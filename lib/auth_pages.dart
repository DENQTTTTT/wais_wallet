// Wais Wallet - auth screens: Login, Create Account, Check Email,
// Forgot Password, Reset Password

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core.dart';
import 'security.dart';
import 'widgets.dart';

TextStyle? _title(BuildContext c) => Theme.of(c)
    .textTheme
    .headlineSmall
    ?.copyWith(fontWeight: FontWeight.w800);

TextStyle? _sub(BuildContext c) => Theme.of(c)
    .textTheme
    .bodyMedium
    ?.copyWith(color: Theme.of(c).colorScheme.onSurfaceVariant, height: 1.4);

// ---------------------------------------------------------------- LOGIN

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  int _fails = 0;
  DateTime? _lockedUntil;

  Future<void> _login() async {
    final now = DateTime.now();
    if (_lockedUntil != null && now.isBefore(_lockedUntil!)) {
      final s = _lockedUntil!.difference(now).inSeconds + 1;
      showMsg(context, 'Masyadong maraming maling subok. Subukan ulit sa loob ng $s segundo.', error: true);
      return;
    }
    final email = _email.text.trim();
    if (!isValidEmail(email) || _password.text.isEmpty) {
      showMsg(context, 'Ilagay ang tamang email at password.', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await supabase.auth.signInWithPassword(email: email, password: _password.text);
      authNotice.value = null;
      _fails = 0;
    } on AuthException catch (e) {
      _fails++;
      if (_fails >= 5) {
        _lockedUntil = DateTime.now().add(const Duration(seconds: 30));
        _fails = 0;
      }
      if (mounted) showMsg(context, friendlyAuthError(e), error: true);
    } catch (e) {
      if (mounted) showMsg(context, friendlyAuthError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AuthShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: BrandMark()),
          const SizedBox(height: 32),
          ValueListenableBuilder<String?>(
            valueListenable: authNotice,
            builder: (context, msg, child) {
              if (msg == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.info_rounded, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(child: Text(msg, style: _sub(context))),
                    ],
                  ),
                ).animate().fadeIn().slideY(begin: -0.2),
              );
            },
          ),
          Text('Welcome back ', style: _title(context))
              .animate()
              .fadeIn(delay: 100.ms)
              .slideY(begin: 0.2),
          const SizedBox(height: 6),
          Text('Mag-login para makita ang iyong ipon at gastos.', style: _sub(context))
              .animate()
              .fadeIn(delay: 160.ms),
          const SizedBox(height: 22),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
          ).animate().fadeIn(delay: 220.ms).slideY(begin: 0.2),
          const SizedBox(height: 14),
          PasswordField(
            controller: _password,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _login(),
          ).animate().fadeIn(delay: 280.ms).slideY(begin: 0.2),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () =>
                  Navigator.of(context).push(softRoute(const ForgotPasswordPage())),
              child: const Text('Forgot password?'),
            ),
          ),
          const SizedBox(height: 6),
          PrimaryButton(
            label: 'Log in',
            icon: Icons.login_rounded,
            loading: _loading,
            onPressed: _login,
          ).animate().fadeIn(delay: 340.ms).slideY(begin: 0.2),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(child: Divider(color: cs.outlineVariant)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('wala pang account?', style: _sub(context)),
              ),
              Expanded(child: Divider(color: cs.outlineVariant)),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).push(softRoute(const SignUpPage())),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Create account'),
            ),
          ).animate().fadeIn(delay: 400.ms),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- SIGN UP

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;

  Future<void> _signUp() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final pass = _password.text;

    if (!isValidEmail(email)) {
      showMsg(context, 'Ilagay ang tamang email.', error: true);
      return;
    }
    if (!PasswordCheck(pass).ok) {
      showMsg(context, 'Sundin ang password requirements (10+ characters, Aa, 123).', error: true);
      return;
    }
    if (isCommonPassword(pass)) {
      showMsg(context, 'Masyadong common ang password na yan. Gumawa ng mas kakaiba.', error: true);
      return;
    }
    if (pass != _confirm.text) {
      showMsg(context, 'Hindi magkapareho ang password at confirm password.', error: true);
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await supabase.auth.signUp(
        email: email,
        password: pass,
        data: name.isEmpty ? null : {'display_name': name},
      );
      if (!mounted) return;
      if (res.session != null) {
        // Email confirmation is OFF: you're already logged in.
        Navigator.of(context).popUntil((r) => r.isFirst);
      } else {
        Navigator.of(context).pushReplacement(softRoute(CheckEmailPage(email: email)));
      }
      return;
    } on AuthException catch (e) {
      if (mounted) showMsg(context, friendlyAuthError(e), error: true);
    } catch (e) {
      if (mounted) showMsg(context, friendlyAuthError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: BrandMark(size: 60, showName: false)),
          const SizedBox(height: 22),
          Text('Gumawa ng account', style: _title(context))
              .animate()
              .fadeIn(delay: 80.ms)
              .slideY(begin: 0.2),
          const SizedBox(height: 6),
          Text('Libre at ligtas. Ikaw lang ang makakakita ng data mo.', style: _sub(context))
              .animate()
              .fadeIn(delay: 140.ms),
          const SizedBox(height: 22),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Pangalan (optional)',
              prefixIcon: Icon(Icons.person_rounded),
            ),
          ).animate().fadeIn(delay: 180.ms).slideY(begin: 0.2),
          const SizedBox(height: 14),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
          ).animate().fadeIn(delay: 230.ms).slideY(begin: 0.2),
          const SizedBox(height: 14),
          PasswordField(
            controller: _password,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
          ).animate().fadeIn(delay: 280.ms).slideY(begin: 0.2),
          const SizedBox(height: 12),
          StrengthMeter(password: _password.text),
          const SizedBox(height: 14),
          PasswordField(
            controller: _confirm,
            label: 'Confirm password',
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _signUp(),
          ).animate().fadeIn(delay: 330.ms).slideY(begin: 0.2),
          const SizedBox(height: 22),
          PrimaryButton(
            label: 'Create account',
            icon: Icons.check_rounded,
            loading: _loading,
            onPressed: _signUp,
          ).animate().fadeIn(delay: 380.ms),
          const SizedBox(height: 14),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('May account na? Log in'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- CHECK EMAIL

class CheckEmailPage extends StatelessWidget {
  const CheckEmailPage({super.key, required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AuthShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primaryContainer,
              ),
              child: Icon(Icons.mark_email_read_rounded, size: 48, color: cs.primary),
            )
                .animate()
                .scale(duration: 600.ms, curve: Curves.easeOutBack)
                .fadeIn(),
          ),
          const SizedBox(height: 24),
          Text('I-check ang email mo', textAlign: TextAlign.center, style: _title(context))
              .animate()
              .fadeIn(delay: 200.ms),
          const SizedBox(height: 10),
          Text(
            'Nagpadala kami ng confirmation link sa\n$email\n\nI-click ang link para ma-activate ang account mo. Kung wala sa inbox, tingnan ang spam.',
            textAlign: TextAlign.center,
            style: _sub(context),
          ).animate().fadeIn(delay: 280.ms),
          const SizedBox(height: 28),
          PrimaryButton(
            label: 'Back to login',
            icon: Icons.arrow_back_rounded,
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ).animate().fadeIn(delay: 360.ms),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- FORGOT PASSWORD

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _email = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  int _cooldown = 0;
  Timer? _timer;

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!isValidEmail(email)) {
      showMsg(context, 'Ilagay ang tamang email.', error: true);
      return;
    }
    if (_cooldown > 0) return;
    setState(() => _loading = true);
    try {
      await supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: kIsWeb ? Uri.base.origin : null,
      );
    } catch (_) {
      // Intentionally ignored: we never reveal whether an email exists.
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _sent = true;
      _cooldown = 60;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AuthShell(
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primaryContainer),
              child: Icon(Icons.lock_reset_rounded, size: 42, color: cs.primary),
            ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack).fadeIn(),
          ),
          const SizedBox(height: 22),
          Text('Nakalimutan ang password?', textAlign: TextAlign.center, style: _title(context))
              .animate()
              .fadeIn(delay: 120.ms),
          const SizedBox(height: 8),
          Text(
            'Ilagay ang email mo at padadalhan ka namin ng link para gumawa ng bagong password.',
            textAlign: TextAlign.center,
            style: _sub(context),
          ).animate().fadeIn(delay: 180.ms),
          const SizedBox(height: 24),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            onSubmitted: (_) => _send(),
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
          ).animate().fadeIn(delay: 240.ms).slideY(begin: 0.2),
          const SizedBox(height: 18),
          PrimaryButton(
            label: _cooldown > 0 ? 'Ulitin sa ${_cooldown}s' : 'Send reset link',
            icon: Icons.send_rounded,
            loading: _loading,
            onPressed: _cooldown > 0 ? null : _send,
          ).animate().fadeIn(delay: 300.ms),
          if (_sent) ...[
            const SizedBox(height: 18),
            GlassCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.mark_email_read_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Kung may account na naka-register sa email na yan, may darating na link sa inbox mo. I-check din ang spam.',
                      style: _sub(context),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn().slideY(begin: 0.2),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- RESET PASSWORD

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;

  Future<void> _save() async {
    final pass = _password.text;
    if (!PasswordCheck(pass).ok || isCommonPassword(pass)) {
      showMsg(context, 'Sundin ang password requirements at iwasan ang common passwords.', error: true);
      return;
    }
    if (pass != _confirm.text) {
      showMsg(context, 'Hindi magkapareho ang mga password.', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await supabase.auth.updateUser(UserAttributes(password: pass));
      await supabase.auth.signOut();
      authNotice.value = 'Na-update na ang password mo. Mag-login gamit ang bago. ✅';
      widget.onDone();
      return;
    } catch (e) {
      if (mounted) showMsg(context, friendlyAuthError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AuthShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primaryContainer),
              child: Icon(Icons.key_rounded, size: 42, color: cs.primary),
            ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack).fadeIn(),
          ),
          const SizedBox(height: 22),
          Text('Gumawa ng bagong password', textAlign: TextAlign.center, style: _title(context))
              .animate()
              .fadeIn(delay: 120.ms),
          const SizedBox(height: 22),
          PasswordField(
            controller: _password,
            label: 'New password',
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          StrengthMeter(password: _password.text),
          const SizedBox(height: 14),
          PasswordField(
            controller: _confirm,
            label: 'Confirm new password',
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 22),
          PrimaryButton(
            label: 'Save new password',
            icon: Icons.check_rounded,
            loading: _loading,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
