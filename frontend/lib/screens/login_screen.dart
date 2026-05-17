import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      _snack('Please fill in all fields', isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      // login() persists the full session (access + refresh + expiry).
      final response =
          await api.login(_usernameController.text, _passwordController.text);
      final username = (response['username'] as String?) ?? '';
      final roles = (response['roles'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const <String>[];
      if (mounted) {
        _snack('Signed in as $username');
        await Future.delayed(const Duration(milliseconds: 250));
        _route(roles);
      }
    } catch (e) {
      if (mounted) {
        _snack(_friendlyError(e), isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(Object e) {
    if (e is ApiException) {
      switch (e.code) {
        case 'invalid_credentials':
          return 'Wrong username or password.';
        case 'account_locked':
          return e.message;
        case 'account_disabled':
          return 'This account has been disabled.';
        case 'network_error':
          return e.message;
        default:
          return e.message;
      }
    }
    return e.toString().replaceFirst('Exception: ', '');
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

  void _route(List<String> roles) {
    if (roles.contains('ROLE_ADMIN')) {
      Navigator.pushReplacementNamed(context, '/admin');
    } else if (roles.contains('ROLE_MODERATOR')) {
      Navigator.pushReplacementNamed(context, '/moderator');
    } else {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: NexusBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _masthead(),
                      const SizedBox(height: 32),
                      _formCard(),
                      const SizedBox(height: 18),
                      _footerRule(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _masthead() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'EDITION \u2014 ${DateTime.now().year}',
              style: AppTheme.label(color: AppTheme.textTertiary),
            ),
            const Spacer(),
            Text(
              'VOL. II',
              style: AppTheme.label(color: AppTheme.persimmon),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(height: 3, color: AppTheme.ink),
        const SizedBox(height: 16),
        RichText(
          text: TextSpan(
            style: AppTheme.display(
              size: 56,
              weight: FontWeight.w700,
              letterSpacing: -2,
              height: 0.95,
            ),
            children: [
              TextSpan(text: 'The '),
              TextSpan(
                text: 'Moderation',
                style: AppTheme.display(
                  size: 56,
                  weight: FontWeight.w400,
                  style: FontStyle.italic,
                  letterSpacing: -2,
                  color: AppTheme.persimmon,
                  height: 0.95,
                ),
              ),
              const TextSpan(text: '\nLedger'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(height: 1, color: AppTheme.hairline),
        const SizedBox(height: 10),
        Text(
          'A daily review of community discourse \u2014 read, refine, release.',
          style: AppTheme.body(
            size: 14,
            color: AppTheme.textSecondary,
            style: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _formCard() {
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
      accentColor: AppTheme.persimmon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '01',
                style: AppTheme.mono(
                  size: 10,
                  color: AppTheme.persimmon,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'SIGN IN \u2014 CREDENTIALS',
                style: AppTheme.label(color: AppTheme.ink, size: 10),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _usernameController,
            label: 'Username',
            prefixIcon: Icons.person_outline,
          ),
          const SizedBox(height: 22),
          AppTextField(
            controller: _passwordController,
            label: 'Password',
            obscureText: _obscurePassword,
            prefixIcon: Icons.lock_outline,
            onSubmitted: (_) => _login(),
            suffixIcon: GestureDetector(
              onTap: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppTheme.textTertiary,
                  size: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 26),
          ActionButton(
            text: 'Enter the Pressroom',
            icon: Icons.arrow_forward,
            isLoading: _isLoading,
            onPressed: _login,
          ),
        ],
      ),
    );
  }

  Widget _footerRule() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'No account?',
          style: AppTheme.body(size: 12, color: AppTheme.textTertiary),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => Navigator.pushNamed(context, '/register'),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.ink, width: 1.2),
              ),
            ),
            child: Text(
              'Take out a subscription',
              style: AppTheme.body(
                size: 12,
                color: AppTheme.ink,
                weight: FontWeight.w600,
                style: FontStyle.italic,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
