// Wais Wallet - app entry point
// Needs: lib/config.dart (your Supabase URL + anon key)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_pages.dart';
import 'config.dart';
import 'home_page.dart';
import 'security.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  await themeController.load();
  runApp(const WaisWalletApp());
}

class WaisWalletApp extends StatelessWidget {
  const WaisWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, child) {
        final accent = themeController.accent;
        return MaterialApp(
          title: 'Wais Wallet',
          debugShowCheckedModeBanner: false,
          themeMode: themeController.mode,
          theme: buildTheme(accent, Brightness.light),
          darkTheme: buildTheme(accent, Brightness.dark),
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final w = mq.size.width;
            // what the user set in phone settings, kept within a safe range
            final user = (mq.textScaler.scale(100) / 100).clamp(0.85, 1.3).toDouble();
            // gentle adjustment by screen width
            final fit = w < 340
                ? 0.88
                : w < 380
                    ? 0.94
                    : w >= 1000
                        ? 1.12
                        : w >= 700
                            ? 1.05
                            : 1.0;
            final scale = (user * fit).clamp(0.8, 1.45).toDouble();
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(scale)),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const AuthGate(),
        );
      },
    );
  }
}

/// Decides what to show: login, "set new password" (after a reset link), or home.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _sub;
  bool _recovering = false;

  @override
  void initState() {
    super.initState();
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      setState(() {
        if (data.event == AuthChangeEvent.passwordRecovery) {
          _recovering = true;
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_recovering) {
      return ResetPasswordPage(onDone: () => setState(() => _recovering = false));
    }
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return const LoginPage();
    return const AutoLockShell(child: HomePage());
  }
}