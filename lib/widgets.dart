// Wais Wallet - reusable UI pieces

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'core.dart';
import 'security.dart';

/// Soft animated green background with floating glows.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [Color(0xFF04100B), Color(0xFF0A2118)]
                    : const [Color(0xFFF1FBF6), Color(0xFFDDF6E8)],
              ),
            ),
          ),
        ),
        Positioned(
          top: -120,
          right: -80,
          child: _Glow(color: cs.primary, size: 340)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: -14, end: 14, duration: 5.seconds, curve: Curves.easeInOut),
        ),
        Positioned(
          bottom: -140,
          left: -100,
          child: _Glow(color: cs.secondary, size: 320)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: 12, end: -12, duration: 6.seconds, curve: Curves.easeInOut),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.32),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 24,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: dark ? 0.72 : 0.88),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: dark ? 0.6 : 0.9),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: dark ? 0.05 : 0.07),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 76, this.showName = true});

  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.32),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.primary, cs.secondary],
            ),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.4),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Icon(
            Icons.account_balance_wallet_rounded,
            color: cs.onPrimary,
            size: size * 0.5,
          ),
        )
            .animate()
            .scale(
              begin: const Offset(0.6, 0.6),
              duration: 550.ms,
              curve: Curves.easeOutBack,
            )
            .fadeIn(),
        if (showName) ...[
          const SizedBox(height: 14),
          Text(
            'Wais Wallet',
            style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 2),
          Text(
            'Ipon smart. Gastos alam.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ).animate().fadeIn(delay: 300.ms),
        ],
      ],
    );
  }
}

/// Full-width main button with a built-in loading spinner.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: loading ? () {} : onPressed,
        child: AnimatedSwitcher(
          duration: 200.ms,
          child: loading
              ? SizedBox(
                  key: const ValueKey('loading'),
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: cs.onPrimary,
                  ),
                )
              : Row(
                  key: const ValueKey('label'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20),
                      const SizedBox(width: 8),
                    ],
                    Text(label),
                  ],
                ),
        ),
      ),
    );
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hide = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _hide,
      enableSuggestions: false,
      autocorrect: false,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.lock_rounded),
        suffixIcon: IconButton(
          icon: Icon(
            _hide ? Icons.visibility_rounded : Icons.visibility_off_rounded,
          ),
          onPressed: () => setState(() => _hide = !_hide),
        ),
      ),
    );
  }
}

/// Animated password strength bar + requirement checklist.
class StrengthMeter extends StatelessWidget {
  const StrengthMeter({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = PasswordCheck(password);
    final filled = password.isEmpty ? 0 : (c.score < 1 ? 1 : c.score);
    final labels = ['Mahina', 'Okay', 'Malakas', 'Napakalakas'];
    final colors = [cs.error, Colors.orange, cs.primary, cs.secondary];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < 4; i++)
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 6,
                  margin: EdgeInsets.only(right: i == 3 ? 0 : 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: i < filled
                        ? colors[filled - 1]
                        : cs.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            _Req(label: '10+ characters', ok: c.longEnough),
            _Req(label: 'Aa', ok: c.hasLower && c.hasUpper),
            _Req(label: '123', ok: c.hasDigit),
            _Req(label: '!@#  (extra)', ok: c.hasSymbol),
          ],
        ),
        if (filled > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              labels[filled - 1],
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors[filled - 1],
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
      ],
    );
  }
}

class _Req extends StatelessWidget {
  const _Req({required this.label, required this.ok});

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = ok ? cs.primary : cs.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.circle_outlined,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}

/// Page layout for login / sign-up / forgot password screens.
class AuthShell extends StatelessWidget {
  const AuthShell({super.key, required this.child, this.showBack = false});

  final Widget child;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 56, 24, 32),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxContentWidth(context, 440)),
                    child: child,
                  ),
                ),
              ),
              if (showBack)
                Positioned(
                  top: 4,
                  left: 8,
                  child: IconButton.filledTonal(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Back button + title row used on inner pages.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class CountUpText extends StatelessWidget {
  const CountUpText({super.key, required this.value, required this.format, this.style});

  final double value;
  final String Function(double) format;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: value),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(format(v), style: style, maxLines: 1, softWrap: false),
      ),
    );
  }
}
