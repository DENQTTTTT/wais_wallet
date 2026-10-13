// Wais Wallet - budgets: list, set limit per category (or overall), edit, delete

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'budgets_logic.dart';
import 'core.dart';
import 'widgets.dart';

class BudgetsPage extends StatefulWidget {
  const BudgetsPage({super.key});

  @override
  State<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends State<BudgetsPage> {
  List<Budget> _budgets = [];
  final Map<String, Map<String, dynamic>> _cats = {};
  Map<String, double> _spent = {};
  double _total = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month);
      final next = DateTime(now.year, now.month + 1);
      final cats = await supabase.from('categories').select();
      final budgets = await loadBudgets();
      final tx = await supabase
          .from('transactions')
          .select('category_id, amount, type')
          .gte('occurred_on', fmtDate(start))
          .lt('occurred_on', fmtDate(next));
      final items = List<Map<String, dynamic>>.from(tx);
      if (!mounted) return;
      setState(() {
        _cats
          ..clear()
          ..addEntries([
            for (final c in cats)
              MapEntry(c['id'] as String, Map<String, dynamic>.from(c)),
          ]);
        _budgets = budgets
          ..sort((a, b) {
            if (a.categoryId == null) return -1;
            if (b.categoryId == null) return 1;
            return ((_cats[a.categoryId]?['name'] as String?) ?? '')
                .compareTo((_cats[b.categoryId]?['name'] as String?) ?? '');
          });
        _spent = spentByCategory(items);
        _total = totalExpenseOf(items);
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

  Future<void> _openEdit([Budget? b]) async {
    final saved = await Navigator.of(context).push<bool>(
      softRoute<bool>(BudgetEditPage(budget: b, existing: _budgets)),
    );
    if (saved == true) _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final pad = pagePad(context);
    final now = DateTime.now();

    final children = <Widget>[
      const PageHeader(title: 'Budgets'),
      const SizedBox(height: 8),
      Text(
        'Monthly limit para sa ${monthNames[now.month - 1]} at susunod pang buwan. Mag-wa-warning sa 80% at 100%.',
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      const SizedBox(height: 16),
    ];

    if (_loading) {
      children.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      ));
    } else if (_error != null) {
      children.add(GlassCard(
        child: Text(
          'Hindi ma-load ang budgets. Na-run mo na ba ang SQL para sa budgets table?\n\n$_error',
        ),
      ));
    } else if (_budgets.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primaryContainer),
              child: Icon(Icons.savings_rounded, size: 42, color: cs.primary),
            ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 14),
            Text('Wala ka pang budget',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Maglagay ng limit sa Food, Transport, atbp. para alam mo kung hanggang saan ka lang.',
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ));
    } else {
      for (var i = 0; i < _budgets.length; i++) {
        children.add(_tile(cs, tt, _budgets[i], i));
      }
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
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
                  padding: EdgeInsets.fromLTRB(pad, 12, pad, 110),
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(ColorScheme cs, TextTheme tt, Budget b, int i) {
    final isOverall = b.categoryId == null;
    final cat = isOverall ? null : _cats[b.categoryId];
    final name = isOverall ? 'Overall (lahat ng gastos)' : ((cat?['name'] as String?) ?? 'Category');
    final icon = isOverall ? '🎯' : ((cat?['icon'] as String?) ?? '💸');
    final spent = isOverall ? _total : (_spent[b.categoryId] ?? 0);
    final pct = b.amount <= 0 ? 0.0 : spent / b.amount;
    final color = budgetColor(pct, cs);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openEdit(b),
        child: GlassCard(
          radius: 22,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            children: [
              Row(
                children: [
                  Text(icon, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(pct * 100).round()}%',
                    style: tt.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: pct.clamp(0.0, 1.0).toDouble(),
                  minHeight: 8,
                  color: color,
                  backgroundColor: cs.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${peso(spent)} / ${peso(b.amount)}',
                    maxLines: 1,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
        ),
      ).animate().fadeIn(delay: (30 * (i > 12 ? 12 : i)).ms).slideX(begin: 0.05),
    );
  }
}

// ---------------------------------------------------------------------------

class BudgetEditPage extends StatefulWidget {
  const BudgetEditPage({super.key, this.budget, required this.existing});

  /// null = add, otherwise edit this one (category is locked when editing).
  final Budget? budget;
  final List<Budget> existing;

  @override
  State<BudgetEditPage> createState() => _BudgetEditPageState();
}

class _BudgetEditPageState extends State<BudgetEditPage> {
  final _amount = TextEditingController();
  List<Map<String, dynamic>> _categories = [];
  String? _categoryId;
  bool _overall = false;
  bool _saving = false;
  bool _deleting = false;

  bool get _isEdit => widget.budget != null;

  @override
  void initState() {
    super.initState();
    final b = widget.budget;
    if (b != null) {
      _categoryId = b.categoryId;
      _overall = b.categoryId == null;
      _amount.text = b.amount == b.amount.roundToDouble()
          ? b.amount.toStringAsFixed(0)
          : b.amount.toStringAsFixed(2);
    }
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await supabase
          .from('categories')
          .select()
          .eq('type', 'expense')
          .order('name');
      if (!mounted) return;
      setState(() => _categories = List<Map<String, dynamic>>.from(cats));
    } catch (e) {
      if (!mounted) return;
      showMsg(context, 'Hindi ma-load ang categories: $e', error: true);
    }
  }

  String _lockedName() {
    if (_overall) return '🎯 Overall (lahat ng gastos)';
    for (final c in _categories) {
      if (c['id'] == _categoryId) return '${c['icon'] ?? ''} ${c['name']}'.trim();
    }
    return 'Category';
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (amount == null || amount <= 0) {
      showMsg(context, 'Maglagay ng valid na limit.', error: true);
      return;
    }
    if (amount > 1000000000) {
      showMsg(context, 'Masyadong malaki ang amount.', error: true);
      return;
    }
    if (!_overall && _categoryId == null) {
      showMsg(context, 'Pumili ng category o Overall.', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final target = _overall ? null : _categoryId;
      Budget? current = widget.budget;
      if (current == null) {
        for (final b in widget.existing) {
          if (b.categoryId == target) current = b; // already has one: update it
        }
      }
      if (current != null) {
        await supabase.from('budgets').update({'amount': amount}).eq('id', current.id);
      } else {
        await supabase.from('budgets').insert({
          'category_id': target,
          'amount': amount,
        });
      }
    } catch (e) {
      if (!mounted) return;
      showMsg(context, 'Hindi na-save: $e', error: true);
      setState(() => _saving = false);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('I-delete ang budget?'),
        content: const Text('Buburahin ang limit na ito. Hindi ginagalaw ang mga transaction mo.'),
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
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await supabase.from('budgets').delete().eq('id', widget.budget!.id);
    } catch (e) {
      if (!mounted) return;
      showMsg(context, 'Hindi ma-delete: $e', error: true);
      setState(() => _deleting = false);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final pad = pagePad(context);
    final amountStyle = isNarrow(context) ? tt.headlineLarge : tt.displaySmall;

    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth(context, 560)),
              child: ListView(
                padding: EdgeInsets.fromLTRB(pad, 12, pad, 32),
                children: [
                  PageHeader(title: _isEdit ? 'Edit budget' : 'Add budget'),
                  const SizedBox(height: 18),
                  Text('Para saan?', style: tt.labelLarge),
                  const SizedBox(height: 8),
                  if (_isEdit)
                    GlassCard(child: Text(_lockedName(), style: tt.bodyLarge))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('🎯 Overall'),
                          selected: _overall,
                          onSelected: (_) => setState(() {
                            _overall = true;
                            _categoryId = null;
                          }),
                        ),
                        for (final c in _categories)
                          ChoiceChip(
                            label: Text('${c['icon'] ?? ''} ${c['name']}'),
                            selected: !_overall && _categoryId == c['id'],
                            onSelected: (_) => setState(() {
                              _overall = false;
                              _categoryId = c['id'] as String;
                            }),
                          ),
                      ],
                    ),
                  const SizedBox(height: 18),
                  Text('Monthly limit', style: tt.labelLarge),
                  const SizedBox(height: 8),
                  GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: TextField(
                      controller: _amount,
                      autofocus: !_isEdit,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: amountStyle?.copyWith(fontWeight: FontWeight.w800),
                      decoration: InputDecoration(
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: '0.00',
                        prefixText: '₱ ',
                        prefixStyle: amountStyle?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pareho ang limit kada buwan. Kapag may budget na ang napili mo, ia-update lang ito.',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: _isEdit ? 'Save changes' : 'Save',
                    icon: Icons.check_rounded,
                    loading: _saving,
                    onPressed: _save,
                  ),
                  if (_isEdit) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        onPressed: (_saving || _deleting) ? null : _delete,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('I-delete ang budget'),
                        style: TextButton.styleFrom(foregroundColor: cs.error),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
