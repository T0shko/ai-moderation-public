import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPendingComments();
  }

  void _loadPendingComments() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final comments = await api.getPendingComments();
      if (mounted) setState(() => _pendingComments = comments);
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
      _showSnackBar(approved ? 'Comment approved' : 'Comment rejected');
      _loadPendingComments();
    } on AuthException {
      return;
    } catch (e) {
      _showSnackBar('Action failed', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.dmSans(fontSize: 14)),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
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
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                    : _error != null
                        ? _buildErrorState()
                        : _pendingComments.isEmpty
                            ? _buildEmptyState()
                            : _buildList(),
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
              gradient: AppTheme.accentGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppTheme.glow(AppTheme.amber, 0.2),
            ),
            child: const Icon(Icons.gavel_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Moderation',
                  style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
                Text(
                  '${_pendingComments.length} pending review',
                  style: GoogleFonts.dmSans(fontSize: 12, color: AppTheme.textTertiary),
                ),
              ],
            ),
          ),
          AppIconButton(icon: Icons.refresh_rounded, onPressed: _loadPendingComments),
          const SizedBox(width: 8),
          AppIconButton(icon: Icons.settings_outlined, onPressed: () => Navigator.pushNamed(context, '/settings')),
          const SizedBox(width: 8),
          AppIconButton(icon: Icons.logout_rounded, onPressed: _logout, color: AppTheme.error),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded, size: 48, color: AppTheme.textTertiary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text('Connection issue', style: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
          const SizedBox(height: 20),
          ActionButton(text: 'Retry', icon: Icons.refresh, onPressed: _loadPendingComments, width: 140, height: 44),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 56, color: AppTheme.success.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text('All clear', style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          Text('No comments pending review', style: GoogleFonts.dmSans(fontSize: 13, color: AppTheme.textTertiary)),
        ],
      ),
    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      onRefresh: () async => _loadPendingComments(),
      color: AppTheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _pendingComments.length,
        itemBuilder: (context, index) => _buildCard(_pendingComments[index]),
      ),
    );
  }

  Widget _buildCard(dynamic comment) {
    final sentiment = comment['sentiment'] ?? 'NEUTRAL';
    final confidence = (comment['confidenceScore'] ?? 0.0) * 100;
    final sentColor = _sentimentColor(sentiment);
    final id = comment['id'] as int;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        padding: const EdgeInsets.all(18),
        accentColor: sentColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author + sentiment
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: sentColor.withValues(alpha: 0.15),
                  child: Text(
                    (comment['author']?['username'] ?? '?').substring(0, 1).toUpperCase(),
                    style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700, fontSize: 15, color: sentColor),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comment['author']?['username'] ?? 'Unknown',
                        style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.textPrimary),
                      ),
                      Row(children: [
                        StatusBadge(text: sentiment, color: sentColor),
                        const SizedBox(width: 8),
                        Text('${confidence.toStringAsFixed(0)}%', style: GoogleFonts.dmSans(fontSize: 11, color: AppTheme.textTertiary)),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Content
            Text(
              comment['content'] ?? '',
              style: GoogleFonts.dmSans(fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 16),
            // Actions
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _moderateComment(id, false),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(color: AppTheme.error.withValues(alpha: 0.25)),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.close_rounded, color: AppTheme.error, size: 18),
                            const SizedBox(width: 6),
                            Text('Reject', style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.error)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _moderateComment(id, true),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: AppTheme.successGradient,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        boxShadow: AppTheme.glow(AppTheme.success, 0.15),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                            const SizedBox(width: 6),
                            Text('Approve', style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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
}
