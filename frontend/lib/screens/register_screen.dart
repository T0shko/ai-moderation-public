import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _animController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _register() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      _snack('Please fill in all fields', isError: true);
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      _snack('Passwords do not match', isError: true);
      return;
    }
    if (_passwordController.text.length < 8) {
      _snack('Password must be at least 8 characters', isError: true);
      return;
    }
    if (!RegExp(r'^(?=.*[A-Za-z])(?=.*\d).+$').hasMatch(_passwordController.text)) {
      _snack('Password must include at least one letter and one number',
          isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.register(_usernameController.text, _passwordController.text);
      if (mounted) {
        _snack('Account created');
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) Navigator.pop(context);
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
        case 'username_taken':
          return 'That username is already taken.';
        case 'validation_failed':
          return e.message;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: NexusBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    AppIconButton(
                      icon: Icons.arrow_back,
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'SUBSCRIPTION FORM',
                      style: AppTheme.label(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: FadeTransition(
                        opacity: _fadeAnim,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _masthead(),
                            const SizedBox(height: 28),
                            _formCard(),
                            const SizedBox(height: 20),
                            _footer(),
                          ],
                        ),
                      ),
                    ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'NEW SUBSCRIBER',
              style: AppTheme.label(color: AppTheme.persimmon),
            ),
            const Spacer(),
            Text(
              'PRINT ONLY \u2014 NO ADS',
              style: AppTheme.label(color: AppTheme.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(height: 3, color: AppTheme.ink),
        const SizedBox(height: 16),
        RichText(
          text: TextSpan(
            style: AppTheme.display(
              size: 44,
              weight: FontWeight.w700,
              letterSpacing: -1.5,
              height: 0.98,
            ),
            children: [
              TextSpan(text: 'Take out a '),
              TextSpan(
                text: 'subscription',
                style: AppTheme.display(
                  size: 44,
                  weight: FontWeight.w400,
                  style: FontStyle.italic,
                  letterSpacing: -1.5,
                  color: AppTheme.persimmon,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Pick a name, choose a passphrase, become part of the editorial staff.',
          style: AppTheme.body(
            size: 13,
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
      accentColor: AppTheme.ink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CREDENTIALS',
            style: AppTheme.label(color: AppTheme.ink, size: 10),
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
          const SizedBox(height: 22),
          AppTextField(
            controller: _confirmPasswordController,
            label: 'Confirm Password',
            obscureText: _obscureConfirm,
            prefixIcon: Icons.lock_outline,
            onSubmitted: (_) => _register(),
            suffixIcon: GestureDetector(
              onTap: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  _obscureConfirm
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
            text: 'Stamp & Submit',
            icon: Icons.fiber_manual_record,
            isLoading: _isLoading,
            onPressed: _register,
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Already a subscriber?',
          style: AppTheme.body(size: 12, color: AppTheme.textTertiary),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.ink, width: 1.2),
              ),
            ),
            child: Text(
              'Sign in',
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
