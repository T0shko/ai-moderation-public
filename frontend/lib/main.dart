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
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.bgDeep,
      systemNavigationBarIconBrightness: Brightness.light,
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
      theme: AppTheme.darkTheme,
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

/// Checks for a valid stored session on cold start.
/// If a token + roles exist, skip login and go straight to the right screen.
/// Otherwise show the login screen.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final api = Provider.of<ApiService>(context, listen: false);
    return FutureBuilder<String?>(
      future: api.getToken(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: AppTheme.bgDeep,
            body: Center(
              child: CircularProgressIndicator(color: AppTheme.coral),
            ),
          );
        }

        final token = snapshot.data;
        if (token == null || token.isEmpty) {
          return const LoginScreen();
        }

        // Token exists – resolve destination from roles
        return FutureBuilder<List<String>>(
          future: api.getRoles(),
          builder: (ctx, roleSnap) {
            if (roleSnap.connectionState != ConnectionState.done) {
              return const Scaffold(
                backgroundColor: AppTheme.bgDeep,
                body: Center(
                  child: CircularProgressIndicator(color: AppTheme.coral),
                ),
              );
            }
            final roles = roleSnap.data ?? [];
            if (roles.contains('ROLE_ADMIN')) {
              return const AdminDashboard();
            } else if (roles.contains('ROLE_MODERATOR')) {
              return const ModeratorDashboard();
            } else {
              return const UserHomeScreen();
            }
          },
        );
      },
    );
  }
}
