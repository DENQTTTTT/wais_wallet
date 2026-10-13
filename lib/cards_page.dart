// Wais Wallet - credit cards: list, detail, statements, due dates

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'card_style.dart';
import 'cards_logic.dart';
import 'core.dart';
import 'soa_import.dart';
import 'soa_parser.dart';
import 'widgets.dart';

const _cardGradients = <List<Color>>[
  [Color(0xFF0B6B4F), Color(0xFF00C27A)],
  [Color(0xFF123A2F), Color(0xFF2BAE7D)],
  [Color(0xFF1F7A4D), Color(0xFFB8F34A)],
  [Color(0xFF0A4F4A), Color(0xFF12B5A0)],
];

Future<bool> _confirm(BuildContext context, String title, String body, String action) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return ok ?? false;
}

Future<DateTime?> _pickDate(BuildContext context, DateTime initial) {
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
  );
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

// ---------------------------------------------------------------- CARD VISUAL

class CardVisual extends StatelessWidget {
  const CardVisual({
    super.key,
    required this.card,
    required this.index,
    this.due,
    this.onTap,
  });

  final Map<String, dynamic> card;
  final int index;
  final DueItem? due;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final style = CardStyle.fromJson(card['style']);
    final colors = style.colors ?? _cardGradients[index % _cardGradients.length];
    final bank = ((card['bank'] as String?) ?? '').trim();
    final last4 = ((card['last4'] as String?) ?? '').trim();
    final name = (card['nickname'] as String?) ?? 'Card';
    final fg = style.darkText ? const Color(0xFF111418) : Colors.white;
    final fgSoft = fg.withValues(alpha: 0.75);
    final emoji = style.emoji;

    final availW = MediaQuery.sizeOf(context).width - 40;
    final cardH = ((availW > 520 ? 520.0 : availW) / 1.75).clamp(168.0, 215.0).toDouble();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: cardH,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          boxShadow: [
            BoxShadow(
              color: colors.last.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: CardPatternPainter(style.pattern, fg)),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (emoji != null) ...[
                          Text(emoji, style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            bank.isEmpty ? 'Credit card' : bank,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w800),
                          ),
                        ),
                        Icon(Icons.contactless_rounded, color: fg),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      '••••  ••••  ••••  ${last4.isEmpty ? '••••' : last4}',
                      style: tt.titleLarge?.copyWith(
                        color: fg,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodyMedium?.copyWith(color: fgSoft),
                          ),
                        ),
                        if (due != null) _DuePill(due: due!, fg: fg),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DuePill extends StatelessWidget {
  const _DuePill({required this.due, required this.fg});

  final DueItem due;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        dueLabel(due.daysLeft),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class CardsPage extends StatefulWidget {
  const CardsPage({super.key});

  @override
  State<CardsPage> createState() => _CardsPageState();
}

class _CardsPageState extends State<CardsPage> {
  List<Map<String, dynamic>> _cards = [];
  List<DueItem> _due = [];
  double _outstanding = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final cards = List<Map<String, dynamic>>.from(
        await supabase.from('cards').select().eq('active', true).order('created_at'),
      );
      final stmts = List<Map<String, dynamic>>.from(
        await supabase.from('statements').select().eq('status', 'unpaid'),
      );
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _due = buildDueItems(cards, stmts);
        _outstanding = stmts.fold<double>(
          0.0,
          (s, x) => s + (x['total_due'] as num).toDouble(),
        );
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  DueItem? _dueFor(String cardId) {
    for (final d in _due) {
      if (d.cardId == cardId) return d;
    }
    return null;
  }

  Future<void> _openAdd() async {
    await Navigator.of(context).push(softRoute(const AddEditCardPage()));
    if (mounted) _load(silent: true);
  }

  Future<void> _openDetail(Map<String, dynamic> card, int index) async {
    await Navigator.of(context).push(softRoute(CardDetailPage(card: card, index: index)));
    if (mounted) _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final children = <Widget>[
      const PageHeader(title: 'Credit cards'),
      const SizedBox(height: 18),
    ];

    if (_loading) {
      children.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      ));
    } else if (_error != null) {
      children.add(GlassCard(child: Text('Error: $_error')));
    } else if (_cards.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primaryContainer),
              child: Icon(Icons.credit_card_rounded, size: 44, color: cs.primary),
            ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 16),
            Text('Wala ka pang card', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Ilagay ang mga credit card mo para hindi ka malate sa due date.',
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ));
    } else {
      final next = _due.isEmpty ? null : _due.first;
      children.add(
        GlassCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Kabuuang babayaran',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    CountUpText(
                      value: _outstanding,
                      format: peso,
                      style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              if (next != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Susunod na due',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    Text(
                      '${next.cardName} • ${dueLabel(next.daysLeft)}',
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: dueColor(next.daysLeft, cs),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ).animate().fadeIn().slideY(begin: 0.1),
      );
      children.add(const SizedBox(height: 16));
      for (var i = 0; i < _cards.length; i++) {
        final c = _cards[i];
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: CardVisual(
              card: c,
              index: i,
              due: _dueFor(c['id'] as String),
              onTap: () => _openDetail(c, i),
            ),
          ).animate().fadeIn(delay: (80 * i).ms).slideY(begin: 0.12),
        );
      }
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAdd,
        icon: const Icon(Icons.add_card_rounded),
        label: const Text('Add card'),
      ),
      body: AuroraBackground(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth(context, 560)),
              child: RefreshIndicator(
                onRefresh: () => _load(silent: true),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- ADD / EDIT CARD

class AddEditCardPage extends StatefulWidget {
  const AddEditCardPage({super.key, this.card, this.index = 0});

  final Map<String, dynamic>? card; // null = new card
  final int index; // position in the list (decides the automatic color)

  @override
  State<AddEditCardPage> createState() => _AddEditCardPageState();
}

class _AddEditCardPageState extends State<AddEditCardPage> {
  late final TextEditingController _nickname;
  late final TextEditingController _bank;
  late final TextEditingController _last4;
  late final TextEditingController _limit;
  late final TextEditingController _statementDay;
  late final TextEditingController _dueDay;
  late CardStyle _style;
  bool _saving = false;

  bool get _editing => widget.card != null;

  @override
  void initState() {
    super.initState();
    final c = widget.card;
    String s(String key) => (c?[key] ?? '').toString().trim();
    _nickname = TextEditingController(text: s('nickname'));
    _bank = TextEditingController(text: s('bank'));
    _last4 = TextEditingController(text: s('last4'));
    final lim = c?['credit_limit'];
    _limit = TextEditingController(text: lim == null ? '' : (lim as num).toStringAsFixed(0));
    _statementDay = TextEditingController(text: s('statement_day'));
    _dueDay = TextEditingController(text: s('due_day'));
    _style = CardStyle.fromJson(c?['style']);
  }

  int? _parseDay(String t) {
    if (t.trim().isEmpty) return null;
    final v = int.tryParse(t.trim());
    if (v == null || v < 1 || v > 31) return -1; // invalid marker
    return v;
  }

  Future<void> _save() async {
    final nickname = _nickname.text.trim();
    if (nickname.isEmpty) {
      showMsg(context, 'Lagyan ng pangalan ang card (hal. BDO Gold).', error: true);
      return;
    }
    final last4 = _last4.text.trim();
    if (last4.isNotEmpty && last4.length != 4) {
      showMsg(context, 'Last 4 digits lang ang ilagay (4 numbers).', error: true);
      return;
    }
    final stDay = _parseDay(_statementDay.text);
    final dueDay = _parseDay(_dueDay.text);
    if (stDay == -1 || dueDay == -1) {
      showMsg(context, 'Ang day ay dapat 1 hanggang 31.', error: true);
      return;
    }
    double? limit;
    if (_limit.text.trim().isNotEmpty) {
      limit = double.tryParse(_limit.text.replaceAll(',', '').trim());
      if (limit == null || limit < 0) {
        showMsg(context, 'Hindi valid ang credit limit.', error: true);
        return;
      }
    }

    final data = {
      'nickname': nickname,
      'bank': _bank.text.trim().isEmpty ? null : _bank.text.trim(),
      'last4': last4.isEmpty ? null : last4,
      'credit_limit': limit,
      'statement_day': stDay,
      'due_day': dueDay,
      'style': _style.isDefault ? null : _style.toJson(),
    };

    setState(() => _saving = true);
    try {
      if (_editing) {
        await supabase.from('cards').update(data).eq('id', widget.card!['id']);
      } else {
        await supabase.from('cards').insert(data);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    } catch (e) {
      if (mounted) showMsg(context, 'Hindi na-save: $e', error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  void dispose() {
    _nickname.dispose();
    _bank.dispose();
    _last4.dispose();
    _limit.dispose();
    _statementDay.dispose();
    _dueDay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth(context, 520)),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  PageHeader(title: _editing ? 'Edit card' : 'Add card'),
                  const SizedBox(height: 18),
                  GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.lock_rounded, color: cs.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Last 4 digits lang. Huwag ilagay ang buong card number, CVV, o PIN.',
                            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  ListenableBuilder(
                    listenable: Listenable.merge([_nickname, _bank, _last4]),
                    builder: (context, _) => CardVisual(
                      card: {
                        'nickname': _nickname.text.trim().isEmpty ? 'Card' : _nickname.text.trim(),
                        'bank': _bank.text.trim(),
                        'last4': _last4.text.trim(),
                        'style': _style.toJson(),
                      },
                      index: widget.index,
                    ),
                  ),
                  CardDesigner(
                    style: _style,
                    defaultColors: _cardGradients[widget.index % _cardGradients.length],
                    onChanged: (v) => setState(() => _style = v),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _nickname,
                    maxLength: 40,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Pangalan ng card',
                      hintText: 'e.g. BDO Gold',
                      counterText: '',
                      prefixIcon: Icon(Icons.credit_card_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _bank,
                    maxLength: 60,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Bank (optional)',
                      counterText: '',
                      prefixIcon: Icon(Icons.account_balance_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _last4,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Last 4 digits (optional)',
                      prefixIcon: Icon(Icons.pin_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _limit,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Credit limit (optional)',
                      prefixText: '₱ ',
                      prefixIcon: Icon(Icons.speed_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _statementDay,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Statement day',
                            helperText: 'Day of month (1-31)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _dueDay,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Due day',
                            helperText: 'Day of month (1-31)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: _editing ? 'Save changes' : 'Save card',
                    icon: Icons.check_rounded,
                    loading: _saving,
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

// ---------------------------------------------------------------- CARD DETAIL

class CardDetailPage extends StatefulWidget {
  const CardDetailPage({super.key, required this.card, required this.index});

  final Map<String, dynamic> card;
  final int index;

  @override
  State<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<CardDetailPage> {
  late Map<String, dynamic> _card = widget.card;
  List<Map<String, dynamic>> _stmts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final card = await supabase.from('cards').select().eq('id', _card['id']).single();
      final stmts = List<Map<String, dynamic>>.from(
        await supabase
            .from('statements')
            .select()
            .eq('card_id', _card['id'])
            .order('statement_date', ascending: false),
      );
      if (!mounted) return;
      setState(() {
        _card = card;
        _stmts = stmts;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _unpaid =>
      _stmts.where((s) => s['status'] == 'unpaid').toList();

  double get _outstanding => _unpaid.fold<double>(
        0.0,
        (s, x) => s + (x['total_due'] as num).toDouble(),
      );

  DueItem? get _due {
    final items = buildDueItems([_card], _unpaid);
    return items.isEmpty ? null : items.first;
  }

  Future<void> _edit() async {
    await Navigator.of(context).push(softRoute(AddEditCardPage(card: _card, index: widget.index)));
    if (mounted) _load(silent: true);
  }

  Future<void> _deleteCard() async {
    final ok = await _confirm(
      context,
      'I-delete ang card?',
      'Buburahin din ang lahat ng statements ng card na ito.',
      'Delete',
    );
    if (!ok) return;
    try {
      await supabase.from('cards').delete().eq('id', _card['id']);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showMsg(context, 'Hindi ma-delete: $e', error: true);
    }
  }

  Future<void> _addStatement() async {
    await Navigator.of(context).push(softRoute(AddStatementPage(card: _card)));
    if (mounted) _load(silent: true);
  }

  Future<void> _setPaid(Map<String, dynamic> s, bool paid) async {
    try {
      await supabase.from('statements').update({
        'status': paid ? 'paid' : 'unpaid',
        'paid_on': paid ? fmtDate(DateTime.now()) : null,
      }).eq('id', s['id']);
      if (!mounted) return;
      if (paid) showMsg(context, 'Na-mark na as paid ✅');
      _load(silent: true);
    } catch (e) {
      if (mounted) showMsg(context, 'Hindi na-update: $e', error: true);
    }
  }

  Future<void> _deleteStatement(Map<String, dynamic> s) async {
    final ok = await _confirm(
      context,
      'I-delete ang statement?',
      'Buburahin ang statement na ito.',
      'Delete',
    );
    if (!ok) return;
    try {
      await supabase.from('statements').delete().eq('id', s['id']);
      if (mounted) _load(silent: true);
    } catch (e) {
      if (mounted) showMsg(context, 'Hindi ma-delete: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final limit = (_card['credit_limit'] as num?)?.toDouble();

    final children = <Widget>[
      Row(
        children: [
          Expanded(child: PageHeader(title: (_card['nickname'] as String?) ?? 'Card')),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') _edit();
              if (v == 'delete') _deleteCard();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit card')),
              PopupMenuItem(value: 'delete', child: Text('Delete card')),
            ],
          ),
        ],
      ),
      const SizedBox(height: 16),
      CardVisual(card: _card, index: widget.index, due: _due)
          .animate()
          .fadeIn()
          .slideY(begin: 0.1),
      const SizedBox(height: 16),
    ];

    if (limit != null && limit > 0) {
      final pct = (_outstanding / limit).clamp(0.0, 1.0);
      children.add(
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Credit used',
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  Text(
                    '${peso(_outstanding)} / ${peso(limit)}',
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: pct),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, child) => LinearProgressIndicator(
                    value: v,
                    minHeight: 10,
                    color: pct > 0.8 ? cs.error : cs.primary,
                    backgroundColor: cs.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Base sa mga unpaid statements',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),
      );
      children.add(const SizedBox(height: 16));
    }

    children.add(
      Text('Statements', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
    );
    children.add(const SizedBox(height: 10));

    if (_loading) {
      children.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: CircularProgressIndicator()),
      ));
    } else if (_error != null) {
      children.add(GlassCard(child: Text('Error: $_error')));
    } else if (_stmts.isEmpty) {
      children.add(
        GlassCard(
          child: Text(
            'Wala pang statement. I-tap ang "Add statement" kapag dumating na ang SOA mo.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    } else {
      for (var i = 0; i < _stmts.length; i++) {
        children.add(_stmtTile(cs, tt, _stmts[i], i));
      }
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStatement,
        icon: const Icon(Icons.receipt_long_rounded),
        label: const Text('Add statement'),
      ),
      body: AuroraBackground(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth(context, 560)),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stmtTile(ColorScheme cs, TextTheme tt, Map<String, dynamic> s, int i) {
    final paid = s['status'] == 'paid';
    final due = DateTime.parse(s['due_date'] as String);
    final days = due.difference(_dateOnly(DateTime.now())).inDays;
    final total = (s['total_due'] as num).toDouble();
    final minDue = (s['min_due'] as num).toDouble();
    final color = paid ? cs.primary : dueColor(days, cs);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Statement ${s['statement_date']}',
                          style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                      Text('Due ${s['due_date']}',
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                Text(peso(total),
                    style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            if (minDue > 0) ...[
              const SizedBox(height: 4),
              Text('Minimum: ${peso(minDue)}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    paid ? 'Paid ${s['paid_on'] ?? ''}'.trim() : dueLabel(days),
                    style: tt.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w800),
                  ),
                ),
                const Spacer(),
                if (!paid)
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                    onPressed: () => _setPaid(s, true),
                    child: const Text('Mark paid'),
                  )
                else
                  TextButton(
                    onPressed: () => _setPaid(s, false),
                    child: const Text('Undo'),
                  ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: () => _deleteStatement(s),
                  icon: Icon(Icons.delete_outline_rounded, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ).animate().fadeIn(delay: (50 * (i > 8 ? 8 : i)).ms).slideY(begin: 0.08),
    );
  }
}

// ---------------------------------------------------------------- ADD STATEMENT

class AddStatementPage extends StatefulWidget {
  const AddStatementPage({super.key, required this.card});

  final Map<String, dynamic> card;

  @override
  State<AddStatementPage> createState() => _AddStatementPageState();
}

class _AddStatementPageState extends State<AddStatementPage> {
  final _total = TextEditingController();
  final _min = TextEditingController();
  late DateTime _stmtDate;
  late DateTime _dueDate;
  bool _dueTouched = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _stmtDate = _dateOnly(DateTime.now());
    _dueDate = _suggestDue();
  }

  DateTime _suggestDue() {
    final dd = widget.card['due_day'];
    if (dd is int) return nextDueDate(dd, _stmtDate);
    return _stmtDate.add(const Duration(days: 21));
  }

  Future<void> _pickStatement() async {
    final p = await _pickDate(context, _stmtDate);
    if (p == null) return;
    setState(() {
      _stmtDate = _dateOnly(p);
      if (!_dueTouched) _dueDate = _suggestDue();
    });
  }

  Future<void> _pickDue() async {
    final p = await _pickDate(context, _dueDate);
    if (p == null) return;
    setState(() {
      _dueDate = _dateOnly(p);
      _dueTouched = true;
    });
  }

  Future<void> _importSoa() async {
    final name = (widget.card['nickname'] as String?) ?? 'Card';
    final r = await Navigator.of(context).push<SoaResult>(
      softRoute<SoaResult>(SoaImportPage(cardName: name)),
    );
    if (r == null || !mounted) return;
    setState(() {
      if (r.totalDue != null) _total.text = r.totalDue!.toStringAsFixed(2);
      if (r.minDue != null) _min.text = r.minDue!.toStringAsFixed(2);
      if (r.statementDate != null) {
        _stmtDate = _dateOnly(r.statementDate!);
        if (!_dueTouched) _dueDate = _suggestDue();
      }
      if (r.dueDate != null) {
        _dueDate = _dateOnly(r.dueDate!);
        _dueTouched = true;
      }
    });
    showMsg(context, 'Napunan na ang form. I-check ang numbers bago i-save.');
  }

  Future<void> _save() async {
    final total = double.tryParse(_total.text.replaceAll(',', '').trim());
    if (total == null || total < 0) {
      showMsg(context, 'Ilagay ang total amount due.', error: true);
      return;
    }
    final minText = _min.text.replaceAll(',', '').trim();
    final minDue = minText.isEmpty ? 0.0 : double.tryParse(minText);
    if (minDue == null || minDue < 0) {
      showMsg(context, 'Hindi valid ang minimum due.', error: true);
      return;
    }
    if (minDue > total) {
      showMsg(context, 'Hindi puwedeng mas malaki ang minimum kaysa sa total.', error: true);
      return;
    }
    if (_dueDate.isBefore(_stmtDate)) {
      showMsg(context, 'Dapat nasa/after ng statement date ang due date.', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      await supabase.from('statements').insert({
        'card_id': widget.card['id'],
        'statement_date': fmtDate(_stmtDate),
        'due_date': fmtDate(_dueDate),
        'total_due': total,
        'min_due': minDue,
        'status': 'unpaid',
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    } catch (e) {
      final msg = e.toString().toLowerCase().contains('duplicate')
          ? 'May statement na para sa statement date na yan.'
          : 'Hindi na-save: $e';
      if (mounted) showMsg(context, msg, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  void dispose() {
    _total.dispose();
    _min.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final name = (widget.card['nickname'] as String?) ?? 'Card';

    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth(context, 520)),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  const PageHeader(title: 'Add statement'),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 56),
                    child: Text(name, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _importSoa,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('Upload SOA (PDF) — auto-fill'),
                  ),
                  const SizedBox(height: 14),
                  GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: TextField(
                      controller: _total,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: tt.displaySmall?.copyWith(fontWeight: FontWeight.w800),
                      decoration: InputDecoration(
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: '0.00',
                        labelText: 'Total amount due',
                        floatingLabelAlignment: FloatingLabelAlignment.center,
                        prefixText: '₱ ',
                        prefixStyle: tt.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _min,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Minimum amount due (optional)',
                      prefixText: '₱ ',
                      prefixIcon: Icon(Icons.south_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _DateRow(
                    icon: Icons.receipt_long_rounded,
                    label: 'Statement date',
                    value: fmtDate(_stmtDate),
                    onTap: _pickStatement,
                  ),
                  const SizedBox(height: 10),
                  _DateRow(
                    icon: Icons.event_rounded,
                    label: 'Due date',
                    value: fmtDate(_dueDate),
                    onTap: _pickDue,
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: 'Save statement',
                    icon: Icons.check_rounded,
                    loading: _saving,
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

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: tt.bodyMedium)),
            Text(value, style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            Icon(Icons.edit_calendar_rounded, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
