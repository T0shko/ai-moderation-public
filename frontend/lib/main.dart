import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/user_home_screen.dart';
import 'screens/moderator_dashboard.dart';
import 'screens/admin_dashboard.dart';
import 'screens/ai_chat_screen.dart';
import 'screens/settings_screen.dart';
import 'services/api_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppTheme.bgDeep,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    MultiProvider(
      providers: [Provider(create: (_) => ApiService())],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Moderation',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      navigatorKey: ApiService.navigatorKey,
      home: const _AuthGate(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home': (context) => const UserHomeScreen(),
        '/moderator': (context) => const ModeratorDashboard(),
        '/admin': (context) => const AdminDashboard(),
        '/chat': (context) => const AiChatScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}

/// Cold-start session check.
///
/// 1. No access token cached → LoginScreen.
/// 2. Token cached → validate it against /auth/me, which silently refreshes
///    via the refresh token if the access token is expired. If validation
///    fails the user is routed to LoginScreen (logout already cleared state).
/// 3. Validation succeeds → resolve home by role.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late final Future<List<String>?> _bootstrap;

  @override
  void initState() {
    super.initState();
    _bootstrap = _resolveSession();
  }

  Future<List<String>?> _resolveSession() async {
    final api = Provider.of<ApiService>(context, listen: false);
    return api.restoreSession();
  }

  Widget _splash() => const Scaffold(
        backgroundColor: AppTheme.paper,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.persimmon),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>?>(
      future: _bootstrap,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _splash();
        }
        final roles = snapshot.data;
        if (roles == null) {
          return const LoginScreen();
        }
        if (roles.contains('ROLE_ADMIN')) {
          return const AdminDashboard();
        }
        if (roles.contains('ROLE_MODERATOR')) {
          return const ModeratorDashboard();
        }
        return const UserHomeScreen();
      },
    );
  }
}
