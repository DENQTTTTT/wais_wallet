// Wais Wallet - manage recurring transactions (sahod, rent, subscriptions...)

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'core.dart';
import 'recurring_logic.dart';
import 'widgets.dart';

class RecurringPage extends StatefulWidget {
  const RecurringPage({super.key});

  @override
  State<RecurringPage> createState() => _RecurringPageState();
}

class _RecurringPageState extends State<RecurringPage> {
  List<Map<String, dynamic>> _rules = [];
  final Map<String, Map<String, dynamic>> _cats = {};
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
      final cats = await supabase.from('categories').select();
      final rules = await supabase
          .from('recurring_transactions')
          .select()
          .order('day_of_month');
      if (!mounted) return;
      setState(() {
        _cats
          ..clear()
          ..addEntries([
            for (final c in cats) MapEntry(c['id'] as String, Map<String, dynamic>.from(c)),
          ]);
        _rules = List<Map<String, dynamic>>.from(rules);
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

  Future<void> _openEdit([Map<String, dynamic>? rule]) async {
    final saved = await Navigator.of(context).push<bool>(
      softRoute<bool>(RecurringEditPage(rule: rule)),
    );
    if (saved == true) _load(silent: true);
  }

  Future<void> _toggle(Map<String, dynamic> r, bool v) async {
    setState(() => r['active'] = v);
    try {
      await supabase
          .from('recurring_transactions')
          .update({'active': v})
          .eq('id', r['id']);
    } catch (e) {
      if (!mounted) return;
      showMsg(context, 'Hindi ma-update: $e', error: true);
      _load(silent: true);
    }
  }

  Future<bool> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('I-delete ito?'),
        content: const Text(
          'Titigil na ang auto-log nito. Hindi buburahin ang mga transaction na na-log na.',
        ),
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

  Future<void> _delete(Map<String, dynamic> r) async {
    setState(() => _rules.removeWhere((x) => x['id'] == r['id']));
    try {
      await supabase.from('recurring_transactions').delete().eq('id', r['id']);
    } catch (e) {
      if (!mounted) return;
      showMsg(context, 'Hindi ma-delete: $e', error: true);
      _load(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final pad = pagePad(context);

    final children = <Widget>[
      const PageHeader(title: 'Recurring'),
      const SizedBox(height: 8),
      Text(
        'Awtomatikong ma-lo-log kapag binuksan mo ang app. Ang petsa ay ang araw na naka-schedule.',
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
      children.add(GlassCard(child: Text('Error: $_error')));
    } else if (_rules.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primaryContainer),
              child: Icon(Icons.autorenew_rounded, size: 42, color: cs.primary),
            ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 14),
            Text('Wala pang recurring',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Ilagay ang sahod, rent, Netflix, load at iba pa para hindi mo na ie-encode.',
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ));
    } else {
      for (var i = 0; i < _rules.length; i++) {
        children.add(_tile(cs, tt, _rules[i], i));
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

  Widget _tile(ColorScheme cs, TextTheme tt, Map<String, dynamic> r, int i) {
    final cat = _cats[r['category_id']];
    final catName = (cat?['name'] as String?) ?? 'Uncategorized';
    final icon = (cat?['icon'] as String?) ?? '🔁';
    final isExpense = r['type'] == 'expense';
    final merchant = ((r['merchant'] as String?) ?? '').trim();
    final amount = (r['amount'] as num).toDouble();
    final active = r['active'] == true;
    final color = isExpense ? cs.error : cs.primary;
    final maxAmountW = MediaQuery.sizeOf(context).width * 0.3;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Dismissible(
          key: ValueKey('rec-${r['id']}'),
          direction: DismissDirection.endToStart,
          confirmDismiss: (d) => _confirmDelete(),
          onDismissed: (d) => _delete(r),
          background: Container(
            color: cs.error,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: Icon(Icons.delete_rounded, color: cs.onError),
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openEdit(r),
            child: Opacity(
              opacity: active ? 1 : 0.55,
              child: GlassCard(
                radius: 22,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                          Text(
                            merchant.isEmpty ? catName : merchant,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            'Bawat ika-${r['day_of_month']} • $catName',
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
                          style: tt.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      ),
                    ),
                    Switch(value: active, onChanged: (v) => _toggle(r, v)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ).animate().fadeIn(delay: (30 * (i > 12 ? 12 : i)).ms).slideX(begin: 0.05);
  }
}

// ---------------------------------------------------------------------------

class RecurringEditPage extends StatefulWidget {
  const RecurringEditPage({super.key, this.rule});

  /// null = add a new recurring, otherwise edit this row.
  final Map<String, dynamic>? rule;

  @override
  State<RecurringEditPage> createState() => _RecurringEditPageState();
}

class _RecurringEditPageState extends State<RecurringEditPage> {
  final _amount = TextEditingController();
  final _merchant = TextEditingController();
  String _type = 'expense';
  String? _categoryId;
  int _day = DateTime.now().day;
  bool _logThisMonth = false;
  bool _saving = false;
  bool _deleting = false;
  List<Map<String, dynamic>> _categories = [];

  bool get _isEdit => widget.rule != null;

  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    if (r != null) {
      _type = (r['type'] as String?) ?? 'expense';
      final a = (r['amount'] as num).toDouble();
      _amount.text = a == a.roundToDouble() ? a.toStringAsFixed(0) : a.toStringAsFixed(2);
      _merchant.text = (r['merchant'] as String?) ?? '';
      _categoryId = r['category_id'] as String?;
      _day = (r['day_of_month'] as num).toInt().clamp(1, 31);
    }
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await supabase.from('categories').select().order('name');
      if (!mounted) return;
      setState(() => _categories = List<Map<String, dynamic>>.from(cats));
    } catch (e) {
      if (!mounted) return;
      showMsg(context, 'Hindi ma-load ang categories: $e', error: true);
    }
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (amount == null || amount <= 0) {
      showMsg(context, 'Maglagay ng valid na amount.', error: true);
      return;
    }
    if (amount > 1000000000) {
      showMsg(context, 'Masyadong malaki ang amount.', error: true);
      return;
    }
    final merchant = _merchant.text.trim();
    if (merchant.isEmpty && _categoryId == null) {
      showMsg(context, 'Maglagay ng pangalan o pumili ng category.', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final payload = {
        'type': _type,
        'amount': amount,
        'category_id': _categoryId,
        'merchant': merchant.isEmpty ? null : merchant,
        'day_of_month': _day,
      };
      if (_isEdit) {
        await supabase
            .from('recurring_transactions')
            .update(payload)
            .eq('id', widget.rule!['id']);
      } else {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        // switch on  -> null = may be logged this month (if the day has come)
        // switch off -> start from the next scheduled date
        final last = _logThisMonth
            ? null
            : fmtDate(latestOccurrenceOnOrBefore(_day, today));
        await supabase.from('recurring_transactions').insert({
          ...payload,
          'active': true,
          'last_generated_on': last,
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
        title: const Text('I-delete ito?'),
        content: const Text(
          'Titigil na ang auto-log nito. Hindi buburahin ang mga transaction na na-log na.',
        ),
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
      await supabase
          .from('recurring_transactions')
          .delete()
          .eq('id', widget.rule!['id']);
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
    _merchant.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final pad = pagePad(context);
    final amountStyle = isNarrow(context) ? tt.headlineLarge : tt.displaySmall;
    final visible = _categories.where((c) => c['type'] == _type).toList();

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
                  PageHeader(title: _isEdit ? 'Edit recurring' : 'Add recurring'),
                  const SizedBox(height: 18),
                  SegmentedButton<String>(
                    expandedInsets: EdgeInsets.zero,
                    segments: const [
                      ButtonSegment(
                        value: 'expense',
                        label: Text('Expense'),
                        icon: Icon(Icons.north_east_rounded),
                      ),
                      ButtonSegment(
                        value: 'income',
                        label: Text('Income'),
                        icon: Icon(Icons.south_west_rounded),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() {
                      _type = s.first;
                      _categoryId = null;
                    }),
                  ),
                  const SizedBox(height: 18),
                  GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: TextField(
                      controller: _amount,
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
                  const SizedBox(height: 18),
                  Text('Pangalan', style: tt.labelLarge),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _merchant,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Sahod, Rent, Netflix, Globe',
                      prefixIcon: Icon(Icons.storefront_rounded),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('Category', style: tt.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in visible)
                        ChoiceChip(
                          label: Text('${c['icon'] ?? ''} ${c['name']}'),
                          selected: _categoryId == c['id'],
                          onSelected: (_) => setState(() => _categoryId = c['id'] as String),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text('Anong araw ng buwan?', style: tt.labelLarge),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: _day,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.calendar_month_rounded),
                    ),
                    items: [
                      for (var d = 1; d <= 31; d++)
                        DropdownMenuItem(value: d, child: Text('Ika-$d')),
                    ],
                    onChanged: (v) => setState(() => _day = v ?? _day),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Kung wala ang araw na iyon sa buwan (hal. 31), sa huling araw ng buwan ito ma-lo-log.',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  if (!_isEdit) ...[
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _logThisMonth,
                      onChanged: (v) => setState(() => _logThisMonth = v),
                      title: const Text('I-log din ngayong buwan'),
                      subtitle: const Text(
                        'I-on kung hindi mo pa nailalagay ngayong buwan. Kung hindi, sa susunod na petsa ito magsisimula.',
                      ),
                    ),
                  ],
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
                        label: const Text('I-delete ang recurring'),
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
