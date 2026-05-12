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
        _snack('Filed for review \u2014 AI analyzing');
        _loadComments();
      }
    } on AuthException {
      return;
    } catch (_) {
      if (mounted) _snack('Failed to post', isError: true);
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
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
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AppTheme.ink, strokeWidth: 1.8),
                      )
                    : _error != null
                        ? _errorState()
                        : _comments.isEmpty
                            ? _emptyState()
                            : _commentsList(),
              ),
              _composer(),
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
              Text('THE PRESSROOM \u2014 PUBLIC FEED',
                  style: AppTheme.label(color: AppTheme.textTertiary)),
              const Spacer(),
              Text('${_comments.length} ENTRIES',
                  style: AppTheme.label(color: AppTheme.persimmon)),
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
                      const TextSpan(text: 'Today\u2019s '),
                      TextSpan(
                        text: 'Dispatches',
                        style: AppTheme.display(
                          size: 32,
                          weight: FontWeight.w400,
                          style: FontStyle.italic,
                          letterSpacing: -1.2,
                          color: AppTheme.persimmon,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AppIconButton(
                icon: Icons.auto_awesome,
                onPressed: () => Navigator.pushNamed(context, '/chat'),
                tooltip: 'AI Concierge',
              ),
              const SizedBox(width: 8),
              AppIconButton(
                icon: Icons.refresh,
                onPressed: _loadComments,
                tooltip: 'Reload',
              ),
              const SizedBox(width: 8),
              AppIconButton(
                icon: Icons.logout,
                onPressed: _logout,
                color: AppTheme.rust,
                tooltip: 'Sign out',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.paperLight,
        border: Border(top: BorderSide(color: AppTheme.ink, width: 1.5)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 12, height: 1, color: AppTheme.persimmon),
              const SizedBox(width: 8),
              Text('FILE A NEW DISPATCH',
                  style: AppTheme.label(color: AppTheme.ink, size: 10)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AppTextField(
                  controller: _commentController,
                  label: 'Your dispatch',
                  hint: 'Write your thought, dear reader…',
                  maxLines: 3,
                  onSubmitted: (_) => _postComment(),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 140,
                child: ActionButton(
                  text: 'File',
                  icon: Icons.send_outlined,
                  isLoading: _isPosting,
                  onPressed: _postComment,
                  height: 46,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CrosshairMark(size: 24, color: AppTheme.rust),
            const SizedBox(height: 12),
            Text('TRANSMISSION LOST',
                style: AppTheme.label(color: AppTheme.rust, size: 11)),
            const SizedBox(height: 6),
            Text('The wire is down. We could not reach the desk.',
                style: AppTheme.body(
                    size: 14,
                    color: AppTheme.textSecondary,
                    style: FontStyle.italic)),
            const SizedBox(height: 20),
            SizedBox(
              width: 180,
              child: ActionButton(
                text: 'Retry',
                icon: Icons.refresh,
                onPressed: _loadComments,
                height: 44,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.ink, width: 1.5),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: const Icon(Icons.edit_note,
                size: 40, color: AppTheme.ink),
          ),
          const SizedBox(height: 14),
          Text('THE PAGE IS BLANK',
              style: AppTheme.label(color: AppTheme.textSecondary, size: 11)),
          const SizedBox(height: 6),
          Text('Be the first to file a dispatch.',
              style: AppTheme.body(
                  size: 14,
                  color: AppTheme.textTertiary,
                  style: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _commentsList() {
    return RefreshIndicator(
      onRefresh: () async => _loadComments(),
      color: AppTheme.ink,
      backgroundColor: AppTheme.paperLight,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        itemCount: _comments.length,
        separatorBuilder: (_, _) => _ledgerSeparator(),
        itemBuilder: (context, index) =>
            _entry(_comments[index], index + 1),
      ),
    );
  }

  Widget _ledgerSeparator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: AppTheme.hairline)),
          const SizedBox(width: 10),
          Text('\u00B7 \u00B7 \u00B7',
              style: AppTheme.mono(size: 9, color: AppTheme.textTertiary)),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: AppTheme.hairline)),
        ],
      ),
    );
  }

  Widget _entry(dynamic comment, int index) {
    final sentiment = comment['sentiment'] ?? 'NEUTRAL';
    final confidence = (comment['confidenceScore'] ?? 0.0) * 100;
    final status = comment['status'] ?? 'PENDING';
    final sentColor = _sentimentColor(sentiment);
    final statusColor = _statusColor(status);
    final author = comment['author']?['username'] ?? 'Anonymous';
    final initial = author.toString().substring(0, 1).toUpperCase();

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Square serif drop-cap avatar.
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.paperLight,
              border: Border.all(color: AppTheme.ink, width: 1.2),
            ),
            child: Stack(
              children: [
                Center(
                  child: Text(
                    initial,
                    style: AppTheme.display(
                      size: 30,
                      weight: FontWeight.w700,
                      color: AppTheme.ink,
                      letterSpacing: -1,
                    ),
                  ),
                ),
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(width: 6, height: 6, color: sentColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      author,
                      style: AppTheme.body(
                        size: 15,
                        color: AppTheme.ink,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '\u2014 ${sentiment.toString().toLowerCase()}',
                      style: AppTheme.body(
                        size: 13,
                        color: sentColor,
                        style: FontStyle.italic,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'N\u00B0 ${index.toString().padLeft(3, '0')}',
                      style: AppTheme.mono(
                        size: 10,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    StatusBadge(
                      text: status,
                      color: statusColor,
                      showPulse: status == 'PENDING',
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'CONF ${confidence.toStringAsFixed(0)}%',
                      style: AppTheme.label(color: AppTheme.textTertiary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  comment['content'] ?? '',
                  style: AppTheme.body(
                    size: 15,
                    color: AppTheme.ink,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _sentimentColor(String s) {
    if (s == 'NEGATIVE') return AppTheme.rust;
    if (s == 'POSITIVE') return AppTheme.olive;
    return AppTheme.azure;
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'APPROVED':
        return AppTheme.olive;
      case 'REJECTED':
        return AppTheme.rust;
      case 'PENDING':
        return AppTheme.honey;
      default:
        return AppTheme.textTertiary;
    }
  }
}
