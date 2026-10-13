// Wais Wallet - home: balance card, category breakdown, transaction list

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'add_transaction_page.dart';
import 'budgets_logic.dart';
import 'budgets_page.dart';
import 'cards_logic.dart';
import 'cards_page.dart';
import 'core.dart';
import 'recurring_logic.dart';
import 'recurring_page.dart';
import 'settings_page.dart';
import 'widgets.dart';

class _CatTotal {
  _CatTotal(this.name, this.icon, this.total);

  final String name;
  final String icon;
  final double total;

  _CatTotal add(double x) => _CatTotal(name, icon, total + x);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Map<String, dynamic>> _items = [];
  List<DueItem> _due = [];
  bool _loading = true;
  String? _error;
  String _tab = 'expense'; // 'expense' or 'income'
  bool _showBreakdown = false;
  List<Budget> _budgets = [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadDue();
    _runRecurring();
    _loadBudgets();
  }

  Future<void> _loadDue() async {
    try {
      final items = await loadDueItems();
      if (!mounted) return;
      setState(() => _due = items);
    } catch (_) {
      // Due reminders are optional; never break the home screen.
    }
  }

  /// Logs any recurring transactions that are due (silent if none).
  Future<void> _runRecurring() async {
    try {
      final n = await generateDueRecurring();
      if (n > 0 && mounted) {
        showMsg(context, 'Na-log ang $n recurring na transaction 🔁');
        await _load(silent: true);
      }
    } catch (_) {
      // optional feature; never break the home screen
    }
  }

  Future<void> _loadBudgets() async {
    try {
      final b = await loadBudgets();
      if (!mounted) return;
      setState(() => _budgets = b);
    } catch (_) {
      // budgets table may not exist yet; just hide the budget card
    }
  }

  Future<void> _openBudgets() async {
    await Navigator.of(context).push(softRoute(const BudgetsPage()));
    if (mounted) _loadBudgets();
  }

  Future<void> _openRecurring() async {
    await Navigator.of(context).push(softRoute(const RecurringPage()));
    if (!mounted) return;
    await _runRecurring();
    _load(silent: true);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(softRoute(const SettingsPage()));
    if (!mounted) return;
    await _runRecurring();
    _load(silent: true);
  }

  Future<void> _openCards() async {
    await Navigator.of(context).push(softRoute(const CardsPage()));
    if (mounted) _loadDue();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final next = DateTime(_month.year, _month.month + 1);
      final data = await supabase
          .from('transactions')
          .select('*, categories(name, icon)')
          .gte('occurred_on', fmtDate(_month))
          .lt('occurred_on', fmtDate(next))
          .order('occurred_on', ascending: false)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(data);
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

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  double _sum(String type) => _items
      .where((t) => t['type'] == type)
      .fold(0.0, (s, t) => s + (t['amount'] as num).toDouble());

  List<_CatTotal> _byCategory(String type) {
    final map = <String, _CatTotal>{};
    for (final t in _items) {
      if (t['type'] != type) continue;
      final cat = t['categories'] as Map?;
      final name = (cat?['name'] as String?) ?? 'Uncategorized';
      final icon = (cat?['icon'] as String?) ?? (type == 'income' ? '💰' : '💸');
      final amt = (t['amount'] as num).toDouble();
      map.update(name, (v) => v.add(amt), ifAbsent: () => _CatTotal(name, icon, amt));
    }
    final list = map.values.toList()..sort((a, b) => b.total.compareTo(a.total));
    return list;
  }

  Future<void> _openAdd() async {
    final saved = await Navigator.of(context).push<bool>(
      softRoute<bool>(AddTransactionPage(initialType: _tab)),
    );
    if (saved == true) _load(silent: true);
  }

  Future<void> _openEdit(Map<String, dynamic> t) async {
    final changed = await Navigator.of(context).push<bool>(
      softRoute<bool>(AddTransactionPage(transaction: t)),
    );
    if (changed == true) _load(silent: true);
  }

  Future<bool> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('I-delete ito?'),
        content: const Text('Buburahin ang transaction na ito.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _delete(Map<String, dynamic> t) async {
    setState(() => _items.removeWhere((x) => x['id'] == t['id']));
    try {
      await supabase.from('transactions').delete().eq('id', t['id']);
    } catch (e) {
      if (!mounted) return;
      showMsg(context, 'Hindi ma-delete: $e', error: true);
      _load(silent: true);
    }
  }

  String _firstName() {
    final u = supabase.auth.currentUser;
    final n = (u?.userMetadata?['display_name'] as String?)?.trim();
    if (n != null && n.isNotEmpty) return n.split(' ').first;
    final email = u?.email ?? '';
    return email.contains('@') ? email.split('@').first : 'friend';
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Magandang umaga';
    if (h < 18) return 'Magandang hapon';
    return 'Magandang gabi';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final pad = pagePad(context);
    final income = _sum('income');
    final expense = _sum('expense');
    final tabItems = _items.where((t) => t['type'] == _tab).toList();
    final tabTotal = _tab == 'expense' ? expense : income;
    final cats = _byCategory(_tab);

    final children = <Widget>[
      _header(cs, tt),
      const SizedBox(height: 18),
      _monthPicker(tt),
      const SizedBox(height: 14),
      _balanceCard(cs, tt, income, expense),
      if (_due.isNotEmpty) ...[
        const SizedBox(height: 16),
        _dueCard(cs, tt),
      ],
      const SizedBox(height: 20),
      _tabBar(),
      const SizedBox(height: 12),
      _summaryCard(cs, tt, tabTotal, tabItems.length, cats),
      if (_tab == 'expense' && _budgets.isNotEmpty) ...[
        const SizedBox(height: 12),
        _budgetCard(cs, tt),
      ],
      const SizedBox(height: 16),
      ..._listWidgets(cs, tt, tabItems),
    ];

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAdd,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ).animate().scale(delay: 500.ms, duration: 400.ms, curve: Curves.easeOutBack),
      body: AuroraBackground(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth(context, 640)),
              child: RefreshIndicator(
                onRefresh: () async {
                  await _runRecurring();
                  await _load(silent: true);
                  await _loadDue();
                  await _loadBudgets();
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(pad, 12, pad, 110),
                      sliver: SliverList(delegate: SliverChildListDelegate(children)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs, TextTheme tt) {
    final name = _firstName();
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [cs.primary, cs.secondary]),
          ),
          child: Text(
            name.isEmpty ? '?' : name[0].toUpperCase(),
            style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w800, fontSize: 18),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_greeting(), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Credit cards',
          onPressed: _openCards,
          icon: const Icon(Icons.credit_card_rounded),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Settings',
          onPressed: _openSettings,
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    ).animate().fadeIn().slideY(begin: -0.2);
  }

  Widget _monthPicker(TextTheme tt) {
    final label = '${monthNames[_month.month - 1]} ${_month.year}';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: () => _changeMonth(-1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
          child: Text(
            label,
            key: ValueKey(label),
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          onPressed: () => _changeMonth(1),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  Widget _balanceCard(ColorScheme cs, TextTheme tt, double income, double expense) {
    final on = cs.onPrimary;
    return Container(
      padding: EdgeInsets.all(isNarrow(context) ? 16 : 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary, Color.lerp(cs.primary, cs.secondary, 0.6)!],
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.35),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Balance ngayong buwan',
            style: tt.bodyMedium?.copyWith(color: on.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 6),
          CountUpText(
            value: income - expense,
            format: peso,
            style: tt.headlineLarge?.copyWith(color: on, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  icon: Icons.south_west_rounded,
                  label: 'Income',
                  value: income,
                  color: on,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStat(
                  icon: Icons.north_east_rounded,
                  label: 'Expenses',
                  value: expense,
                  color: on,
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1);
  }

  Widget _dueCard(ColorScheme cs, TextTheme tt) {
    final top = _due.take(3).toList();
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_rounded, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Due soon',
                    style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
              TextButton(onPressed: _openCards, child: const Text('Cards')),
            ],
          ),
          for (final d in top)
            GestureDetector(
              onTap: _openCards,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: dueColor(d.daysLeft, cs).withValues(alpha: 0.14),
                      ),
                      child: Icon(Icons.credit_card_rounded,
                          color: dueColor(d.daysLeft, cs), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.last4 == null || d.last4!.isEmpty
                                ? d.cardName
                                : '${d.cardName} •••• ${d.last4}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${dueLabel(d.daysLeft)} • ${fmtDate(d.dueDate)}',
                            style: tt.bodySmall?.copyWith(
                              color: dueColor(d.daysLeft, cs),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (d.amount != null)
                      Text(peso(d.amount!),
                          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
        ],
      ),
    ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.1);
  }

  Widget _budgetCard(ColorScheme cs, TextTheme tt) {
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;
    final spent = spentByCategory(_items);
    final total = totalExpenseOf(_items);

    // overall first, then the closest to the limit
    final rows = <({String icon, String name, double spent, double limit})>[];
    for (final b in _budgets) {
      if (b.categoryId == null) {
        rows.add((icon: '🎯', name: 'Overall', spent: total, limit: b.amount));
      } else {
        String name = 'Category';
        String icon = '💸';
        for (final t in _items) {
          if (t['category_id'] == b.categoryId) {
            final cat = t['categories'] as Map?;
            name = (cat?['name'] as String?) ?? name;
            icon = (cat?['icon'] as String?) ?? icon;
            break;
          }
        }
        rows.add((icon: icon, name: name, spent: spent[b.categoryId] ?? 0, limit: b.amount));
      }
    }
    double pctOf(({String icon, String name, double spent, double limit}) r) =>
        r.limit <= 0 ? 0 : r.spent / r.limit;
    rows.sort((a, b) {
      if (a.name == 'Overall') return -1;
      if (b.name == 'Overall') return 1;
      return pctOf(b).compareTo(pctOf(a));
    });
    final shown = rows.take(4).toList();
    final safe = isCurrent ? safeToSpendPerDay(_budgets, spent, total, now) : null;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.savings_outlined, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Budget',
                    style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
              TextButton(onPressed: _openBudgets, child: const Text('Lahat')),
            ],
          ),
          if (safe != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: (safe <= 0 ? cs.error : cs.primary).withValues(alpha: 0.12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Safe to spend ngayon',
                    style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      safe <= 0 ? 'Wala nang natitira' : '${peso(safe)} / araw',
                      maxLines: 1,
                      style: tt.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: safe <= 0 ? cs.error : cs.primary,
                      ),
                    ),
                  ),
                  Text(
                    '${daysLeftInMonth(now)} araw pa ang natitira ngayong buwan',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (final r in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(r.icon, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(pctOf(r) * 100).round()}%',
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: budgetColor(pctOf(r), cs),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: pctOf(r).clamp(0.0, 1.0).toDouble(),
                      minHeight: 8,
                      color: budgetColor(pctOf(r), cs),
                      backgroundColor: cs.outlineVariant.withValues(alpha: 0.45),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${peso(r.spent)} / ${peso(r.limit)}',
                        maxLines: 1,
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    return SegmentedButton<String>(
      expandedInsets: EdgeInsets.zero,
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: 'expense',
          label: Text('Expenses'),
          icon: Icon(Icons.north_east_rounded),
        ),
        ButtonSegment(
          value: 'income',
          label: Text('Income'),
          icon: Icon(Icons.south_west_rounded),
        ),
      ],
      selected: {_tab},
      onSelectionChanged: (s) => setState(() {
        _tab = s.first;
        _showBreakdown = false;
      }),
    );
  }

  Widget _summaryCard(
    ColorScheme cs,
    TextTheme tt,
    double total,
    int count,
    List<_CatTotal> cats,
  ) {
    final isExp = _tab == 'expense';
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: cs.primary.withValues(alpha: 0.12),
                ),
                child: Icon(
                  isExp ? Icons.north_east_rounded : Icons.south_west_rounded,
                  color: cs.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isExp ? 'Total expenses' : 'Total income',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    CountUpText(
                      value: total,
                      format: peso,
                      style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: Text(
                  '$count ${count == 1 ? 'transaction' : 'transactions'}',
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (cats.isNotEmpty)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => setState(() => _showBreakdown = !_showBreakdown),
                  icon: Icon(
                    _showBreakdown ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  ),
                  label: Text(isExp ? 'Saan napunta' : 'Saan galing'),
                ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _openRecurring,
                icon: const Icon(Icons.autorenew_rounded),
                label: const Text('Recurring'),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _openBudgets,
                icon: const Icon(Icons.savings_outlined),
                label: const Text('Budgets'),
              ),
            ],
          ),
          if (cats.isNotEmpty) ...[
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _showBreakdown
                  ? _breakdownRows(cs, tt, cats, total)
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ],
      ),
    );
  }

  Widget _breakdownRows(ColorScheme cs, TextTheme tt, List<_CatTotal> cats, double total) {
    final top = cats.take(5).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: [
          for (final c in top)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(c.icon, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(peso(c.total), style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Text(
                        '${total == 0 ? 0 : (c.total / total * 100).round()}%',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: 0.0,
                        end: total == 0 ? 0.0 : c.total / total,
                      ),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, child) => LinearProgressIndicator(
                        value: v,
                        minHeight: 8,
                        color: cs.primary,
                        backgroundColor: cs.outlineVariant.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _listWidgets(ColorScheme cs, TextTheme tt, List<Map<String, dynamic>> items) {
    if (_loading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_error != null) {
      return [GlassCard(child: Text('Error: $_error'))];
    }
    final isExp = _tab == 'expense';
    if (items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 36),
          child: Column(
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primaryContainer),
                child: Icon(
                  isExp ? Icons.receipt_long_rounded : Icons.savings_rounded,
                  size: 42,
                  color: cs.primary,
                ),
              ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
              const SizedBox(height: 14),
              Text(
                isExp ? 'Wala pang expense ngayong buwan' : 'Wala pang income ngayong buwan',
                textAlign: TextAlign.center,
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                isExp
                    ? 'Tap "Add" para i-log ang gastos mo.'
                    : 'Tap "Add" para i-log ang kita mo.',
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          'Pinakabago muna',
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      for (var i = 0; i < items.length; i++) _tile(cs, tt, items[i], i),
    ];
  }

  Widget _tile(ColorScheme cs, TextTheme tt, Map<String, dynamic> t, int i) {
    final cat = t['categories'] as Map?;
    final catName = (cat?['name'] as String?) ?? 'Uncategorized';
    final icon = (cat?['icon'] as String?) ?? '💸';
    final isExpense = t['type'] == 'expense';
    final merchant = ((t['merchant'] as String?) ?? '').trim();
    final amount = (t['amount'] as num).toDouble();
    final color = isExpense ? cs.error : cs.primary;
    final isLatest = i == 0;
    final maxAmountW = MediaQuery.sizeOf(context).width * 0.36;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Dismissible(
          key: ValueKey('tx-${t['id']}'),
          direction: DismissDirection.endToStart,
          confirmDismiss: (direction) => _confirmDelete(),
          onDismissed: (direction) => _delete(t),
          background: Container(
            color: cs.error,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: Icon(Icons.delete_rounded, color: cs.onError),
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openEdit(t),
            child: GlassCard(
              radius: 22,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: cs.primary.withValues(alpha: 0.12),
                    ),
                    child: Text(icon, style: const TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                merchant.isEmpty ? catName : merchant,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (isLatest) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: cs.primaryContainer,
                                ),
                                child: Text(
                                  'Pinakabago',
                                  maxLines: 1,
                                  style: tt.labelSmall?.copyWith(
                                    color: cs.onPrimaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          '${t['occurred_on']} • $catName${t['source'] == 'recurring' ? ' • 🔁' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxAmountW),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${isExpense ? '-' : '+'}${peso(amount)}',
                        maxLines: 1,
                        style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w800, color: color),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).animate().fadeIn(delay: (30 * math.min(i, 12)).ms).slideX(begin: 0.05);
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: color.withValues(alpha: 0.14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: tt.labelSmall?.copyWith(color: color.withValues(alpha: 0.8))),
                CountUpText(
                  value: value,
                  format: peso,
                  style: tt.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
