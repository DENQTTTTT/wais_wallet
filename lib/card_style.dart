// Wais Wallet - customizable card design
// A card's look is saved in cards.style (jsonb). null = default look.

import 'package:flutter/material.dart';

enum CardPattern { none, glow, circles, lines }

const cardPresets = <List<Color>>[
  [Color(0xFF0B6B4F), Color(0xFF00C27A)],
  [Color(0xFF123A2F), Color(0xFF2BAE7D)],
  [Color(0xFF1F7A4D), Color(0xFFB8F34A)],
  [Color(0xFF0A4F4A), Color(0xFF12B5A0)],
  [Color(0xFF0A2E7A), Color(0xFF2563D6)],
  [Color(0xFF0A6BB5), Color(0xFF4DB8F0)],
  [Color(0xFF4A1A6B), Color(0xFF9B4DCA)],
  [Color(0xFF9D174D), Color(0xFFF472B6)],
  [Color(0xFF9E1B1F), Color(0xFFE2474B)],
  [Color(0xFFD9480F), Color(0xFFFF9A3C)],
  [Color(0xFFB7791F), Color(0xFFF6D365)],
  [Color(0xFF111418), Color(0xFF3A424D)],
  [Color(0xFFBFC6D1), Color(0xFFF1F3F6)],
];

class CardStyle {
  const CardStyle({
    this.colors,
    this.pattern = CardPattern.none,
    this.darkText = false,
    this.emoji,
  });

  /// Exactly 2 colors (gradient). null = automatic color by position.
  final List<Color>? colors;
  final CardPattern pattern;
  final bool darkText;
  final String? emoji;

  bool get isDefault =>
      colors == null && pattern == CardPattern.none && !darkText && emoji == null;

  CardStyle copyWith({
    List<Color>? colors,
    CardPattern? pattern,
    bool? darkText,
    String? emoji,
    bool clearEmoji = false,
  }) {
    return CardStyle(
      colors: colors ?? this.colors,
      pattern: pattern ?? this.pattern,
      darkText: darkText ?? this.darkText,
      emoji: clearEmoji ? null : (emoji ?? this.emoji),
    );
  }

  Map<String, dynamic> toJson() {
    final c = colors;
    return {
      if (c != null && c.length == 2) 'c1': c[0].toARGB32(),
      if (c != null && c.length == 2) 'c2': c[1].toARGB32(),
      'pattern': pattern.name,
      'dark': darkText,
      if (emoji != null) 'emoji': emoji,
    };
  }

  static CardStyle fromJson(Object? j) {
    if (j is! Map) return const CardStyle();
    List<Color>? colors;
    final c1 = j['c1'];
    final c2 = j['c2'];
    if (c1 is num && c2 is num) {
      colors = [
        Color(c1.toInt() | 0xFF000000),
        Color(c2.toInt() | 0xFF000000),
      ];
    }
    final p = CardPattern.values.firstWhere(
      (e) => e.name == j['pattern'],
      orElse: () => CardPattern.none,
    );
    final e = j['emoji'];
    return CardStyle(
      colors: colors,
      pattern: p,
      darkText: j['dark'] == true,
      emoji: (e is String && e.isNotEmpty) ? e : null,
    );
  }
}

/// Soft decorative pattern drawn on top of the gradient.
class CardPatternPainter extends CustomPainter {
  CardPatternPainter(this.pattern, this.color);

  final CardPattern pattern;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    switch (pattern) {
      case CardPattern.none:
        break;
      case CardPattern.glow:
        final p = Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.0)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.85, size.height * 0.1),
              radius: size.width * 0.6,
            ),
          );
        canvas.drawRect(Offset.zero & size, p);
        break;
      case CardPattern.circles:
        final p = Paint()..color = color.withValues(alpha: 0.12);
        canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.15), size.height * 0.55, p);
        canvas.drawCircle(Offset(size.width * 0.75, size.height * 0.95), size.height * 0.4, p);
        canvas.drawCircle(Offset(size.width * 0.1, size.height * 1.05), size.height * 0.35, p);
        break;
      case CardPattern.lines:
        final p = Paint()
          ..color = color.withValues(alpha: 0.12)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
        for (double x = -size.height; x < size.width; x += 22) {
          canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CardPatternPainter old) =>
      old.pattern != pattern || old.color != color;
}

// ---------------------------------------------------------------- DESIGNER

class CardDesigner extends StatefulWidget {
  const CardDesigner({
    super.key,
    required this.style,
    required this.defaultColors,
    required this.onChanged,
  });

  final CardStyle style;
  final List<Color> defaultColors;
  final ValueChanged<CardStyle> onChanged;

  @override
  State<CardDesigner> createState() => _CardDesignerState();
}

class _CardDesignerState extends State<CardDesigner> {
  static const _emojis = ['💳', '🛒', '✈️', '🍔', '🏠', '⭐', '💎', '🔥', '🎮', '🐷', '💰', '🎯'];

  late bool _customOpen;

  bool _same(List<Color> a, List<Color> b) =>
      a[0].toARGB32() == b[0].toARGB32() && a[1].toARGB32() == b[1].toARGB32();

  @override
  void initState() {
    super.initState();
    final c = widget.style.colors;
    _customOpen = c != null && !cardPresets.any((p) => _same(p, c));
  }

  Widget _label(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(
          t,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = widget.style;
    final colors = style.colors;
    final current = colors ?? widget.defaultColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(context, 'Kulay'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final p in cardPresets)
              _Swatch(
                gradient: LinearGradient(colors: p),
                selected: !_customOpen && colors != null && _same(p, colors),
                onTap: () {
                  setState(() => _customOpen = false);
                  widget.onChanged(style.copyWith(colors: p));
                },
              ),
            _Swatch(
              gradient: const SweepGradient(
                colors: [
                  Color(0xFFFF4D4D),
                  Color(0xFFFFD84D),
                  Color(0xFF4DFF88),
                  Color(0xFF4DB8FF),
                  Color(0xFFB04DFF),
                  Color(0xFFFF4D4D),
                ],
              ),
              selected: _customOpen,
              icon: Icons.palette_rounded,
              onTap: () {
                setState(() => _customOpen = true);
                widget.onChanged(style.copyWith(colors: [current[0], current[1]]));
              },
            ),
          ],
        ),
        if (_customOpen) ...[
          const SizedBox(height: 12),
          _HsvEditor(
            label: 'Kulay 1',
            color: current[0],
            onChanged: (c) => widget.onChanged(style.copyWith(colors: [c, current[1]])),
          ),
          const SizedBox(height: 8),
          _HsvEditor(
            label: 'Kulay 2',
            color: current[1],
            onChanged: (c) => widget.onChanged(style.copyWith(colors: [current[0], c])),
          ),
        ],
        _label(context, 'Background'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in const [
              (CardPattern.none, 'Plain'),
              (CardPattern.glow, 'Glow'),
              (CardPattern.circles, 'Bilog'),
              (CardPattern.lines, 'Guhit'),
            ])
              ChoiceChip(
                label: Text(e.$2),
                selected: style.pattern == e.$1,
                onSelected: (_) => widget.onChanged(style.copyWith(pattern: e.$1)),
              ),
          ],
        ),
        _label(context, 'Kulay ng text'),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Puti'),
              selected: !style.darkText,
              onSelected: (_) => widget.onChanged(style.copyWith(darkText: false)),
            ),
            ChoiceChip(
              label: const Text('Madilim'),
              selected: style.darkText,
              onSelected: (_) => widget.onChanged(style.copyWith(darkText: true)),
            ),
          ],
        ),
        _label(context, 'Emoji sa card'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _EmojiChip(
              selected: style.emoji == null,
              onTap: () => widget.onChanged(style.copyWith(clearEmoji: true)),
              child: Icon(Icons.block_rounded, size: 20, color: cs.onSurfaceVariant),
            ),
            for (final e in _emojis)
              _EmojiChip(
                selected: style.emoji == e,
                onTap: () => widget.onChanged(style.copyWith(emoji: e)),
                child: Text(e, style: const TextStyle(fontSize: 22)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() => _customOpen = false);
              widget.onChanged(const CardStyle());
            },
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('I-reset ang disenyo'),
          ),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.gradient, required this.selected, required this.onTap, this.icon});

  final Gradient gradient;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: gradient,
          border: Border.all(
            color: selected ? cs.onSurface : Colors.white24,
            width: selected ? 3 : 1,
          ),
        ),
        child: icon != null
            ? Icon(icon, size: 18, color: Colors.white)
            : (selected ? const Icon(Icons.check_rounded, size: 18, color: Colors.white) : null),
      ),
    );
  }
}

class _EmojiChip extends StatelessWidget {
  const _EmojiChip({required this.selected, required this.onTap, required this.child});

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected ? cs.primary.withValues(alpha: 0.18) : cs.surfaceContainerHighest.withValues(alpha: 0.4),
          border: Border.all(color: selected ? cs.primary : Colors.transparent, width: 2),
        ),
        child: child,
      ),
    );
  }
}

class _HsvEditor extends StatelessWidget {
  const _HsvEditor({required this.label, required this.color, required this.onChanged});

  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;

  Widget _slider(String name, double value, double max, ValueChanged<double> cb) {
    return Row(
      children: [
        SizedBox(width: 84, child: Text(name)),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, max).toDouble(),
            min: 0,
            max: max,
            onChanged: cb,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hsv = HSVColor.fromColor(color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        _slider('Hue', hsv.hue, 360, (v) => onChanged(hsv.withHue(v).toColor())),
        _slider('Saturation', hsv.saturation, 1, (v) => onChanged(hsv.withSaturation(v).toColor())),
        _slider('Brightness', hsv.value, 1, (v) => onChanged(hsv.withValue(v).toColor())),
      ],
    );
  }
}
