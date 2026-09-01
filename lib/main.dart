import 'package:flutter/material.dart';

import 'pages/login_page.dart';
import 'pages/shell_page.dart';
import 'services/api_client.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JmClientApp());
}

class JmClientApp extends StatelessWidget {
  const JmClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFE04F62);
    return MaterialApp(
      title: '禁漫客户端',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF141318),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1B1A20),
          centerTitle: false,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF1B1A20),
          indicatorColor: seed.withValues(alpha: 0.22),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<void> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiClient.instance.auth.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final hasSession = ApiClient.instance.auth.hasSession;
        return hasSession ? const ShellPage() : const LoginPage();
      },
    );
  }
}
