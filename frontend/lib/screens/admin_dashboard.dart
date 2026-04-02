import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _users = [];
  List<dynamic> _allComments = [];
  bool _isLoading = false;
  String? _error;
  double _threshold = 0.6;
  String _activeModel = 'ensemble';

  // Test tab state
  final _testCommentController = TextEditingController();
  bool _isPostingTest = false;
  Map<String, dynamic>? _lastTestResult;
  bool _isTestingImage = false;
  Map<String, dynamic>? _lastImageResult;
  Map<String, dynamic>? _visionLabInfo;
  String? _visionLabError;
  String? _selectedImageName;
  int? _selectedImageSize;
  Uint8List? _selectedImageBytes;
  String? _selectedImageContentType;

  // Chat tab state
  final _chatController = TextEditingController();
  final _chatScrollController = ScrollController();
  final List<Map<String, String>> _chatMessages = [];
  bool _isChatSending = false;
  String _chatProvider = 'combined';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _testCommentController.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final users = await api.getUsers();
      final comments = await api.getAllCommentsAdmin();
      Map<String, dynamic>? visionLabInfo;
      String? visionLabError;
      try {
        final settings = await api.getAiSettings();
        _threshold = (settings['threshold'] ?? 0.6).toDouble();
        _activeModel = settings['activeModel'] ?? 'ensemble';
      } catch (_) {}
      try {
        visionLabInfo = await api.getVisionLabInfo();
      } catch (e) {
        visionLabError = e.toString().replaceFirst('Exception: ', '');
      }
      if (mounted) {
        setState(() {
          _users = users;
          _allComments = comments;
          _visionLabInfo = visionLabInfo;
          _visionLabError = visionLabError;
        });
      }
    } on AuthException {
      return; // Already redirected to login
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _moderateComment(int id, bool approved) async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.moderateComment(id, approved);
      _showSnackBar(approved ? 'Comment approved' : 'Comment rejected');
      _loadData();
    } on AuthException {
      return;
    } catch (e) {
      _showSnackBar('Failed to moderate comment', isError: true);
    }
  }

  void _updateRole(int userId, String role) async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.updateUserRole(userId, role);
      _showSnackBar('Role updated');
      _loadData();
    } on AuthException {
      return;
    } catch (e) {
      _showSnackBar('Failed to update role', isError: true);
    }
  }

  void _saveAiSettings() async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.updateAiSettings(_threshold, _activeModel);
      _showSnackBar('Settings saved');
    } on AuthException {
      return;
    } catch (e) {
      _showSnackBar('Failed to save settings', isError: true);
    }
  }

  void _postTestComment() async {
    final text = _testCommentController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isPostingTest = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.postComment(text);
      _testCommentController.clear();
      _showSnackBar('Comment posted — check Overview for result');
      _loadData(); // Refresh to see the new comment
    } on AuthException {
      return;
    } catch (e) {
      _showSnackBar('Failed to post comment', isError: true);
    } finally {
      if (mounted) setState(() => _isPostingTest = false);
    }
  }

  void _testAnalyze() async {
    final text = _testCommentController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isPostingTest = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final result = await api.testSentiment(text);
      if (mounted) setState(() => _lastTestResult = result);
    } catch (e) {
      _showSnackBar('Analysis failed', isError: true);
    } finally {
      if (mounted) setState(() => _isPostingTest = false);
    }
  }

  void _pickVisionImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: false,
        withData: true,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'gif', 'webp'],
      );
      if (result == null || result.files.isEmpty) return;

      final pickedFile = result.files.single;
      final bytes = pickedFile.bytes;
      if (bytes == null || bytes.isEmpty) {
        _showSnackBar('Could not read the selected image', isError: true);
        return;
      }

      if (mounted) {
        setState(() {
          _selectedImageName = pickedFile.name;
          _selectedImageSize = bytes.length;
          _selectedImageBytes = bytes;
          _selectedImageContentType = pickedFile.extension != null
              ? _extensionToContentType(pickedFile.extension!)
              : null;
          _lastImageResult = null;
        });
        _showSnackBar('Image staged in Vision Lab');
      }
    } on AuthException {
      return;
    } catch (e) {
      _showSnackBar('Could not pick image: $e', isError: true);
    }
  }

  void _analyzeVisionImage() async {
    if (_selectedImageBytes == null || _selectedImageName == null) {
      _showSnackBar('Choose an image first', isError: true);
      return;
    }

    setState(() => _isTestingImage = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final imageResult = await api.analyzeVisionImage(
        _selectedImageBytes!,
        _selectedImageName!,
        _selectedImageContentType,
      );

      Map<String, dynamic>? visionLabInfo = _visionLabInfo;
      String? visionLabError;
      try {
        visionLabInfo = await api.getVisionLabInfo();
      } catch (e) {
        visionLabError = e.toString().replaceFirst('Exception: ', '');
      }

      if (mounted) {
        setState(() {
          _lastImageResult = imageResult;
          _visionLabInfo = visionLabInfo;
          _visionLabError = visionLabError;
        });
        _showSnackBar('Vision Lab analysis completed');
      }
    } catch (e) {
      _showSnackBar('Vision Lab failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isTestingImage = false);
    }
  }

  void _refreshVisionLabInfo() async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final info = await api.getVisionLabInfo();
      if (mounted) {
        setState(() {
          _visionLabInfo = info;
          _visionLabError = null;
        });
        _showSnackBar('Vision Lab refreshed');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _visionLabError = e.toString().replaceFirst('Exception: ', '');
        });
      }
      _showSnackBar('Could not refresh Vision Lab', isError: true);
    }
  }

  String _extensionToContentType(String extension) {
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  void _sendChatMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _isChatSending) return;

    setState(() {
      _chatMessages.add({'role': 'user', 'content': text});
      _isChatSending = true;
    });
    _chatController.clear();
    _scrollChat();

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final response = await api.sendChatMessage(text, provider: _chatProvider);
      if (mounted) {
        setState(
          () => _chatMessages.add({
            'role': 'assistant',
            'content': response['response'] ?? 'No response',
          }),
        );
        _scrollChat();
      }
    } on AuthException {
      return;
    } catch (e) {
      if (mounted) {
        setState(
          () => _chatMessages.add({
            'role': 'error',
            'content':
                'Failed: ${e.toString().replaceFirst('Exception: ', '')}',
          }),
        );
      }
    } finally {
      if (mounted) setState(() => _isChatSending = false);
    }
  }

  void _scrollChat() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.dmSans(fontSize: 14)),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
      ),
    );
  }

  void _logout() async {
    await Provider.of<ApiService>(context, listen: false).logout();
    if (mounted) Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: NexusBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildTabBar(),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primary,
                        ),
                      )
                    : _error != null
                    ? _buildErrorState()
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildOverviewTab(),
                          _buildTestTab(),
                          _buildChatTab(),
                          _buildUsersTab(),
                          _buildSettingsTab(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.bgSecondary.withValues(alpha: 0.7),
        border: const Border(bottom: BorderSide(color: AppTheme.borderDefault)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppTheme.glow(AppTheme.coral, 0.2),
            ),
            child: const Icon(
              Icons.admin_panel_settings_outlined,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Admin',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'System management',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: AppTheme.textTertiary,
                  ),
                ),
                if (_visionLabInfo != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Vision Lab live',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.peach,
                    ),
                  ),
                ],
              ],
            ),
          ),
          AppIconButton(icon: Icons.refresh_rounded, onPressed: _loadData),
          const SizedBox(width: 8),
          AppIconButton(
            icon: Icons.logout_rounded,
            onPressed: _logout,
            color: AppTheme.error,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: AppTheme.bgSecondary.withValues(alpha: 0.5),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        indicatorColor: AppTheme.primary,
        indicatorWeight: 2,
        labelColor: AppTheme.primary,
        unselectedLabelColor: AppTheme.textTertiary,
        labelStyle: GoogleFonts.dmSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        tabAlignment: TabAlignment.start,
        tabs: const [
          Tab(text: 'Overview'),
          Tab(text: 'Test'),
          Tab(text: 'Chat'),
          Tab(text: 'Users'),
          Tab(text: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 48,
            color: AppTheme.textTertiary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Connection issue',
            style: GoogleFonts.playfairDisplay(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          ActionButton(
            text: 'Retry',
            icon: Icons.refresh,
            onPressed: _loadData,
            width: 140,
            height: 44,
          ),
        ],
      ),
    );
  }

  // ── Overview Tab ──────────────────────────────────────────────
  Widget _buildOverviewTab() {
    final approved = _allComments
        .where((c) => c['status'] == 'APPROVED')
        .length;
    final rejected = _allComments
        .where((c) => c['status'] == 'REJECTED')
        .length;
    final pending = _allComments.where((c) => c['status'] == 'PENDING').length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatTile(
                value: '${_allComments.length}',
                label: 'Total Posts',
                icon: Icons.article_outlined,
                color: AppTheme.info,
              ),
              const SizedBox(width: 10),
              StatTile(
                value: '$approved',
                label: 'Approved',
                icon: Icons.check_circle_outline,
                color: AppTheme.success,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              StatTile(
                value: '$rejected',
                label: 'Rejected',
                icon: Icons.cancel_outlined,
                color: AppTheme.error,
              ),
              const SizedBox(width: 10),
              StatTile(
                value: '$pending',
                label: 'Pending',
                icon: Icons.schedule_outlined,
                color: AppTheme.warning,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              StatTile(
                value: '${_users.length}',
                label: 'Users',
                icon: Icons.people_outline,
                color: AppTheme.plum,
              ),
              const SizedBox(width: 10),
              const Expanded(child: SizedBox()),
            ],
          ),
          const SizedBox(height: 20),
          SectionHeader(
            title: 'Recent Activity',
            subtitle:
                'Last ${_allComments.length > 5 ? 5 : _allComments.length} posts',
          ),
          ..._allComments.take(5).map((c) => _buildMiniComment(c)),
        ],
      ),
    );
  }

  Widget _buildMiniComment(dynamic comment) {
    final status = comment['status'] ?? 'PENDING';
    final sentiment = comment['sentiment'] ?? 'NEUTRAL';
    final confidence = (comment['confidenceScore'] ?? 0.0) * 100;
    final statusColor = status == 'APPROVED'
        ? AppTheme.success
        : status == 'REJECTED'
        ? AppTheme.error
        : AppTheme.warning;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        padding: const EdgeInsets.all(14),
        accentColor: statusColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    comment['author']?['username'] ?? 'Unknown',
                    style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                StatusBadge(text: status, color: statusColor),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              comment['content'] ?? '',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '$sentiment',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${confidence.toStringAsFixed(0)}% confidence',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                  ),
                ),
                const Spacer(),
                if (status == 'PENDING') ...[
                  GestureDetector(
                    onTap: () => _moderateComment(comment['id'], true),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 16,
                        color: AppTheme.success,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _moderateComment(comment['id'], false),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 16,
                        color: AppTheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Test Tab (Post comments + Vision Lab) ─────────────────────
  Widget _buildTestTab() {
    final totalAnalyses = _visionLabInfo?['totalAnalyses']?.toString() ?? '0';
    final maxSizeLabel = _visionLabInfo?['maxSizeLabel']?.toString() ?? '10 MB';
    final acceptedTypes =
        (_visionLabInfo?['acceptedTypes'] as List?)
            ?.map(
              (type) =>
                  type.toString().replaceFirst('image/', '').toUpperCase(),
            )
            .join('  •  ') ??
        'JPEG  •  PNG  •  GIF  •  WEBP';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SurfaceCard(
            padding: EdgeInsets.zero,
            backgroundColor: AppTheme.bgSecondary.withValues(alpha: 0.95),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.coral.withValues(alpha: 0.12),
                    AppTheme.amber.withValues(alpha: 0.08),
                    AppTheme.bgSecondary,
                  ],
                ),
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              ),
              padding: const EdgeInsets.all(22),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 760;
                  final intro = _buildVisionLabIntro(
                    totalAnalyses,
                    maxSizeLabel,
                    acceptedTypes,
                  );
                  final deck = _buildVisionLabDeck(compact);

                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [intro, const SizedBox(height: 18), deck],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 11, child: intro),
                      const SizedBox(width: 18),
                      Expanded(flex: 10, child: deck),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 18),
          SurfaceCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  title: 'Text Sandbox',
                  subtitle:
                      'Keep testing text moderation separately from the new vision pipeline',
                ),
                AppTextField(
                  controller: _testCommentController,
                  label: 'Enter text to test...',
                  prefixIcon: Icons.edit_outlined,
                  maxLines: 4,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ActionButton(
                        text: 'Post Comment',
                        icon: Icons.send_rounded,
                        isLoading: _isPostingTest,
                        onPressed: _postTestComment,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ActionButton(
                        text: 'Analyze Only',
                        icon: Icons.psychology_outlined,
                        isLoading: _isPostingTest,
                        onPressed: _testAnalyze,
                        gradient: AppTheme.accentGradient,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_lastTestResult != null) ...[
            const SizedBox(height: 16),
            _buildTestResult(),
          ],
        ],
      ),
    );
  }

  Widget _buildVisionLabIntro(
    String totalAnalyses,
    String maxSizeLabel,
    String acceptedTypes,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppTheme.bgDeep.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(AppTheme.radiusRound),
            border: Border.all(color: AppTheme.amber.withValues(alpha: 0.22)),
          ),
          child: Text(
            'VISION LAB / WEB SAFE',
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: AppTheme.peach,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Drop in an image. The UI is brand new, the endpoints are new, and the local AI algorithm stays intact.',
          style: GoogleFonts.playfairDisplay(
            fontSize: 32,
            height: 1.05,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Vision Lab uses JSON transport for browser uploads so web clients stop fighting multipart edge cases. GET returns lab metadata, POST runs analysis and stores the result.',
          style: GoogleFonts.dmSans(
            fontSize: 14,
            height: 1.6,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _buildVisionMetaChip(
              Icons.layers_outlined,
              '$totalAnalyses analyses',
            ),
            _buildVisionMetaChip(Icons.cloud_done_outlined, 'GET + POST'),
            _buildVisionMetaChip(Icons.data_object_outlined, 'JSON transport'),
            _buildVisionMetaChip(Icons.sd_storage_outlined, maxSizeLabel),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.bgDeep.withValues(alpha: 0.32),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: AppTheme.borderActive),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Accepted formats',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                acceptedTypes,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  letterSpacing: 0.2,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVisionLabDeck(bool compact) {
    return Column(
      children: [
        SurfaceCard(
          padding: const EdgeInsets.all(18),
          backgroundColor: AppTheme.bgDeep.withValues(alpha: 0.42),
          accentGradient: AppTheme.warmGradient,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Upload Console',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: compact ? 22 : 24,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  AppIconButton(
                    icon: Icons.sync_rounded,
                    onPressed: _refreshVisionLabInfo,
                    tooltip: 'Refresh Vision Lab info',
                    color: AppTheme.amber,
                    backgroundColor: AppTheme.bgSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildVisionDropZone(),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ActionButton(
                      text: 'Choose Image',
                      icon: Icons.add_photo_alternate_outlined,
                      onPressed: _pickVisionImage,
                      gradient: AppTheme.primaryGradient,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ActionButton(
                      text: 'Run Analysis',
                      icon: Icons.bolt_rounded,
                      isLoading: _isTestingImage,
                      onPressed: _selectedImageBytes == null
                          ? null
                          : _analyzeVisionImage,
                      gradient: AppTheme.accentGradient,
                    ),
                  ),
                ],
              ),
              if (_visionLabError != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(
                      color: AppTheme.error.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    _visionLabError!,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: AppTheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_lastImageResult != null) ...[
          const SizedBox(height: 16),
          _buildImageResult(),
        ],
      ],
    );
  }

  Widget _buildVisionDropZone() {
    final staged = _selectedImageName != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: staged
              ? AppTheme.amber.withValues(alpha: 0.35)
              : AppTheme.borderActive,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.bgPrimary.withValues(alpha: 0.92),
            AppTheme.bgTertiary.withValues(alpha: 0.86),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: staged
                      ? AppTheme.accentGradient
                      : AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppTheme.glow(
                    staged ? AppTheme.amber : AppTheme.coral,
                    0.18,
                  ),
                ),
                child: Icon(
                  staged ? Icons.check_rounded : Icons.image_search_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      staged
                          ? (_selectedImageName ?? 'Image ready')
                          : 'No image staged',
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      staged
                          ? '${(_selectedImageSize! / 1024).toStringAsFixed(1)} KB  •  ${_selectedImageContentType ?? 'image/jpeg'}'
                          : 'Choose a browser image file and send it straight to the new Vision Lab endpoint.',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              StatusBadge(
                text: staged ? 'READY' : 'IDLE',
                color: staged ? AppTheme.amber : AppTheme.slate,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.bgDeep.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: AppTheme.borderDefault),
            ),
            child: Row(
              children: [
                _buildMiniStatusColumn('Transport', 'Base64 JSON'),
                const SizedBox(width: 12),
                _buildMiniStatusColumn('Endpoint', '/api/vision-lab'),
                const SizedBox(width: 12),
                _buildMiniStatusColumn('Methods', 'GET + POST'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatusColumn(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              color: AppTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisionMetaChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.bgDeep.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(AppTheme.radiusRound),
        border: Border.all(color: AppTheme.borderDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.peach),
          const SizedBox(width: 8),
          Text(
            text,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestResult() {
    final sentiment = _lastTestResult!['sentiment'] ?? 'UNKNOWN';
    final confidence = (_lastTestResult!['confidence'] ?? 0.0) * 100;
    final wouldApprove = _lastTestResult!['wouldBeAutoApproved'] ?? false;
    final sentColor = sentiment == 'NEGATIVE'
        ? AppTheme.error
        : sentiment == 'POSITIVE'
        ? AppTheme.success
        : AppTheme.info;

    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      accentColor: sentColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Analysis Result'),
          Row(
            children: [
              Expanded(child: _resultRow('Sentiment', sentiment, sentColor)),
              Expanded(
                child: _resultRow(
                  'Confidence',
                  '${confidence.toStringAsFixed(1)}%',
                  AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                wouldApprove ? Icons.check_circle_rounded : Icons.block_rounded,
                color: wouldApprove ? AppTheme.success : AppTheme.error,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                wouldApprove
                    ? 'Would be auto-approved'
                    : 'Would be flagged for review',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: wouldApprove ? AppTheme.success : AppTheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '"${_lastTestResult!['content'] ?? ''}"',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color: AppTheme.textTertiary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.dmSans(fontSize: 11, color: AppTheme.textTertiary),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildImageResult() {
    final status = _lastImageResult!['status'] ?? 'UNKNOWN';
    final categories = ((_lastImageResult!['categories'] as List?) ?? const [])
        .map((item) => item.toString())
        .toList();
    final reason = _lastImageResult!['reason'] ?? '';
    final confidence = ((_lastImageResult!['confidence'] ?? 0.0) as num) * 100;
    final filename =
        _lastImageResult!['filename'] ?? _selectedImageName ?? 'Uploaded image';
    final engine = _lastImageResult!['engine'] ?? 'Spatial Grid Ensemble';
    final analysisId = _lastImageResult!['analysisId']?.toString() ?? '--';

    final statusColor = status == 'SAFE'
        ? AppTheme.success
        : status == 'REJECTED'
        ? AppTheme.error
        : AppTheme.warning;

    return SurfaceCard(
      padding: EdgeInsets.zero,
      accentGradient: status == 'SAFE'
          ? AppTheme.successGradient
          : status == 'REJECTED'
          ? AppTheme.dangerGradient
          : AppTheme.accentGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  statusColor.withValues(alpha: 0.14),
                  AppTheme.bgSecondary,
                ],
              ),
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vision Verdict',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            filename,
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusBadge(text: status, color: statusColor),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _resultRow(
                        'Confidence',
                        '${confidence.toStringAsFixed(1)}%',
                        statusColor,
                      ),
                    ),
                    Expanded(
                      child: _resultRow(
                        'Analysis ID',
                        analysisId,
                        AppTheme.textPrimary,
                      ),
                    ),
                    Expanded(
                      child: _resultRow('Engine', engine, AppTheme.amber),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Reasoning',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  reason.isEmpty
                      ? 'No significant violations detected.'
                      : reason,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    height: 1.6,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Detected categories',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: categories.isEmpty
                      ? [StatusBadge(text: 'NONE', color: AppTheme.slate)]
                      : categories
                            .map(
                              (category) => StatusBadge(
                                text: category,
                                color: statusColor,
                              ),
                            )
                            .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Chat Tab ──────────────────────────────────────────────────
  Widget _buildChatTab() {
    return Column(
      children: [
        // Chat header with provider select
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.borderDefault)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: AppTheme.accentGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.smart_toy_outlined,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'AI Chat',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.bgTertiary,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  border: Border.all(color: AppTheme.borderDefault),
                ),
                child: DropdownButton<String>(
                  value: _chatProvider,
                  onChanged: (v) => setState(() => _chatProvider = v!),
                  underline: const SizedBox(),
                  isDense: true,
                  dropdownColor: AppTheme.bgElevated,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: AppTheme.textPrimary,
                  ),
                  items: ['combined', 'opennlp', 'huggingface']
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                ),
              ),
              const SizedBox(width: 8),
              AppIconButton(
                icon: Icons.delete_outline_rounded,
                size: 36,
                onPressed: () async {
                  try {
                    await Provider.of<ApiService>(
                      context,
                      listen: false,
                    ).clearChatHistory();
                    setState(() => _chatMessages.clear());
                  } catch (_) {}
                },
                color: AppTheme.error,
              ),
            ],
          ),
        ),
        // Messages
        Expanded(
          child: _chatMessages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_outlined,
                        size: 40,
                        color: AppTheme.textTertiary.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Start chatting',
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _chatScrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _chatMessages.length + (_isChatSending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _chatMessages.length) {
                      return _buildTypingDots();
                    }
                    return _buildChatBubble(_chatMessages[index]);
                  },
                ),
        ),
        // Input
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.borderDefault)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.bgTertiary,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.borderActive),
                  ),
                  child: TextField(
                    controller: _chatController,
                    style: GoogleFonts.dmSans(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    minLines: 1,
                    onSubmitted: (_) => _sendChatMessage(),
                    decoration: InputDecoration(
                      hintText: 'Message...',
                      hintStyle: GoogleFonts.dmSans(
                        color: AppTheme.textTertiary,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _sendChatMessage,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: AppTheme.accentGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatBubble(Map<String, String> msg) {
    final isUser = msg['role'] == 'user';
    final isError = msg['role'] == 'error';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: isError
                  ? AppTheme.error.withValues(alpha: 0.15)
                  : AppTheme.amber.withValues(alpha: 0.15),
              child: Icon(
                isError ? Icons.error_outline : Icons.smart_toy_outlined,
                size: 14,
                color: isError ? AppTheme.error : AppTheme.amber,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? AppTheme.coral.withValues(alpha: 0.12)
                    : isError
                    ? AppTheme.error.withValues(alpha: 0.08)
                    : AppTheme.bgTertiary,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(
                  color: isUser
                      ? AppTheme.coral.withValues(alpha: 0.2)
                      : isError
                      ? AppTheme.error.withValues(alpha: 0.2)
                      : AppTheme.borderDefault,
                ),
              ),
              child: Text(
                msg['content'] ?? '',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: isError ? AppTheme.error : AppTheme.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingDots() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppTheme.amber.withValues(alpha: 0.15),
            child: const Icon(
              Icons.smart_toy_outlined,
              size: 14,
              color: AppTheme.amber,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.bgTertiary,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: AppTheme.borderDefault),
            ),
            child: Text(
              '...',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                color: AppTheme.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Users Tab ─────────────────────────────────────────────────
  Widget _buildUsersTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _users.length,
      itemBuilder: (context, index) => _buildUserCard(_users[index]),
    );
  }

  Widget _buildUserCard(dynamic user) {
    final role = (user['role'] ?? 'USER').toString();
    final roleColor = role.contains('ADMIN')
        ? AppTheme.coral
        : role.contains('MODERATOR')
        ? AppTheme.amber
        : AppTheme.info;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        padding: const EdgeInsets.all(16),
        accentColor: roleColor,
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: roleColor.withValues(alpha: 0.15),
              child: Text(
                (user['username'] ?? '?').substring(0, 1).toUpperCase(),
                style: GoogleFonts.playfairDisplay(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: roleColor,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user['username'] ?? 'Unknown',
                    style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  StatusBadge(text: role, color: roleColor),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (newRole) => _updateRole(user['id'], newRole),
              icon: const Icon(
                Icons.more_vert_rounded,
                color: AppTheme.textSecondary,
              ),
              itemBuilder: (_) => [
                _roleItem('USER', 'User'),
                _roleItem('MODERATOR', 'Moderator'),
                _roleItem('ADMIN', 'Admin'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _roleItem(String value, String label) {
    return PopupMenuItem(
      value: value,
      child: Text(
        label,
        style: GoogleFonts.dmSans(fontSize: 14, color: AppTheme.textPrimary),
      ),
    );
  }

  // ── Settings Tab ──────────────────────────────────────────────
  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SurfaceCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  title: 'AI Model',
                  subtitle: 'Configure moderation thresholds',
                ),
                Row(
                  children: [
                    Text(
                      'Confidence Threshold',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        _threshold.toStringAsFixed(2),
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppTheme.primary,
                    inactiveTrackColor: AppTheme.bgTertiary,
                    thumbColor: AppTheme.primary,
                    overlayColor: AppTheme.primary.withValues(alpha: 0.15),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: _threshold,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    onChanged: (v) => setState(() => _threshold = v),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'Active Model',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.bgTertiary,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        border: Border.all(color: AppTheme.borderDefault),
                      ),
                      child: DropdownButton<String>(
                        value: _activeModel,
                        onChanged: (v) => setState(() => _activeModel = v!),
                        underline: const SizedBox(),
                        isDense: true,
                        dropdownColor: AppTheme.bgElevated,
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          color: AppTheme.textPrimary,
                        ),
                        items: _getModelItems()
                            .map(
                              (m) => DropdownMenuItem(value: m, child: Text(m)),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ActionButton(
                  text: 'Save Settings',
                  icon: Icons.save_rounded,
                  onPressed: _saveAiSettings,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<String> _getModelItems() {
    final defaults = ['ensemble', 'wordfilter', 'huggingface', 'claude'];
    if (!defaults.contains(_activeModel)) {
      return [_activeModel, ...defaults];
    }
    return defaults;
  }
}
