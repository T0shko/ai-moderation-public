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
      _snack(approved ? 'Set in print' : 'Spiked');
      _loadPendingComments();
    } on AuthException {
      return;
    } catch (_) {
      _snack('Action failed', isError: true);
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
                        : _pendingComments.isEmpty
                            ? _emptyState()
                            : _list(),
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
              Text('DESK \u2014 MODERATION',
                  style: AppTheme.label(color: AppTheme.textTertiary)),
              const Spacer(),
              Text('${_pendingComments.length} IN QUEUE',
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
                      const TextSpan(text: 'On the '),
                      TextSpan(
                        text: 'spike',
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
                  icon: Icons.refresh, onPressed: _loadPendingComments),
              const SizedBox(width: 8),
              AppIconButton(
                icon: Icons.settings_outlined,
                onPressed: () => Navigator.pushNamed(context, '/settings'),
              ),
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

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
                onPressed: _loadPendingComments,
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
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppTheme.oliveSoft,
              border: Border.all(color: AppTheme.olive, width: 1.5),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child:
                const Icon(Icons.check, size: 44, color: AppTheme.olive),
          ),
          const SizedBox(height: 14),
          Text('ALL CLEAR \u2014 GO TO PRESS',
              style: AppTheme.label(color: AppTheme.olive, size: 11)),
          const SizedBox(height: 6),
          Text('No dispatches are awaiting review.',
              style: AppTheme.body(
                  size: 14,
                  color: AppTheme.textTertiary,
                  style: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _list() {
    return RefreshIndicator(
      onRefresh: () async => _loadPendingComments(),
      color: AppTheme.ink,
      backgroundColor: AppTheme.paperLight,
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _pendingComments.length,
        itemBuilder: (context, index) =>
            _card(_pendingComments[index], index + 1),
      ),
    );
  }

  Widget _card(dynamic comment, int index) {
    final sentiment = comment['sentiment'] ?? 'NEUTRAL';
    final confidence = (comment['confidenceScore'] ?? 0.0) * 100;
    final sentColor = _sentimentColor(sentiment);
    final id = comment['id'] as int;
    final author = comment['author']?['username'] ?? 'Unknown';
    final initial = author.toString().substring(0, 1).toUpperCase();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SurfaceCard(
        padding: const EdgeInsets.all(20),
        accentColor: sentColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FolioTag(number: index.toString().padLeft(3, '0')),
                const Spacer(),
                StatusBadge(text: sentiment, color: sentColor),
                const SizedBox(width: 8),
                Text(
                  'CONF ${confidence.toStringAsFixed(0)}%',
                  style: AppTheme.label(color: AppTheme.textTertiary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppTheme.paperLight,
                    border: Border.all(color: AppTheme.ink),
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: AppTheme.display(
                        size: 24,
                        weight: FontWeight.w700,
                        color: AppTheme.ink,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(author,
                          style: AppTheme.body(
                              size: 15,
                              color: AppTheme.ink,
                              weight: FontWeight.w600)),
                      Text('contributor',
                          style: AppTheme.body(
                              size: 12,
                              color: AppTheme.textTertiary,
                              style: FontStyle.italic)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              decoration: BoxDecoration(
                color: AppTheme.paper,
                border: Border(
                  left: BorderSide(color: sentColor, width: 3),
                ),
              ),
              child: Text(
                '\u201C${comment['content'] ?? ''}\u201D',
                style: AppTheme.body(
                  size: 16,
                  color: AppTheme.ink,
                  height: 1.55,
                  style: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ActionButton(
                    text: 'Spike',
                    icon: Icons.close,
                    onPressed: () => _moderateComment(id, false),
                    backgroundColor: AppTheme.paperLight,
                    secondary: true,
                    height: 46,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: ActionButton(
                    text: 'Set in print',
                    icon: Icons.check,
                    onPressed: () => _moderateComment(id, true),
                    backgroundColor: AppTheme.olive,
                    height: 46,
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
    if (s == 'NEGATIVE') return AppTheme.rust;
    if (s == 'POSITIVE') return AppTheme.olive;
    return AppTheme.azure;
  }
}
