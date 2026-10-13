// Wais Wallet - security helpers: validation, password rules, auto-logout

import 'package:flutter/material.dart';

import 'core.dart';

/// How long the app may stay in the background before it logs you out.
/// Change this number if you want it stricter or more relaxed.
const Duration kAutoLogoutAfter = Duration(minutes: 10);

final RegExp _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

bool isValidEmail(String v) => _emailRe.hasMatch(v.trim());

class PasswordCheck {
  PasswordCheck(String p)
      : longEnough = p.length >= 10,
        hasLower = RegExp(r'[a-z]').hasMatch(p),
        hasUpper = RegExp(r'[A-Z]').hasMatch(p),
        hasDigit = RegExp(r'[0-9]').hasMatch(p),
        hasSymbol = RegExp(r'[^A-Za-z0-9]').hasMatch(p);

  final bool longEnough;
  final bool hasLower;
  final bool hasUpper;
  final bool hasDigit;
  final bool hasSymbol;

  /// Minimum rule: 10+ characters with lowercase, UPPERCASE and a number.
  bool get ok => longEnough && hasLower && hasUpper && hasDigit;

  /// 0..4 (used by the strength meter)
  int get score =>
      (longEnough ? 1 : 0) +
      ((hasLower && hasUpper) ? 1 : 0) +
      (hasDigit ? 1 : 0) +
      (hasSymbol ? 1 : 0);
}

const _commonPasswords = [
  'password', 'qwerty', '123456', 'abc123', 'iloveyou',
  'admin', 'welcome', 'letmein', 'pass1234', '11111111', 'pilipinas',
];

bool isCommonPassword(String p) {
  final l = p.toLowerCase();
  return _commonPasswords.any((w) => l.contains(w));
}

/// Wrap your logged-in screens with this. If the app stays in the background
/// longer than [kAutoLogoutAfter], you get logged out automatically.
class AutoLockShell extends StatefulWidget {
  const AutoLockShell({super.key, required this.child});

  final Widget child;

  @override
  State<AutoLockShell> createState() => _AutoLockShellState();
}

class _AutoLockShellState extends State<AutoLockShell>
    with WidgetsBindingObserver {
  DateTime? _hiddenAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _hiddenAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final t = _hiddenAt;
      _hiddenAt = null;
      if (t != null && DateTime.now().difference(t) > kAutoLogoutAfter) {
        authNotice.value =
            'Na-logout ka para sa seguridad dahil matagal kang wala. Mag-login ulit.';
        supabase.auth.signOut();
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
