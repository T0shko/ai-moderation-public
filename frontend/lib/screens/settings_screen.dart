import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = false;
  String? _username;
  List<String> _roles = [];

  double _threshold = 0.6;
  bool _autoApprovePositive = true;
  bool _autoRejectHighConf = true;
  double _autoRejectThreshold = 0.85;

  bool _chatEnabled = true;
  final int _maxMessageLength = 2000;
  final int _rateLimitPerMinute = 30;
  final String _defaultProvider = 'combined';

  final int _maxCommentLength = 1000;
  bool _allowAnonymous = false;
  bool _requireModerationNewUsers = true;
  final int _newUserThreshold = 5;

  bool _emailOnFlagged = false;
  bool _dashboardAlerts = true;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  void _loadUserInfo() async {
    setState(() => _isLoading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final username = await api.getUsername();
      final roles = await api.getRoles();
      if (mounted) {
        setState(() {
          _username = username;
          _roles = roles;
        });
      }
    } catch (_) {}
    setState(() => _isLoading = false);
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
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                        child: Column(
                          children: [
                            _profileCard(),
                            const SizedBox(height: 16),
                            _moderationCard(),
                            const SizedBox(height: 16),
                            _chatCard(),
                            const SizedBox(height: 16),
                            _contentCard(),
                            const SizedBox(height: 16),
                            _notificationsCard(),
                            const SizedBox(height: 16),
                            _sessionCard(),
                          ],
                        ),
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
        border: Border(bottom: BorderSide(color: AppTheme.ink, width: 2)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
      child: Row(
        children: [
          AppIconButton(
            icon: Icons.arrow_back,
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('§ EDITORIAL STYLE',
                    style: AppTheme.label(color: AppTheme.textTertiary)),
                const SizedBox(height: 2),
                Text('House Settings',
                    style: AppTheme.display(
                      size: 22,
                      weight: FontWeight.w700,
                      letterSpacing: -0.6,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileCard() {
    final roleStr =
        _roles.map((r) => r.replaceFirst('ROLE_', '')).join(', ');
    final roleColor = _roles.contains('ROLE_ADMIN')
        ? AppTheme.persimmon
        : _roles.contains('ROLE_MODERATOR')
            ? AppTheme.honey
            : AppTheme.azure;
    final initial = (_username ?? '?').substring(0, 1).toUpperCase();

    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      accentColor: roleColor,
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.paperLight,
              border: Border.all(color: AppTheme.ink, width: 1.2),
            ),
            child: Center(
              child: Text(
                initial,
                style: AppTheme.display(
                  size: 36,
                  weight: FontWeight.w700,
                  letterSpacing: -1.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_username ?? 'Loading…',
                    style: AppTheme.display(
                      size: 22,
                      weight: FontWeight.w700,
                      letterSpacing: -0.6,
                    )),
                const SizedBox(height: 6),
                StatusBadge(
                  text: roleStr.isEmpty ? 'READER' : roleStr,
                  color: roleColor,
                  showPulse: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _moderationCard() {
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      accentColor: AppTheme.ink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Moderation',
            subtitle: 'Auto-moderation behavior.',
            index: '01',
          ),
          _sliderRow('Confidence Threshold', _threshold,
              (v) => setState(() => _threshold = v)),
          const SizedBox(height: 8),
          const Divider(color: AppTheme.hairline, height: 1),
          const SizedBox(height: 8),
          _switchRow(
              'Auto-approve positive',
              'Set in print when positive sentiment is high.',
              _autoApprovePositive,
              (v) => setState(() => _autoApprovePositive = v)),
          _switchRow(
              'Auto-reject high confidence',
              'Spike when flagged above threshold.',
              _autoRejectHighConf,
              (v) => setState(() => _autoRejectHighConf = v)),
          if (_autoRejectHighConf)
            _sliderRow('Auto-reject Threshold', _autoRejectThreshold,
                (v) => setState(() => _autoRejectThreshold = v)),
        ],
      ),
    );
  }

  Widget _chatCard() {
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      accentColor: AppTheme.persimmon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'AI Concierge',
            subtitle: 'Chat configuration.',
            index: '02',
          ),
          _switchRow(
              'Concierge Enabled',
              'Allow readers to use the AI concierge.',
              _chatEnabled,
              (v) => setState(() => _chatEnabled = v)),
          _infoRow('Max Message Length', '$_maxMessageLength chars'),
          _infoRow('Rate Limit', '$_rateLimitPerMinute / min'),
          _infoRow('Default Provider', _defaultProvider),
        ],
      ),
    );
  }

  Widget _contentCard() {
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      accentColor: AppTheme.olive,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Content',
            subtitle: 'Reader content rules.',
            index: '03',
          ),
          _infoRow('Max Dispatch Length', '$_maxCommentLength chars'),
          const SizedBox(height: 6),
          const Divider(color: AppTheme.hairline, height: 1),
          const SizedBox(height: 6),
          _switchRow(
              'Allow Anonymous',
              'Let non-logged-in readers comment.',
              _allowAnonymous,
              (v) => setState(() => _allowAnonymous = v)),
          _switchRow(
              'Moderate New Readers',
              'Hold first $_newUserThreshold dispatches for review.',
              _requireModerationNewUsers,
              (v) => setState(() => _requireModerationNewUsers = v)),
        ],
      ),
    );
  }

  Widget _notificationsCard() {
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      accentColor: AppTheme.honey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Notifications',
            subtitle: 'How the desk reaches you.',
            index: '04',
          ),
          _switchRow(
              'Email on Flagged',
              'Send an email when content is flagged.',
              _emailOnFlagged,
              (v) => setState(() => _emailOnFlagged = v)),
          _switchRow(
              'Dashboard Alerts',
              'Show alerts on the editor\u2019s desk.',
              _dashboardAlerts,
              (v) => setState(() => _dashboardAlerts = v)),
        ],
      ),
    );
  }

  Widget _sessionCard() {
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      accentColor: AppTheme.rust,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Session',
            subtitle: 'Sign out from this paper.',
            index: '05',
            trailing: StatusBadge(
              text: 'ACTIVE',
              color: AppTheme.olive,
              showPulse: true,
            ),
          ),
          ActionButton(
            text: 'Sign out',
            icon: Icons.logout,
            onPressed: _logout,
            backgroundColor: AppTheme.rust,
          ),
        ],
      ),
    );
  }

  Widget _switchRow(String title, String subtitle, bool value,
      ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTheme.body(
                      size: 14,
                      color: AppTheme.ink,
                      weight: FontWeight.w600,
                    )),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: AppTheme.body(
                      size: 12,
                      color: AppTheme.textTertiary,
                      style: FontStyle.italic,
                    )),
              ],
            ),
          ),
          _PressSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _sliderRow(
      String title, double value, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: AppTheme.body(
                    size: 14,
                    color: AppTheme.ink,
                    weight: FontWeight.w600,
                  )),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.persimmonSoft,
                  border: Border.all(color: AppTheme.persimmon),
                ),
                child: Text(
                  value.toStringAsFixed(2),
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
            value: value,
            min: 0,
            max: 1,
            divisions: 20,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(label,
              style: AppTheme.body(size: 14, color: AppTheme.textSecondary)),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.paper,
              border: Border.all(color: AppTheme.hairline),
            ),
            child: Text(
              value,
              style: AppTheme.mono(
                size: 11,
                color: AppTheme.ink,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PressSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _PressSwitch({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 44,
        height: 24,
        decoration: BoxDecoration(
          color: value ? AppTheme.ink : AppTheme.paperLight,
          border: Border.all(color: AppTheme.ink, width: 1.2),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 140),
          alignment:
              value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(2),
            width: 18,
            height: 18,
            color: value ? AppTheme.persimmon : AppTheme.ink,
          ),
        ),
      ),
    );
  }
}
