import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;
  List<dynamic> _users = [];
  List<dynamic> _comments = [];
  Map<String, dynamic>? _aiSettings;
  bool _isLoading = false;

  final _thresholdController = TextEditingController();
  String _activeModel = 'ensemble';

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _fadeController.forward();
    _loadData();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  void _loadData() async {
    setState(() => _isLoading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final users = await api.getUsers();
      final settings = await api.getAiSettings();
      final comments = await api.getAllCommentsAdmin();
      if (mounted) {
        setState(() {
          _users = users;
          _aiSettings = settings;
          _comments = comments;
          _thresholdController.text = _aiSettings!['threshold'].toString();
          _activeModel = _aiSettings!['activeModel'];
        });
      }
    } catch (e) {
      if (mounted) _showSnackBar('Error loading data: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
      ),
    );
  }

  void _updateSettings() async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      double threshold = double.parse(_thresholdController.text);
      await api.updateAiSettings(threshold, _activeModel);
      _showSnackBar('AI Settings saved!');
      _loadData();
    } catch (e) {
      _showSnackBar('Error updating settings', isError: true);
    }
  }

  void _changeRole(int userId, String newRole) async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.updateUserRole(userId, newRole);
      _loadData();
      _showSnackBar('Role updated successfully');
    } catch (e) {
      _showSnackBar('Error updating role', isError: true);
    }
  }

  void _moderateComment(int commentId, bool approved) async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.moderateComment(commentId, approved);
      _loadData();
      _showSnackBar(approved ? 'Comment approved' : 'Comment rejected');
    } catch (e) {
      _showSnackBar('Error moderating comment', isError: true);
    }
  }

  void _logout() async {
    await Provider.of<ApiService>(context, listen: false).logout();
    if (mounted) Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    )
                  : FadeTransition(opacity: _fadeAnim, child: _buildBody()),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildAppBar() {
    final titles = [
      'User Management',
      'Content Moderation',
      'AI Settings',
      'Test Console',
    ];
    final icons = [
      Icons.people_alt_outlined,
      Icons.shield_outlined,
      Icons.psychology_outlined,
      Icons.science_outlined,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              boxShadow: AppTheme.glowShadow(AppTheme.primary),
            ),
            child: Icon(icons[_selectedIndex], color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titles[_selectedIndex],
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Text(
                  'Admin Panel',
                  style: TextStyle(fontSize: 12, color: AppTheme.textTertiary),
                ),
              ],
            ),
          ),
          AppIconButton(
            icon: Icons.chat_outlined,
            onPressed: () => Navigator.pushNamed(context, '/chat'),
            tooltip: 'AI Chat',
          ),
          const SizedBox(width: 8),
          AppIconButton(
            icon: Icons.settings_outlined,
            onPressed: () => Navigator.pushNamed(context, '/settings'),
            tooltip: 'Settings',
          ),
          const SizedBox(width: 8),
          AppIconButton(icon: Icons.refresh, onPressed: _loadData),
          const SizedBox(width: 8),
          AppIconButton(
            icon: Icons.logout,
            onPressed: _logout,
            color: AppTheme.error,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: AppTheme.bgSecondary,
        border: Border(top: BorderSide(color: AppTheme.borderDefault)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(0, Icons.people_alt_outlined, 'Users'),
            _buildNavItem(1, Icons.shield_outlined, 'Moderate'),
            _buildNavItem(2, Icons.psychology_outlined, 'AI'),
            _buildNavItem(3, Icons.science_outlined, 'Test'),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedIndex = index);
        _fadeController.reset();
        _fadeController.forward();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected ? AppTheme.primaryGradient : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : AppTheme.textTertiary,
              size: 20,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return _buildUserList();
      case 1:
        return _buildModerationList();
      case 2:
        return _buildAiSettings();
      case 3:
        return _buildTestConsole();
      default:
        return const SizedBox();
    }
  }

  // ── Users tab ───────────────────────────────────────────────────

  Widget _buildUserList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final user = _users[index];
        final role = user['role'] ?? 'USER';

        Color roleColor = role == 'ADMIN'
            ? AppTheme.aurora4
            : role == 'MODERATOR'
            ? AppTheme.aurora1
            : AppTheme.info;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SurfaceCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: Center(
                    child: Text(
                      (user['username'] as String)
                          .substring(0, 1)
                          .toUpperCase(),
                      style: TextStyle(
                        color: roleColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user['username'],
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      StatusBadge(text: role, color: roleColor),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (role) => _changeRole(user['id'], role),
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.bgTertiary,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      border: Border.all(color: AppTheme.borderDefault),
                    ),
                    child: const Icon(
                      Icons.more_vert,
                      color: AppTheme.textSecondary,
                      size: 18,
                    ),
                  ),
                  color: AppTheme.bgElevated,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    side: const BorderSide(color: AppTheme.borderDefault),
                  ),
                  itemBuilder: (context) => [
                    _buildPopupItem(
                      'USER',
                      Icons.person_outline,
                      AppTheme.info,
                    ),
                    _buildPopupItem(
                      'MODERATOR',
                      Icons.verified_user_outlined,
                      AppTheme.aurora1,
                    ),
                    _buildPopupItem(
                      'ADMIN',
                      Icons.admin_panel_settings_outlined,
                      AppTheme.aurora4,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  PopupMenuItem<String> _buildPopupItem(
    String value,
    IconData icon,
    Color color,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Text(value, style: TextStyle(color: color, fontSize: 14)),
        ],
      ),
    );
  }

  // ── Moderation tab ──────────────────────────────────────────────

  Widget _buildModerationList() {
    if (_comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: AppTheme.textTertiary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            const Text(
              'All caught up!',
              style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: _comments.length,
      itemBuilder: (context, index) {
        final comment = _comments[index];
        final sentiment = comment['sentiment'] ?? 'NEUTRAL';
        final confidence = (comment['confidenceScore'] ?? 0.0) * 100;
        final status = comment['status'] ?? 'PENDING';

        Color statusColor = status == 'APPROVED'
            ? AppTheme.success
            : status == 'REJECTED'
            ? AppTheme.error
            : AppTheme.warning;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusBadge(text: status, color: statusColor),
                    const Spacer(),
                    Text(
                      'by ${comment['author']?['username'] ?? 'Unknown'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  comment['content'] ?? '',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _buildSentimentChip(sentiment, confidence),
                    const Spacer(),
                    _buildSmallAction(
                      onTap: () => _moderateComment(comment['id'], false),
                      icon: Icons.close,
                      color: AppTheme.error,
                      label: 'Reject',
                    ),
                    const SizedBox(width: 8),
                    _buildSmallAction(
                      onTap: () => _moderateComment(comment['id'], true),
                      icon: Icons.check,
                      color: AppTheme.success,
                      label: 'Approve',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSentimentChip(String sentiment, double confidence) {
    Color color = sentiment == 'NEGATIVE'
        ? AppTheme.error
        : sentiment == 'POSITIVE'
        ? AppTheme.success
        : AppTheme.info;

    IconData icon = sentiment == 'NEGATIVE'
        ? Icons.sentiment_very_dissatisfied
        : sentiment == 'POSITIVE'
        ? Icons.sentiment_very_satisfied
        : Icons.sentiment_neutral;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 5),
          Text(
            '$sentiment ${confidence.toStringAsFixed(0)}%',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallAction({
    required VoidCallback onTap,
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── AI Settings tab ─────────────────────────────────────────────

  Widget _buildAiSettings() {
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
                  title: 'Moderation Settings',
                  subtitle: 'Configure AI behavior',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Confidence Threshold',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Content scoring below this will be flagged for review',
                  style: TextStyle(fontSize: 12, color: AppTheme.textTertiary),
                ),
                const SizedBox(height: 10),
                AppTextField(
                  controller: _thresholdController,
                  label: 'Threshold (0.0 - 1.0)',
                  prefixIcon: Icons.speed,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Moderation Mode',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Ensemble runs all models - content blocked if ANY model flags it',
                  style: TextStyle(fontSize: 12, color: AppTheme.textTertiary),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.bgTertiary,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: AppTheme.borderDefault),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _activeModel,
                      isExpanded: true,
                      dropdownColor: AppTheme.bgElevated,
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        color: AppTheme.textTertiary,
                      ),
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'ensemble',
                          child: Text('Ensemble (All Models)'),
                        ),
                        DropdownMenuItem(
                          value: 'basic-v1',
                          child: Text('Word Filter Only (Fast)'),
                        ),
                        DropdownMenuItem(
                          value: 'claude-only',
                          child: Text('Claude AI Only'),
                        ),
                      ],
                      onChanged: (val) => setState(() => _activeModel = val!),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ActionButton(
                  text: 'Save Configuration',
                  icon: Icons.save_outlined,
                  onPressed: _updateSettings,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Test Console tab ────────────────────────────────────────────

  Widget _buildTestConsole() {
    return _TestConsoleWidget(
      onRefresh: _loadData,
      showSnackBar: _showSnackBar,
    );
  }
}

// ── Test Console ────────────────────────────────────────────────────

class _TestConsoleWidget extends StatefulWidget {
  final VoidCallback onRefresh;
  final Function(String, {bool isError}) showSnackBar;

  const _TestConsoleWidget({
    required this.onRefresh,
    required this.showSnackBar,
  });

  @override
  State<_TestConsoleWidget> createState() => _TestConsoleWidgetState();
}

class _TestConsoleWidgetState extends State<_TestConsoleWidget> {
  final _testMsgController = TextEditingController();
  bool _isPosting = false;
  XFile? _selectedImage;
  Uint8List? _imageBytes;
  final ImagePicker _picker = ImagePicker();
  String? _lastResult;

  @override
  void dispose() {
    _testMsgController.dispose();
    super.dispose();
  }

  void _postTestMessage() async {
    if (_testMsgController.text.trim().isEmpty) {
      widget.showSnackBar('Please enter a message', isError: true);
      return;
    }

    setState(() => _isPosting = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final message = _testMsgController.text;
      final result = await api.testSentiment(message);

      final sentiment = result['sentiment'] ?? 'UNKNOWN';
      final confidence = ((result['confidence'] ?? 0.0) * 100).toStringAsFixed(
        1,
      );
      final wouldApprove = result['wouldBeAutoApproved'] == true;

      setState(() {
        _lastResult =
            '''Message: "$message"

Sentiment:    $sentiment
Confidence:   $confidence%
Auto-Approve: ${wouldApprove ? 'YES' : 'NO (requires review)'}

${sentiment == 'NEGATIVE'
                ? 'This message would be flagged for moderation.'
                : sentiment == 'POSITIVE'
                ? 'This message would be auto-approved.'
                : 'This message would be auto-approved (neutral).'}''';
      });

      widget.showSnackBar(
        sentiment == 'NEGATIVE'
            ? 'Detected as NEGATIVE! Would be flagged.'
            : 'Analysis complete: $sentiment',
        isError: sentiment == 'NEGATIVE',
      );
    } catch (e) {
      widget.showSnackBar('Analysis failed: $e', isError: true);
      setState(() => _lastResult = 'Error: $e');
    } finally {
      setState(() => _isPosting = false);
    }
  }

  void _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _selectedImage = image;
        _imageBytes = bytes;
        _lastResult =
            'Image selected: ${image.name}\n\nTap "Upload & Analyze" to run AI moderation.';
      });
    }
  }

  void _uploadImage() async {
    if (_selectedImage == null || _imageBytes == null) {
      widget.showSnackBar('Please select an image first', isError: true);
      return;
    }

    setState(() => _isPosting = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final result = await api.uploadImage(
        _imageBytes!.toList(),
        _selectedImage!.name,
      );

      final status = result['status'] ?? 'UNKNOWN';
      final confidence = ((result['confidenceScore'] ?? 0.0) * 100)
          .toStringAsFixed(1);
      final categories = result['detectedCategories'] ?? 'None';
      final reason = result['moderationReason'] ?? 'No issues detected';

      setState(() {
        _lastResult =
            '''Image: ${_selectedImage!.name}

Status:     $status
Confidence: $confidence%
Categories: $categories
Reason:     $reason

${status == 'SAFE'
                ? 'This image passed moderation.'
                : status == 'FLAGGED'
                ? 'This image needs human review.'
                : 'This image was rejected.'}''';
        _selectedImage = null;
        _imageBytes = null;
      });

      widget.showSnackBar(
        status == 'SAFE'
            ? 'Image is SAFE'
            : status == 'FLAGGED'
            ? 'Image FLAGGED for review'
            : 'Image REJECTED',
        isError: status == 'REJECTED',
      );
    } catch (e) {
      widget.showSnackBar('Image moderation failed', isError: true);
      setState(() {
        _lastResult =
            '''Image Moderation Failed

Error: $e

Troubleshooting:
- Make sure the backend server is running
- Check if you're logged in as admin
- Check backend logs for details''';
      });
    } finally {
      setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Text test
          SurfaceCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  title: 'Test Message',
                  subtitle: 'Test AI moderation on text',
                ),
                AppTextField(
                  controller: _testMsgController,
                  label: 'Enter test message',
                  hint: 'Try: "This is awesome!" or something negative...',
                  maxLines: 3,
                  prefixIcon: Icons.edit_note,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildQuickBtn(
                      'Positive',
                      'I love this app! It is amazing!',
                    ),
                    const SizedBox(width: 6),
                    _buildQuickBtn('Neutral', 'The weather is nice today'),
                    const SizedBox(width: 6),
                    _buildQuickBtn('Negative', 'This is terrible and stupid'),
                  ],
                ),
                const SizedBox(height: 16),
                ActionButton(
                  text: 'Analyze Message',
                  icon: Icons.send,
                  isLoading: _isPosting,
                  onPressed: _postTestMessage,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Image test
          SurfaceCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  title: 'Test Image',
                  subtitle: 'Upload an image to test AI detection',
                ),
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 140,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppTheme.bgTertiary,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(color: AppTheme.borderDefault),
                    ),
                    child: _selectedImage != null
                        ? Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMd,
                                ),
                                child: Image.memory(
                                  _imageBytes!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: AppIconButton(
                                  icon: Icons.close,
                                  size: 32,
                                  color: Colors.white,
                                  backgroundColor: AppTheme.error,
                                  onPressed: () => setState(() {
                                    _selectedImage = null;
                                    _imageBytes = null;
                                  }),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.cloud_upload_outlined,
                                size: 40,
                                color: AppTheme.textTertiary.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Tap to select an image',
                                style: TextStyle(
                                  color: AppTheme.textTertiary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                ActionButton(
                  text: 'Upload & Analyze',
                  icon: Icons.analytics_outlined,
                  isLoading: _isPosting,
                  onPressed: _selectedImage != null ? _uploadImage : null,
                  gradient: AppTheme.successGradient,
                ),
              ],
            ),
          ),

          if (_lastResult != null) ...[
            const SizedBox(height: 12),
            SurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.terminal,
                        color: AppTheme.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Result',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppTheme.primary,
                        ),
                      ),
                      const Spacer(),
                      AppIconButton(
                        icon: Icons.copy,
                        size: 30,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _lastResult!));
                          widget.showSnackBar('Copied to clipboard!');
                        },
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => setState(() => _lastResult = null),
                        child: const Icon(
                          Icons.close,
                          color: AppTheme.textTertiary,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.bgPrimary,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      border: Border.all(color: AppTheme.borderDefault),
                    ),
                    child: SelectableText(
                      _lastResult!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickBtn(String label, String message) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _testMsgController.text = message,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.bgTertiary,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(color: AppTheme.borderDefault),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ),
      ),
    );
  }
}
