import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';

class ModeratorDashboard extends StatefulWidget {
  const ModeratorDashboard({super.key});

  @override
  State<ModeratorDashboard> createState() => _ModeratorDashboardState();
}

class _ModeratorDashboardState extends State<ModeratorDashboard> {
  List<dynamic> _pendingComments = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPendingComments();
  }

  void _loadPendingComments() async {
    setState(() => _isLoading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final comments = await api.getPendingComments();
      if (mounted) setState(() => _pendingComments = comments);
    } catch (e) {
      if (mounted) _showSnackBar('Failed to load comments', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _moderateComment(int id, bool approved) async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.moderateComment(id, approved);
      _showSnackBar(approved ? 'Comment approved' : 'Comment rejected');
      _loadPendingComments();
    } catch (e) {
      _showSnackBar('Error moderating comment', isError: true);
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
            _buildStats(),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    )
                  : _pendingComments.isEmpty
                  ? _buildEmptyState()
                  : _buildCommentsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.aurora1, AppTheme.aurora4],
              ),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Content Review',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'Moderator Panel',
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
          AppIconButton(icon: Icons.refresh, onPressed: _loadPendingComments),
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

  Widget _buildStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          StatTile(
            value: '${_pendingComments.length}',
            label: 'Pending',
            icon: Icons.pending_actions,
            color: AppTheme.warning,
          ),
          const SizedBox(width: 10),
          StatTile(
            value: 'Active',
            label: 'AI Status',
            icon: Icons.speed,
            color: AppTheme.success,
          ),
          const SizedBox(width: 10),
          StatTile(
            value: 'v2.0',
            label: 'Model',
            icon: Icons.auto_awesome,
            color: AppTheme.info,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline,
              size: 56,
              color: AppTheme.success,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'All caught up!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'No pending comments to review',
            style: TextStyle(fontSize: 14, color: AppTheme.textTertiary),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _loadPendingComments,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: _pendingComments.length,
      itemBuilder: (context, index) {
        final comment = _pendingComments[index];
        final sentiment = comment['sentiment'] ?? 'NEUTRAL';
        final confidence = (comment['confidenceScore'] ?? 0.0) * 100;

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 300 + (index * 70)),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 20 * (1 - value)),
              child: Opacity(opacity: value, child: child),
            );
          },
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Dismissible(
              key: Key('comment_${comment['id']}'),
              background: _buildSwipeBg(true),
              secondaryBackground: _buildSwipeBg(false),
              onDismissed: (direction) {
                _moderateComment(
                  comment['id'],
                  direction == DismissDirection.startToEnd,
                );
              },
              child: SurfaceCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _sentimentColor(
                              sentiment,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusSm,
                            ),
                          ),
                          child: Icon(
                            _sentimentIcon(sentiment),
                            color: _sentimentColor(sentiment),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                comment['author']?['username'] ?? 'Anonymous',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              Text(
                                '$sentiment  ${confidence.toStringAsFixed(0)}%',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _sentimentColor(sentiment),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const StatusBadge(
                          text: 'PENDING',
                          color: AppTheme.warning,
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
                        Text(
                          'Swipe to moderate',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textTertiary.withValues(alpha: 0.5),
                          ),
                        ),
                        const Spacer(),
                        _buildActionBtn(
                          onTap: () => _moderateComment(comment['id'], false),
                          icon: Icons.close,
                          color: AppTheme.error,
                          label: 'Reject',
                        ),
                        const SizedBox(width: 8),
                        _buildActionBtn(
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
            ),
          ),
        );
      },
    );
  }

  Widget _buildSwipeBg(bool isApprove) {
    final color = isApprove ? AppTheme.success : AppTheme.error;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      alignment: isApprove ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Icon(
        isApprove ? Icons.check_circle : Icons.cancel,
        color: color,
        size: 28,
      ),
    );
  }

  Widget _buildActionBtn({
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
            Icon(icon, color: color, size: 15),
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

  Color _sentimentColor(String s) {
    if (s == 'NEGATIVE') return AppTheme.error;
    if (s == 'POSITIVE') return AppTheme.success;
    return AppTheme.info;
  }

  IconData _sentimentIcon(String s) {
    if (s == 'NEGATIVE') return Icons.sentiment_very_dissatisfied;
    if (s == 'POSITIVE') return Icons.sentiment_very_satisfied;
    return Icons.sentiment_neutral;
  }
}
