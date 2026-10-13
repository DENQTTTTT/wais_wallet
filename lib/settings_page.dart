// Wais Wallet - settings: appearance (themes), security, account

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core.dart';
import 'budgets_page.dart';
import 'recurring_page.dart';
import 'security.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<bool> _confirm(BuildContext context, String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final user = supabase.auth.currentUser;
    final name = (user?.userMetadata?['display_name'] as String?)?.trim() ?? '';

    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth(context, 560)),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  const PageHeader(title: 'Settings'),
                  const SizedBox(height: 18),

                  // ---- account
                  GlassCard(
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [cs.primary, cs.secondary]),
                          ),
                          child: Icon(Icons.person_rounded, color: cs.onPrimary),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (name.isNotEmpty)
                                Text(name, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                              Text(
                                user?.email ?? '',
                                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn().slideY(begin: 0.1),
                  const SizedBox(height: 22),

                  // ---- automation
                  _SectionTitle('Automation'),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).push(softRoute(const RecurringPage())),
                    child: GlassCard(
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: cs.primary.withValues(alpha: 0.12),
                            ),
                            child: Icon(Icons.autorenew_rounded, color: cs.primary, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Recurring', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                                Text(
                                  'Sahod, rent, subscriptions na kusang ma-lo-log',
                                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).push(softRoute(const BudgetsPage())),
                    child: GlassCard(
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: cs.primary.withValues(alpha: 0.12),
                            ),
                            child: Icon(Icons.savings_outlined, color: cs.primary, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Budgets', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                                Text(
                                  'Monthly limit bawat category, may warning',
                                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // ---- appearance
                  _SectionTitle('Appearance'),
                  ListenableBuilder(
                    listenable: themeController,
                    builder: (context, child) {
                      return GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Theme', style: tt.labelLarge),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<ThemeMode>(
                                segments: const [
                                  ButtonSegment(
                                    value: ThemeMode.system,
                                    label: Text('Auto'),
                                    icon: Icon(Icons.brightness_auto_rounded),
                                  ),
                                  ButtonSegment(
                                    value: ThemeMode.light,
                                    label: Text('Light'),
                                    icon: Icon(Icons.light_mode_rounded),
                                  ),
                                  ButtonSegment(
                                    value: ThemeMode.dark,
                                    label: Text('Dark'),
                                    icon: Icon(Icons.dark_mode_rounded),
                                  ),
                                ],
                                selected: {themeController.mode},
                                onSelectionChanged: (s) => themeController.setMode(s.first),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text('Green style', style: tt.labelLarge),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 16,
                              runSpacing: 14,
                              children: [
                                for (var i = 0; i < accents.length; i++)
                                  _Swatch(
                                    option: accents[i],
                                    selected: themeController.accentIndex == i,
                                    onTap: () => themeController.setAccent(i),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ).animate().fadeIn(delay: 80.ms).slideY(begin: 0.1),
                  const SizedBox(height: 22),

                  // ---- security
                  _SectionTitle('Security'),
                  GlassCard(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        _Tile(
                          icon: Icons.password_rounded,
                          title: 'Change password',
                          subtitle: 'Kailangan ang current password mo',
                          onTap: () => Navigator.of(context)
                              .push(softRoute(const ChangePasswordPage())),
                        ),
                        _Tile(
                          icon: Icons.timer_rounded,
                          title: 'Auto-logout',
                          subtitle:
                              'Automatic na logout kapag ${kAutoLogoutAfter.inMinutes} minuto kang wala sa app',
                        ),
                        _Tile(
                          icon: Icons.devices_rounded,
                          title: 'Log out sa lahat ng devices',
                          subtitle: 'Gamitin kung nawala o na-share ang device mo',
                          onTap: () async {
                            final ok = await _confirm(
                              context,
                              'Log out sa lahat?',
                              'Ila-logout ka sa lahat ng devices, pati dito.',
                              'Log out all',
                            );
                            if (ok) {
                              await supabase.auth.signOut(scope: SignOutScope.global);
                              if (context.mounted) {
                                Navigator.of(context).popUntil((r) => r.isFirst);
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 160.ms).slideY(begin: 0.1),
                  const SizedBox(height: 22),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await _confirm(
                          context,
                          'Mag-logout?',
                          'Kailangan mong mag-login ulit.',
                          'Log out',
                        );
                        if (ok) {
                          await supabase.auth.signOut();
                          if (context.mounted) {
                            Navigator.of(context).popUntil((r) => r.isFirst);
                          }
                        }
                      },
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Log out'),
                    ),
                  ).animate().fadeIn(delay: 240.ms),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, this.subtitle, this.onTap});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: cs.primary.withValues(alpha: 0.12),
        ),
        child: Icon(icon, color: cs.primary, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.option, required this.selected, required this.onTap});

  final AccentOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [option.seed, option.glow],
              ),
              border: Border.all(
                color: selected ? cs.onSurface : Colors.transparent,
                width: 3,
              ),
            ),
            child: AnimatedScale(
              scale: selected ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              child: const Icon(Icons.check_rounded, color: Colors.white),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            option.name,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- CHANGE PASSWORD

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;

  Future<void> _save() async {
    final email = supabase.auth.currentUser?.email;
    if (email == null || _current.text.isEmpty) {
      showMsg(context, 'Ilagay ang current password mo.', error: true);
      return;
    }
    if (!PasswordCheck(_new.text).ok || isCommonPassword(_new.text)) {
      showMsg(context, 'Sundin ang password requirements at iwasan ang common passwords.', error: true);
      return;
    }
    if (_new.text != _confirm.text) {
      showMsg(context, 'Hindi magkapareho ang mga bagong password.', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      // Re-check the current password first (proves it's really you).
      await supabase.auth.signInWithPassword(email: email, password: _current.text);
      await supabase.auth.updateUser(UserAttributes(password: _new.text));
      if (!mounted) return;
      showMsg(context, 'Na-update na ang password mo ✅');
      Navigator.of(context).pop();
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
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth(context, 480)),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  const PageHeader(title: 'Change password'),
                  const SizedBox(height: 22),
                  PasswordField(
                    controller: _current,
                    label: 'Current password',
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  PasswordField(
                    controller: _new,
                    label: 'New password',
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  StrengthMeter(password: _new.text),
                  const SizedBox(height: 14),
                  PasswordField(
                    controller: _confirm,
                    label: 'Confirm new password',
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 22),
                  PrimaryButton(
                    label: 'Update password',
                    icon: Icons.check_rounded,
                    loading: _loading,
                    onPressed: _save,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
