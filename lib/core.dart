// Wais Wallet - shared helpers (Supabase client, formatting, messages, routes)

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

/// One-time message shown on the login page (e.g. after auto-logout).
final ValueNotifier<String?> authNotice = ValueNotifier<String?>(null);

String fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String peso(num n) {
  final neg = n < 0;
  final parts = n.abs().toStringAsFixed(2).split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );
  return '${neg ? '-' : ''}₱$whole.${parts[1]}';
}

const monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

void showMsg(BuildContext context, String text, {bool error = false}) {
  final cs = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: TextStyle(color: error ? cs.onError : null),
        ),
        backgroundColor: error ? cs.error : null,
      ),
    );
}

/// Turns auth errors into friendly messages (and never reveals whether an
/// email exists).
String friendlyAuthError(Object e) {
  final raw = (e is AuthException) ? e.message : e.toString();
  final m = raw.toLowerCase();
  if (m.contains('invalid login') || m.contains('invalid credentials')) {
    return 'Mali ang email o password.';
  }
  if (m.contains('not confirmed')) {
    return 'Kumpirmahin muna ang email mo. I-check ang inbox (pati spam).';
  }
  if (m.contains('rate limit') || m.contains('too many')) {
    return 'Masyadong maraming subok. Maghintay muna ng ilang minuto.';
  }
  if (m.contains('already registered') || m.contains('already been registered')) {
    return 'May account na gamit ang email na ito. Subukang mag-login.';
  }
  if (m.contains('weak') || m.contains('password should')) {
    return 'Masyadong mahina ang password. Sundin ang mga requirements.';
  }
  if (m.contains('network') ||
      m.contains('socket') ||
      m.contains('failed host') ||
      m.contains('clientexception')) {
    return 'Walang koneksyon. I-check ang internet mo.';
  }
  return raw;
}

/// Soft fade + slide page transition.
Route<T> softRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, animation, secondary) => page,
    transitionsBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Width helpers so the layout adapts to phone, tablet and wide web windows.
double maxContentWidth(BuildContext context, double base) {
  final w = MediaQuery.sizeOf(context).width;
  if (w >= 1200) return base * 1.35;
  if (w >= 900) return base * 1.2;
  return base;
}

/// Very small phones (about 360dp wide or less).
bool isNarrow(BuildContext context) => MediaQuery.sizeOf(context).width < 360;

/// Side padding for pages: tighter on small phones.
double pagePad(BuildContext context) => isNarrow(context) ? 14.0 : 20.0;
