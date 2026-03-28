import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  final _commentController = TextEditingController();
  bool _isLoading = false;
  bool _isPosting = false;
  List<dynamic> _comments = [];

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _loadComments() async {
    setState(() => _isLoading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final comments = await api.getComments();
      if (mounted) setState(() => _comments = comments);
    } catch (e) {
      if (mounted) _showSnackBar('Failed to load comments', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _postComment() async {
    if (_commentController.text.trim().isEmpty) return;

    setState(() => _isPosting = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.postComment(_commentController.text);
      _commentController.clear();
      if (mounted) {
        _showSnackBar('Comment posted! AI is analyzing...');
        _loadComments();
      }
    } catch (e) {
      if (mounted) _showSnackBar('Failed to post comment', isError: true);
    } finally {
      if (mounted) setState(() => _isPosting = false);
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
            _buildCommentInput(),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    )
                  : _comments.isEmpty
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
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: const Icon(
              Icons.forum_outlined,
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
                  'Community Feed',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'Share your thoughts',
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
            icon: Icons.refresh,
            onPressed: _loadComments,
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
          AppIconButton(
            icon: Icons.logout,
            onPressed: _logout,
            color: AppTheme.error,
            tooltip: 'Logout',
          ),
        ],
      ),
    );
  }

  Widget _buildCommentInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentController,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                ),
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(
                  hintText: 'Write something...',
                  hintStyle: TextStyle(color: AppTheme.textTertiary),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  fillColor: Colors.transparent,
                  filled: false,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _isPosting ? null : _postComment,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: _isPosting
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: AppTheme.textTertiary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          const Text(
            'No comments yet',
            style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 6),
          const Text(
            'Be the first to share!',
            style: TextStyle(fontSize: 13, color: AppTheme.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: _comments.length,
      itemBuilder: (context, index) {
        final comment = _comments[index];
        final sentiment = comment['sentiment'] ?? 'NEUTRAL';
        final confidence = (comment['confidenceScore'] ?? 0.0) * 100;
        final status = comment['status'] ?? 'PENDING';
        return _buildCommentCard(comment, sentiment, confidence, status, index);
      },
    );
  }

  Widget _buildCommentCard(
    dynamic comment,
    String sentiment,
    double confidence,
    String status,
    int index,
  ) {
    final sentimentColor = _getSentimentColor(sentiment);
    final sentimentIcon = _getSentimentIcon(sentiment);
    final statusColor = _getStatusColor(status);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 250 + (index * 60)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 16 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: sentimentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    child: Icon(sentimentIcon, color: sentimentColor, size: 18),
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
                          style: TextStyle(fontSize: 11, color: sentimentColor),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(text: status, color: statusColor),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                comment['content'] ?? '',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getSentimentColor(String s) {
    if (s == 'NEGATIVE') return AppTheme.error;
    if (s == 'POSITIVE') return AppTheme.success;
    return AppTheme.info;
  }

  IconData _getSentimentIcon(String s) {
    if (s == 'NEGATIVE') return Icons.sentiment_very_dissatisfied;
    if (s == 'POSITIVE') return Icons.sentiment_very_satisfied;
    return Icons.sentiment_neutral;
  }

  Color _getStatusColor(String s) {
    switch (s) {
      case 'APPROVED':
        return AppTheme.success;
      case 'REJECTED':
        return AppTheme.error;
      case 'PENDING':
        return AppTheme.warning;
      default:
        return AppTheme.textTertiary;
    }
  }
}
