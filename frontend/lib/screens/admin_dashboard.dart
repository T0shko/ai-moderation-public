import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
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

  final _chatController = TextEditingController();
  final _chatScrollController = ScrollController();
  final List<Map<String, String>> _chatMessages = [];
  bool _isChatSending = false;
  String _chatProvider = 'combined';

  static const _sections = ['Overview', 'Sandbox', 'Concierge', 'Staff', 'Press'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _sections.length, vsync: this);
    _tabController.addListener(() => setState(() {}));
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
      return;
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
      _snack(approved ? 'Set in print' : 'Spiked');
      _loadData();
    } on AuthException {
      return;
    } catch (_) {
      _snack('Failed to moderate comment', isError: true);
    }
  }

  void _updateRole(int userId, String role) async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.updateUserRole(userId, role);
      _snack('Role updated');
      _loadData();
    } on AuthException {
      return;
    } catch (_) {
      _snack('Failed to update role', isError: true);
    }
  }

  void _saveAiSettings() async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.updateAiSettings(_threshold, _activeModel);
      _snack('Settings saved');
    } on AuthException {
      return;
    } catch (_) {
      _snack('Failed to save settings', isError: true);
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
      _snack('Filed for review');
      _loadData();
    } on AuthException {
      return;
    } catch (_) {
      _snack('Failed to post', isError: true);
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
    } catch (_) {
      _snack('Analysis failed', isError: true);
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
        _snack('Could not read the selected image', isError: true);
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
        _snack('Image staged');
      }
    } on AuthException {
      return;
    } catch (e) {
      _snack('Could not pick image: $e', isError: true);
    }
  }

  void _analyzeVisionImage() async {
    if (_selectedImageBytes == null || _selectedImageName == null) {
      _snack('Choose an image first', isError: true);
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
        _snack('Verdict in');
      }
    } catch (e) {
      _snack('Vision Lab failed: $e', isError: true);
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
        _snack('Refreshed');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _visionLabError = e.toString().replaceFirst('Exception: ', '');
        });
      }
      _snack('Could not refresh', isError: true);
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
      final response =
          await api.sendChatMessage(text, provider: _chatProvider);
      if (mounted) {
        setState(() => _chatMessages.add({
              'role': 'assistant',
              'content': response['response'] ?? 'No response',
            }));
        _scrollChat();
      }
    } on AuthException {
      return;
    } catch (e) {
      if (mounted) {
        setState(() => _chatMessages.add({
              'role': 'error',
              'content':
                  'Failed: ${e.toString().replaceFirst('Exception: ', '')}',
            }));
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

  void _snack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTheme.mono(size: 11, color: AppTheme.paperLight),
        ),
        backgroundColor: isError ? AppTheme.rust : AppTheme.ink,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
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
      backgroundColor: AppTheme.paper,
      body: NexusBackground(
        child: SafeArea(
          child: Column(
            children: [
              _masthead(),
              _sectionRule(),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AppTheme.ink, strokeWidth: 1.8),
                      )
                    : _error != null
                        ? _errorState()
                        : TabBarView(
                            controller: _tabController,
                            children: [
                              _overviewTab(),
                              _sandboxTab(),
                              _conciergeTab(),
                              _staffTab(),
                              _pressTab(),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _masthead() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.paperLight,
        border: Border(
          bottom: BorderSide(color: AppTheme.ink, width: 2),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('EDITORIAL OFFICE \u2014 ADMIN',
                  style: AppTheme.label(color: AppTheme.textTertiary)),
              const Spacer(),
              if (_visionLabInfo != null)
                StatusBadge(
                  text: 'VISION LIVE',
                  color: AppTheme.persimmon,
                  showPulse: true,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: AppTheme.display(
                      size: 32,
                      weight: FontWeight.w700,
                      letterSpacing: -1.2,
                    ),
                    children: [
                      const TextSpan(text: 'The '),
                      TextSpan(
                        text: 'Editor\u2019s',
                        style: AppTheme.display(
                          size: 32,
                          weight: FontWeight.w400,
                          style: FontStyle.italic,
                          letterSpacing: -1.2,
                          color: AppTheme.persimmon,
                        ),
                      ),
                      const TextSpan(text: ' Desk'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AppIconButton(icon: Icons.refresh, onPressed: _loadData),
              const SizedBox(width: 8),
              AppIconButton(
                icon: Icons.logout,
                onPressed: _logout,
                color: AppTheme.rust,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionRule() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.paperLight,
        border: Border(
          bottom: BorderSide(color: AppTheme.hairline, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_sections.length, (i) {
            final active = _tabController.index == i;
            return GestureDetector(
              onTap: () => _tabController.animateTo(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      '0${i + 1}',
                      style: AppTheme.mono(
                        size: 10,
                        color: active
                            ? AppTheme.persimmon
                            : AppTheme.textTertiary,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        border: active
                            ? const Border(
                                bottom: BorderSide(
                                  color: AppTheme.persimmon,
                                  width: 2,
                                ),
                              )
                            : null,
                      ),
                      child: Text(
                        _sections[i].toUpperCase(),
                        style: AppTheme.mono(
                          size: 11,
                          color: active ? AppTheme.ink : AppTheme.textSecondary,
                          weight: active ? FontWeight.w700 : FontWeight.w500,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CrosshairMark(size: 24, color: AppTheme.rust),
          const SizedBox(height: 12),
          Text('CONNECTION ISSUE',
              style: AppTheme.label(color: AppTheme.rust)),
          const SizedBox(height: 18),
          SizedBox(
            width: 180,
            child: ActionButton(
              text: 'Retry',
              icon: Icons.refresh,
              onPressed: _loadData,
              height: 44,
            ),
          ),
        ],
      ),
    );
  }

  // ── Overview ─────────────────────────────────────────────────────
  Widget _overviewTab() {
    final approved =
        _allComments.where((c) => c['status'] == 'APPROVED').length;
    final rejected =
        _allComments.where((c) => c['status'] == 'REJECTED').length;
    final pending =
        _allComments.where((c) => c['status'] == 'PENDING').length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatTile(
                value: '${_allComments.length}',
                label: 'Total',
                icon: Icons.article_outlined,
                color: AppTheme.azure,
              ),
              const SizedBox(width: 12),
              StatTile(
                value: '$approved',
                label: 'In print',
                icon: Icons.check,
                color: AppTheme.olive,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              StatTile(
                value: '$rejected',
                label: 'Spiked',
                icon: Icons.close,
                color: AppTheme.rust,
              ),
              const SizedBox(width: 12),
              StatTile(
                value: '$pending',
                label: 'In queue',
                icon: Icons.schedule_outlined,
                color: AppTheme.honey,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              StatTile(
                value: '${_users.length}',
                label: 'Staff',
                icon: Icons.people_outline,
                color: AppTheme.ink,
              ),
              const SizedBox(width: 12),
              const Expanded(child: SizedBox()),
            ],
          ),
          const SizedBox(height: 24),
          SectionHeader(
            title: 'Latest Bulletins',
            subtitle: 'Most recent dispatches across the wire.',
            index: '\u00A7',
          ),
          ..._allComments.take(6).toList().asMap().entries.map(
                (e) => _miniEntry(e.value, e.key + 1),
              ),
        ],
      ),
    );
  }

  Widget _miniEntry(dynamic comment, int index) {
    final status = comment['status'] ?? 'PENDING';
    final sentiment = comment['sentiment'] ?? 'NEUTRAL';
    final confidence = (comment['confidenceScore'] ?? 0.0) * 100;
    final statusColor = status == 'APPROVED'
        ? AppTheme.olive
        : status == 'REJECTED'
            ? AppTheme.rust
            : AppTheme.honey;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        padding: const EdgeInsets.all(16),
        accentColor: statusColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FolioTag(number: index.toString().padLeft(3, '0')),
                const Spacer(),
                Text(sentiment,
                    style: AppTheme.label(
                        color: AppTheme.textTertiary, size: 10)),
                const SizedBox(width: 8),
                Text('${confidence.toStringAsFixed(0)}%',
                    style: AppTheme.mono(
                        size: 10, color: AppTheme.textTertiary)),
                const SizedBox(width: 10),
                StatusBadge(text: status, color: statusColor),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              comment['author']?['username'] ?? 'Unknown',
              style: AppTheme.body(
                size: 13,
                color: AppTheme.ink,
                weight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              comment['content'] ?? '',
              style: AppTheme.body(size: 14, color: AppTheme.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (status == 'PENDING') ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ActionButton(
                      text: 'Spike',
                      onPressed: () => _moderateComment(comment['id'], false),
                      secondary: true,
                      backgroundColor: AppTheme.paperLight,
                      height: 38,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ActionButton(
                      text: 'Set',
                      onPressed: () => _moderateComment(comment['id'], true),
                      backgroundColor: AppTheme.olive,
                      height: 38,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Sandbox (text + vision) ────────────────────────────────────
  Widget _sandboxTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _visionLabPanel(),
          const SizedBox(height: 20),
          _textSandboxPanel(),
          if (_lastTestResult != null) ...[
            const SizedBox(height: 16),
            _textResult(),
          ],
        ],
      ),
    );
  }

  Widget _visionLabPanel() {
    final totalAnalyses =
        _visionLabInfo?['totalAnalyses']?.toString() ?? '0';
    final maxSizeLabel =
        _visionLabInfo?['maxSizeLabel']?.toString() ?? '10 MB';
    final acceptedTypes =
        (_visionLabInfo?['acceptedTypes'] as List?)
                ?.map((t) =>
                    t.toString().replaceFirst('image/', '').toUpperCase())
                .join('  \u00B7  ') ??
            'JPEG  \u00B7  PNG  \u00B7  GIF  \u00B7  WEBP';
    final staged = _selectedImageName != null;

    return SurfaceCard(
      padding: const EdgeInsets.all(22),
      accentColor: AppTheme.persimmon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('§ VISION LAB',
                  style: AppTheme.label(color: AppTheme.persimmon, size: 11)),
              const Spacer(),
              AppIconButton(
                icon: Icons.sync_rounded,
                onPressed: _refreshVisionLabInfo,
                tooltip: 'Refresh',
                size: 34,
              ),
            ],
          ),
          const SizedBox(height: 10),
          RichText(
            text: TextSpan(
              style: AppTheme.display(
                size: 30,
                weight: FontWeight.w700,
                letterSpacing: -1,
                height: 1.05,
              ),
              children: [
                const TextSpan(text: 'Drop a photograph,\nrun the '),
                TextSpan(
                  text: 'verdict',
                  style: AppTheme.display(
                    size: 30,
                    weight: FontWeight.w400,
                    style: FontStyle.italic,
                    letterSpacing: -1,
                    color: AppTheme.persimmon,
                    height: 1.05,
                  ),
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'JSON transport. GET reports lab metadata, POST runs the analysis.',
            style: AppTheme.body(
              size: 14,
              color: AppTheme.textSecondary,
              style: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _ledgerCell('TOTAL', totalAnalyses),
              const SizedBox(width: 10),
              _ledgerCell('MAX SIZE', maxSizeLabel),
              const SizedBox(width: 10),
              _ledgerCell('METHODS', 'GET + POST'),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: AppTheme.paper,
              border: Border.all(
                color: staged ? AppTheme.persimmon : AppTheme.hairline,
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: staged
                            ? AppTheme.persimmonSoft
                            : AppTheme.paperLight,
                        border: Border.all(
                          color: staged ? AppTheme.persimmon : AppTheme.ink,
                          width: 1.2,
                        ),
                      ),
                      child: Icon(
                        staged ? Icons.check : Icons.image_outlined,
                        size: 20,
                        color: staged ? AppTheme.persimmon : AppTheme.ink,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            staged
                                ? (_selectedImageName ?? 'Image staged')
                                : 'No image staged',
                            style: AppTheme.body(
                              size: 14,
                              color: AppTheme.ink,
                              weight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            staged
                                ? '${(_selectedImageSize! / 1024).toStringAsFixed(1)} KB \u00B7 ${_selectedImageContentType ?? 'image/jpeg'}'
                                : 'Choose a file and run the press.',
                            style: AppTheme.mono(
                              size: 10,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusBadge(
                      text: staged ? 'READY' : 'IDLE',
                      color: staged ? AppTheme.persimmon : AppTheme.slate,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  acceptedTypes,
                  style: AppTheme.mono(size: 10, color: AppTheme.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ActionButton(
                  text: 'Choose image',
                  icon: Icons.add_photo_alternate_outlined,
                  onPressed: _pickVisionImage,
                  secondary: true,
                  backgroundColor: AppTheme.paperLight,
                  height: 44,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ActionButton(
                  text: 'Run verdict',
                  icon: Icons.bolt_outlined,
                  isLoading: _isTestingImage,
                  onPressed: _selectedImageBytes == null
                      ? null
                      : _analyzeVisionImage,
                  backgroundColor: AppTheme.persimmon,
                  height: 44,
                ),
              ),
            ],
          ),
          if (_visionLabError != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.rustSoft,
                border: Border.all(color: AppTheme.rust),
              ),
              child: Text(
                _visionLabError!,
                style: AppTheme.mono(size: 11, color: AppTheme.rust),
              ),
            ),
          ],
          if (_lastImageResult != null) ...[
            const SizedBox(height: 18),
            _imageResult(),
          ],
        ],
      ),
    );
  }

  Widget _textSandboxPanel() {
    return SurfaceCard(
      padding: const EdgeInsets.all(22),
      accentColor: AppTheme.ink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Text Sandbox',
            subtitle: 'Try moderation pipeline without publishing.',
            index: '\u00A7',
          ),
          AppTextField(
            controller: _testCommentController,
            label: 'Test text',
            hint: 'Type to inspect…',
            maxLines: 4,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ActionButton(
                  text: 'Analyze',
                  icon: Icons.psychology_outlined,
                  isLoading: _isPostingTest,
                  onPressed: _testAnalyze,
                  secondary: true,
                  backgroundColor: AppTheme.paperLight,
                  height: 46,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ActionButton(
                  text: 'File comment',
                  icon: Icons.send_outlined,
                  isLoading: _isPostingTest,
                  onPressed: _postTestComment,
                  height: 46,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ledgerCell(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.paper,
          border: Border.all(color: AppTheme.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTheme.label(color: AppTheme.textTertiary)),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono(
                size: 13,
                color: AppTheme.ink,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textResult() {
    final sentiment = _lastTestResult!['sentiment'] ?? 'UNKNOWN';
    final confidence = (_lastTestResult!['confidence'] ?? 0.0) * 100;
    final wouldApprove = _lastTestResult!['wouldBeAutoApproved'] ?? false;
    final sentColor = sentiment == 'NEGATIVE'
        ? AppTheme.rust
        : sentiment == 'POSITIVE'
            ? AppTheme.olive
            : AppTheme.azure;

    return SurfaceCard(
      padding: const EdgeInsets.all(22),
      accentColor: sentColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Verdict', index: '\u00B6'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _kv('Sentiment', sentiment, sentColor)),
              Expanded(
                child: _kv(
                  'Confidence',
                  '${confidence.toStringAsFixed(1)}%',
                  AppTheme.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                wouldApprove ? Icons.check : Icons.block,
                color: wouldApprove ? AppTheme.olive : AppTheme.rust,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                wouldApprove
                    ? 'Would be set in print automatically'
                    : 'Would be held for review',
                style: AppTheme.body(
                  size: 13,
                  color: wouldApprove ? AppTheme.olive : AppTheme.rust,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '\u201C${_lastTestResult!['content'] ?? ''}\u201D',
            style: AppTheme.body(
              size: 13,
              color: AppTheme.textTertiary,
              style: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageResult() {
    final status = _lastImageResult!['status'] ?? 'UNKNOWN';
    final categories = ((_lastImageResult!['categories'] as List?) ?? const [])
        .map((item) => item.toString())
        .toList();
    final reason = _lastImageResult!['reason'] ?? '';
    final confidence =
        ((_lastImageResult!['confidence'] ?? 0.0) as num) * 100;
    final filename = _lastImageResult!['filename'] ??
        _selectedImageName ??
        'Uploaded image';
    final engine = _lastImageResult!['engine'] ?? 'Spatial Grid Ensemble';
    final analysisId = _lastImageResult!['analysisId']?.toString() ?? '--';
    final statusColor = status == 'SAFE'
        ? AppTheme.olive
        : status == 'REJECTED'
            ? AppTheme.rust
            : AppTheme.honey;

    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      accentColor: statusColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Vision Verdict',
                    style: AppTheme.display(
                      size: 24,
                      weight: FontWeight.w700,
                      letterSpacing: -0.8,
                    )),
              ),
              StatusBadge(text: status, color: statusColor, stamp: true),
            ],
          ),
          const SizedBox(height: 4),
          Text(filename,
              style:
                  AppTheme.mono(size: 11, color: AppTheme.textTertiary)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _kv('Confidence',
                    '${confidence.toStringAsFixed(1)}%', statusColor),
              ),
              Expanded(child: _kv('Analysis ID', analysisId, AppTheme.ink)),
              Expanded(child: _kv('Engine', engine, AppTheme.persimmon)),
            ],
          ),
          const SizedBox(height: 14),
          Text('REASONING',
              style: AppTheme.label(color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          Text(
            reason.isEmpty ? 'No significant violations detected.' : reason,
            style: AppTheme.body(size: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 14),
          Text('CATEGORIES',
              style: AppTheme.label(color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: categories.isEmpty
                ? [StatusBadge(text: 'NONE', color: AppTheme.slate)]
                : categories
                    .map(
                      (c) => StatusBadge(text: c, color: statusColor),
                    )
                    .toList(),
          ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: AppTheme.label(color: AppTheme.textTertiary)),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTheme.display(
            size: 22,
            weight: FontWeight.w700,
            color: color,
            letterSpacing: -0.6,
          ),
        ),
      ],
    );
  }

  // ── Concierge (chat) ───────────────────────────────────────────
  Widget _conciergeTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.hairline)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.persimmonSoft,
                  border: Border.all(color: AppTheme.persimmon, width: 1.2),
                ),
                child: const Icon(Icons.auto_awesome,
                    color: AppTheme.persimmon, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('AI CONCIERGE',
                    style: AppTheme.label(color: AppTheme.ink, size: 11)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.paperLight,
                  border: Border.all(color: AppTheme.ink),
                ),
                child: DropdownButton<String>(
                  value: _chatProvider,
                  onChanged: (v) => setState(() => _chatProvider = v!),
                  underline: const SizedBox(),
                  isDense: true,
                  dropdownColor: AppTheme.paperLight,
                  style: AppTheme.mono(
                    size: 11,
                    color: AppTheme.ink,
                    weight: FontWeight.w600,
                  ),
                  items: ['combined', 'groq', 'opennlp', 'huggingface']
                      .map((m) =>
                          DropdownMenuItem(value: m, child: Text(m.toUpperCase())))
                      .toList(),
                ),
              ),
              const SizedBox(width: 8),
              AppIconButton(
                icon: Icons.delete_outline,
                onPressed: () async {
                  try {
                    await Provider.of<ApiService>(context, listen: false)
                        .clearChatHistory();
                    setState(() => _chatMessages.clear());
                  } catch (_) {}
                },
                color: AppTheme.rust,
              ),
            ],
          ),
        ),
        Expanded(
          child: _chatMessages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CrosshairMark(
                          size: 18, color: AppTheme.persimmon),
                      const SizedBox(height: 10),
                      Text('READY FOR YOUR QUERY',
                          style: AppTheme.label(
                              color: AppTheme.textTertiary, size: 10)),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _chatScrollController,
                  padding: const EdgeInsets.all(20),
                  itemCount: _chatMessages.length + (_isChatSending ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= _chatMessages.length) return _typingBlock();
                    return _chatBlock(_chatMessages[i]);
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.hairline)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AppTextField(
                  controller: _chatController,
                  label: 'Query',
                  hint: 'Ask the desk…',
                  onSubmitted: (_) => _sendChatMessage(),
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 140,
                child: ActionButton(
                  text: 'Wire',
                  icon: Icons.send_outlined,
                  onPressed: _isChatSending ? null : _sendChatMessage,
                  isLoading: _isChatSending,
                  height: 44,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chatBlock(Map<String, String> msg) {
    final isUser = msg['role'] == 'user';
    final isError = msg['role'] == 'error';
    final color =
        isError ? AppTheme.rust : (isUser ? AppTheme.persimmon : AppTheme.ink);
    final label = isUser
        ? 'YOU'
        : isError
            ? 'WIRE ERROR'
            : 'CONCIERGE';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 1, color: color),
              const SizedBox(width: 8),
              Text(label, style: AppTheme.label(color: color, size: 10)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            msg['content'] ?? '',
            style: AppTheme.body(
              size: 14,
              color: isError ? AppTheme.rust : AppTheme.ink,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _typingBlock() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Text('CONCIERGE',
              style: AppTheme.label(color: AppTheme.persimmon, size: 10)),
          const SizedBox(width: 10),
          Text('typing…',
              style: AppTheme.body(
                size: 13,
                color: AppTheme.textTertiary,
                style: FontStyle.italic,
              )),
        ],
      ),
    );
  }

  // ── Staff (users) ──────────────────────────────────────────────
  Widget _staffTab() {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _users.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) =>
          _staffCard(_users[index], index + 1),
    );
  }

  Widget _staffCard(dynamic user, int index) {
    final role = (user['role'] ?? 'USER').toString();
    final roleColor = role.contains('ADMIN')
        ? AppTheme.persimmon
        : role.contains('MODERATOR')
            ? AppTheme.honey
            : AppTheme.azure;
    final username = user['username'] ?? 'Unknown';
    final initial = username.toString().substring(0, 1).toUpperCase();

    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      accentColor: roleColor,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.paperLight,
              border: Border.all(color: AppTheme.ink),
            ),
            child: Center(
              child: Text(
                initial,
                style: AppTheme.display(
                  size: 26,
                  weight: FontWeight.w700,
                  letterSpacing: -1,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(username,
                        style: AppTheme.body(
                          size: 16,
                          color: AppTheme.ink,
                          weight: FontWeight.w600,
                        )),
                    const SizedBox(width: 10),
                    Text('N\u00B0 ${index.toString().padLeft(3, '0')}',
                        style: AppTheme.mono(
                            size: 10, color: AppTheme.textTertiary)),
                  ],
                ),
                const SizedBox(height: 6),
                StatusBadge(text: role, color: roleColor),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (newRole) => _updateRole(user['id'], newRole),
            icon: const Icon(Icons.more_horiz, color: AppTheme.ink),
            itemBuilder: (_) => [
              _roleItem('USER', 'Reader'),
              _roleItem('MODERATOR', 'Sub-editor'),
              _roleItem('ADMIN', 'Editor-in-Chief'),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _roleItem(String value, String label) {
    return PopupMenuItem(
      value: value,
      child: Text(label,
          style: AppTheme.body(
            size: 14,
            color: AppTheme.ink,
          )),
    );
  }

  // ── Press settings ─────────────────────────────────────────────
  Widget _pressTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: SurfaceCard(
        padding: const EdgeInsets.all(22),
        accentColor: AppTheme.persimmon,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'AI Model',
              subtitle: 'How the desk decides what reaches print.',
              index: '\u00A7',
            ),
            Row(
              children: [
                Text('Confidence Threshold',
                    style: AppTheme.body(
                      size: 14,
                      color: AppTheme.ink,
                      weight: FontWeight.w600,
                    )),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.persimmonSoft,
                    border: Border.all(color: AppTheme.persimmon),
                  ),
                  child: Text(
                    _threshold.toStringAsFixed(2),
                    style: AppTheme.mono(
                      size: 11,
                      color: AppTheme.persimmon,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            Slider(
              value: _threshold,
              min: 0,
              max: 1,
              divisions: 20,
              onChanged: (v) => setState(() => _threshold = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Active Model',
                    style: AppTheme.body(
                      size: 14,
                      color: AppTheme.ink,
                      weight: FontWeight.w600,
                    )),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.paperLight,
                    border: Border.all(color: AppTheme.ink),
                  ),
                  child: DropdownButton<String>(
                    value: _activeModel,
                    onChanged: (v) => setState(() => _activeModel = v!),
                    underline: const SizedBox(),
                    isDense: true,
                    dropdownColor: AppTheme.paperLight,
                    style: AppTheme.mono(
                      size: 11,
                      color: AppTheme.ink,
                      weight: FontWeight.w600,
                    ),
                    items: _modelItems()
                        .map((m) => DropdownMenuItem(
                            value: m, child: Text(m.toUpperCase())))
                        .toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ActionButton(
              text: 'Save settings',
              icon: Icons.save_outlined,
              onPressed: _saveAiSettings,
            ),
          ],
        ),
      ),
    );
  }

  List<String> _modelItems() {
    final defaults = ['ensemble', 'wordfilter', 'huggingface', 'claude'];
    if (!defaults.contains(_activeModel)) {
      return [_activeModel, ...defaults];
    }
    return defaults;
  }
}
