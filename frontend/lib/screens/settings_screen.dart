import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
      backgroundColor: AppTheme.bgDeep,
      body: NexusBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        child: Column(
                          children: [
                            _buildProfileCard(),
                            const SizedBox(height: 14),
                            _buildModerationDefaults(),
                            const SizedBox(height: 14),
                            _buildChatDefaults(),
                            const SizedBox(height: 14),
                            _buildContentDefaults(),
                            const SizedBox(height: 14),
                            _buildNotificationDefaults(),
                            const SizedBox(height: 20),
                            _buildDangerZone(),
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.bgSecondary.withValues(alpha: 0.7),
        border: const Border(bottom: BorderSide(color: AppTheme.borderDefault)),
      ),
      child: Row(
        children: [
          AppIconButton(icon: Icons.arrow_back_rounded, onPressed: () => Navigator.pop(context)),
          const SizedBox(width: 14),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: AppTheme.warmGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppTheme.glow(AppTheme.coral, 0.2),
            ),
            child: const Icon(Icons.settings_outlined, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Settings', style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                Text('Configuration', style: GoogleFonts.dmSans(fontSize: 12, color: AppTheme.textTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    final roleStr = _roles.map((r) => r.replaceFirst('ROLE_', '')).join(', ');
    final roleColor = _roles.contains('ROLE_ADMIN')
        ? AppTheme.coral
        : _roles.contains('ROLE_MODERATOR')
            ? AppTheme.amber
            : AppTheme.info;

    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      accentGradient: AppTheme.warmGradient,
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: roleColor.withValues(alpha: 0.15),
            child: Text(
              (_username ?? '?').substring(0, 1).toUpperCase(),
              style: GoogleFonts.playfairDisplay(color: roleColor, fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _username ?? 'Loading...',
                  style: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 4),
                StatusBadge(text: roleStr, color: roleColor, showPulse: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModerationDefaults() {
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Moderation', subtitle: 'Auto-moderation behavior'),
          _buildSliderRow('Confidence Threshold', _threshold, (v) => setState(() => _threshold = v)),
          const Divider(color: AppTheme.borderDefault, height: 24),
          _buildSwitchRow('Auto-approve positive', 'Automatically approve positive sentiment', _autoApprovePositive, (v) => setState(() => _autoApprovePositive = v)),
          _buildSwitchRow('Auto-reject high confidence', 'Reject when flagged above threshold', _autoRejectHighConf, (v) => setState(() => _autoRejectHighConf = v)),
          if (_autoRejectHighConf)
            _buildSliderRow('Auto-reject Threshold', _autoRejectThreshold, (v) => setState(() => _autoRejectThreshold = v)),
        ],
      ),
    );
  }

  Widget _buildChatDefaults() {
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'AI Chat', subtitle: 'Chat configuration'),
          _buildSwitchRow('Chat Enabled', 'Allow users to use AI chat', _chatEnabled, (v) => setState(() => _chatEnabled = v)),
          _buildInfoRow('Max Message Length', '$_maxMessageLength chars'),
          _buildInfoRow('Rate Limit', '$_rateLimitPerMinute/min'),
          _buildInfoRow('Default Provider', _defaultProvider),
        ],
      ),
    );
  }

  Widget _buildContentDefaults() {
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Content', subtitle: 'User content rules'),
          _buildInfoRow('Max Comment Length', '$_maxCommentLength chars'),
          const Divider(color: AppTheme.borderDefault, height: 24),
          _buildSwitchRow('Allow Anonymous', 'Let non-logged-in users comment', _allowAnonymous, (v) => setState(() => _allowAnonymous = v)),
          _buildSwitchRow('Moderate New Users', 'Require moderation for first $_newUserThreshold posts', _requireModerationNewUsers, (v) => setState(() => _requireModerationNewUsers = v)),
        ],
      ),
    );
  }

  Widget _buildNotificationDefaults() {
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Notifications', subtitle: 'Alert preferences'),
          _buildSwitchRow('Email on Flagged', 'Send email when content is flagged', _emailOnFlagged, (v) => setState(() => _emailOnFlagged = v)),
          _buildSwitchRow('Dashboard Alerts', 'Show alerts on dashboard', _dashboardAlerts, (v) => setState(() => _dashboardAlerts = v)),
        ],
      ),
    );
  }

  Widget _buildDangerZone() {
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Session',
            subtitle: 'Manage your session',
            trailing: StatusBadge(text: 'ACTIVE', color: AppTheme.success, showPulse: true),
          ),
          ActionButton(text: 'Sign Out', icon: Icons.logout_rounded, onPressed: _logout, gradient: AppTheme.dangerGradient),
        ],
      ),
    );
  }

  Widget _buildSwitchRow(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: GoogleFonts.dmSans(fontSize: 12, color: AppTheme.textTertiary)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeTrackColor: AppTheme.primary, inactiveTrackColor: AppTheme.bgTertiary),
        ],
      ),
    );
  }

  Widget _buildSliderRow(String title, double value, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                ),
                child: Text(value.toStringAsFixed(2), style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary)),
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
            child: Slider(value: value, min: 0.0, max: 1.0, divisions: 20, onChanged: onChanged),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(label, style: GoogleFonts.dmSans(fontSize: 14, color: AppTheme.textSecondary)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.bgTertiary,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: AppTheme.borderDefault),
            ),
            child: Text(value, style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          ),
        ],
      ),
    );
  }
}
