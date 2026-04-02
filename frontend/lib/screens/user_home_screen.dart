import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
  String? _error;

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
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final comments = await api.getComments();
      if (mounted) setState(() => _comments = comments);
    } on AuthException {
      return;
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
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
        _showSnackBar('Comment posted — AI analyzing...');
        _loadComments();
      }
    } on AuthException {
      return;
    } catch (e) {
      if (mounted) _showSnackBar('Failed to post', isError: true);
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
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
              _buildAppBar(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                    : _error != null
                        ? _buildErrorState()
                        : _comments.isEmpty
                            ? _buildEmptyState()
                            : _buildCommentsList(),
              ),
              _buildCommentInput(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
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
              gradient: AppTheme.warmGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppTheme.glow(AppTheme.coral, 0.2),
            ),
            child: const Icon(Icons.shield_outlined, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Feed',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  '${_comments.length} posts',
                  style: GoogleFonts.dmSans(fontSize: 12, color: AppTheme.textTertiary),
                ),
              ],
            ),
          ),
          AppIconButton(
            icon: Icons.smart_toy_outlined,
            onPressed: () => Navigator.pushNamed(context, '/chat'),
            tooltip: 'AI Chat',
            color: AppTheme.amber,
          ),
          const SizedBox(width: 8),
          AppIconButton(icon: Icons.refresh_rounded, onPressed: _loadComments),
          const SizedBox(width: 8),
          AppIconButton(icon: Icons.logout_rounded, onPressed: _logout, color: AppTheme.error),
        ],
      ),
    );
  }

  Widget _buildCommentInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: AppTheme.bgSecondary.withValues(alpha: 0.9),
        border: const Border(top: BorderSide(color: AppTheme.borderDefault)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.bgTertiary,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.borderActive),
              ),
              child: TextField(
                controller: _commentController,
                style: GoogleFonts.dmSans(color: AppTheme.textPrimary, fontSize: 14),
                maxLines: 3,
                minLines: 1,
                onSubmitted: (_) => _postComment(),
                decoration: InputDecoration(
                  hintText: 'Share your thoughts...',
                  hintStyle: GoogleFonts.dmSans(color: AppTheme.textTertiary),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _isPosting ? null : _postComment,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: AppTheme.glow(AppTheme.coral, 0.3),
              ),
              child: _isPosting
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: AppTheme.textTertiary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('Connection issue', style: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
            const SizedBox(height: 8),
            Text('Could not reach the server', style: GoogleFonts.dmSans(fontSize: 13, color: AppTheme.textTertiary)),
            const SizedBox(height: 20),
            ActionButton(text: 'Retry', icon: Icons.refresh, onPressed: _loadComments, width: 140, height: 44),
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
          Icon(Icons.chat_bubble_outline_rounded, size: 48, color: AppTheme.textTertiary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text('No posts yet', style: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          Text('Be the first to share!', style: GoogleFonts.dmSans(fontSize: 13, color: AppTheme.textTertiary)),
        ],
      ),
    );
  }

  Widget _buildCommentsList() {
    return RefreshIndicator(
      onRefresh: () async => _loadComments(),
      color: AppTheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        itemCount: _comments.length,
        itemBuilder: (context, index) {
          final comment = _comments[index];
          return _buildCommentCard(comment);
        },
      ),
    );
  }

  Widget _buildCommentCard(dynamic comment) {
    final sentiment = comment['sentiment'] ?? 'NEUTRAL';
    final confidence = (comment['confidenceScore'] ?? 0.0) * 100;
    final status = comment['status'] ?? 'PENDING';
    final sentColor = _sentimentColor(sentiment);
    final statusColor = _statusColor(status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        padding: const EdgeInsets.all(16),
        accentColor: sentColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: sentColor.withValues(alpha: 0.15),
                  child: Text(
                    (comment['author']?['username'] ?? '?').substring(0, 1).toUpperCase(),
                    style: GoogleFonts.playfairDisplay(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: sentColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comment['author']?['username'] ?? 'Anonymous',
                        style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.textPrimary),
                      ),
                      Row(
                        children: [
                          Text(sentiment, style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w600, color: sentColor)),
                          const SizedBox(width: 8),
                          Text('${confidence.toStringAsFixed(0)}%', style: GoogleFonts.dmSans(fontSize: 10, color: AppTheme.textTertiary)),
                        ],
                      ),
                    ],
                  ),
                ),
                StatusBadge(text: status, color: statusColor, showPulse: status == 'PENDING'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              comment['content'] ?? '',
              style: GoogleFonts.dmSans(fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
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

  Color _statusColor(String s) {
    switch (s) {
      case 'APPROVED': return AppTheme.success;
      case 'REJECTED': return AppTheme.error;
      case 'PENDING': return AppTheme.warning;
      default: return AppTheme.textTertiary;
    }
  }
}
