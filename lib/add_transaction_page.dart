// Wais Wallet - add a transaction
// Auto-category order: 1) what you taught the app  2) built-in PH merchants
// 3) AI guess (merchant name only) when the name is unknown.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core.dart';
import 'budgets_logic.dart';
import 'merchant_guess.dart';
import 'recurring_logic.dart';
import 'recurring_page.dart';
import 'widgets.dart';

/// Name of the Edge Function (Supabase -> Edge Functions).
const _aiFunctionName = 'suggest-category';

class _Guess {
  _Guess(this.categoryId, this.note);
  final String categoryId;
  final String note;
}

class AddTransactionPage extends StatefulWidget {
  const AddTransactionPage({super.key, this.transaction, this.initialType});

  /// When set, the page edits this transaction row instead of adding a new one.
  final Map<String, dynamic>? transaction;

  /// 'expense' or 'income' (used only when adding).
  final String? initialType;

  @override
  State<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends State<AddTransactionPage> {
  final _amount = TextEditingController();
  final _merchant = TextEditingController();
  final _note = TextEditingController();
  String _type = 'expense';
  DateTime _date = DateTime.now();
  String? _categoryId;
  bool _userPickedCategory = false;
  List<Map<String, dynamic>> _categories = [];
  final Map<String, String> _rules = {}; // keyword -> category_id
  bool _saving = false;
  bool _deleting = false;
  bool _repeat = false; // add mode: also create a monthly recurring rule
  int? _repeatDay; // null = follow the picked date
  bool _editLock = false; // edit mode: keep the saved category until the merchant changes
  bool _chipTapped = false;
  String _origMerchant = '';

  bool get _isEdit => widget.transaction != null;

  Timer? _debounce;
  bool _aiOn = true;
  bool _aiBusy = false;
  String? _autoNote; // small hint under the categories
  final Map<String, String?> _aiCache = {}; // "type|merchant" -> category_id

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    if (t != null) {
      _type = (t['type'] as String?) ?? 'expense';
      final a = (t['amount'] as num).toDouble();
      _amount.text = a == a.roundToDouble() ? a.toStringAsFixed(0) : a.toStringAsFixed(2);
      _merchant.text = (t['merchant'] as String?) ?? '';
      _origMerchant = _merchant.text.trim();
      _note.text = (t['note'] as String?) ?? '';
      _categoryId = t['category_id'] as String?;
      _userPickedCategory = true;
      _editLock = true;
      final d = DateTime.tryParse('${t['occurred_on']}');
      if (d != null) _date = d;
    } else if (widget.initialType == 'income') {
      _type = 'income';
    }
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final cats = await supabase.from('categories').select().order('name');
      final rules = await supabase.from('merchant_rules').select();
      if (!mounted) return;
      setState(() {
        _categories = List<Map<String, dynamic>>.from(cats);
        for (final r in rules) {
          _rules[(r['keyword'] as String).toLowerCase()] = r['category_id'] as String;
        }
      });
    } catch (e) {
      if (!mounted) return;
      showMsg(context, 'Hindi ma-load ang categories: $e', error: true);
    }
  }

  Map<String, dynamic>? _catById(String id) {
    for (final c in _categories) {
      if (c['id'] == id) return c;
    }
    return null;
  }

  Map<String, dynamic>? _catByName(String type, String name) {
    for (final c in _categories) {
      if (c['type'] == type && (c['name'] as String).toLowerCase() == name.toLowerCase()) {
        return c;
      }
    }
    return null;
  }

  String _label(Map<String, dynamic> c) => '${c['icon'] ?? ''} ${c['name']}'.trim();

  /// Local guess (no internet): learned rules first, then the built-in list.
  _Guess? _localGuess(String text) {
    final norm = normalizeMerchant(text);
    if (norm.isEmpty) return null;

    // 1) what you taught the app (longest keyword wins, whole words)
    String? bestCat;
    var bestLen = 0;
    for (final e in _rules.entries) {
      final kw = normalizeMerchant(e.key);
      if (kw.length <= bestLen || !merchantHasWord(norm, kw)) continue;
      final cat = _catById(e.value);
      if (cat == null || cat['type'] != _type) continue;
      bestCat = e.value;
      bestLen = kw.length;
    }
    if (bestCat != null) {
      final cat = _catById(bestCat)!;
      return _Guess(bestCat, 'Auto: ${_label(cat)} (natutunan mo na)');
    }

    // 2) built-in Philippine merchants
    final name = builtInCategoryFor(text, _type);
    if (name != null) {
      final cat = _catByName(_type, name);
      if (cat != null) return _Guess(cat['id'] as String, 'Auto: ${_label(cat)}');
    }
    return null;
  }

  void _onMerchantChanged(String v) {
    _debounce?.cancel();
    if (_editLock && v.trim() != _origMerchant) {
      _editLock = false;
      if (!_chipTapped) _userPickedCategory = false;
    }
    if (_userPickedCategory) return;
    final text = v.trim();

    if (text.isEmpty) {
      setState(() {
        _categoryId = null;
        _autoNote = null;
      });
      return;
    }

    final g = _localGuess(text);
    if (g != null) {
      setState(() {
        _categoryId = g.categoryId;
        _autoNote = g.note;
      });
      return;
    }

    // unknown name: clear the old auto pick, then (maybe) ask the AI
    setState(() {
      _categoryId = null;
      _autoNote = null;
    });
    if (_aiOn && text.length >= 3) {
      _debounce = Timer(const Duration(milliseconds: 900), () => _askAi(text));
    }
  }

  Future<void> _askAi(String text) async {
    if (!mounted || _userPickedCategory) return;
    final type = _type;
    final key = '$type|${normalizeMerchant(text)}';
    String? catId;

    if (_aiCache.containsKey(key)) {
      catId = _aiCache[key];
    } else {
      final names = <String>[
        for (final c in _categories)
          if (c['type'] == type) c['name'] as String,
      ];
      if (names.isEmpty) return;
      setState(() => _aiBusy = true);
      try {
        final resp = await supabase.functions.invoke(
          _aiFunctionName,
          body: {'merchant': text, 'type': type, 'categories': names},
        );
        final data = resp.data;
        String? name;
        if (data is Map && data['category'] is String) name = data['category'] as String;
        if (name != null) catId = _catByName(type, name)?['id'] as String?;
        _aiCache[key] = catId; // only successful answers are remembered
      } on FunctionException {
        // quota / network / not deployed: stay quiet, user can pick by hand
      } catch (_) {}
      if (mounted) setState(() => _aiBusy = false);
    }

    if (!mounted || catId == null) return;
    // ignore the answer if the user already moved on
    if (_userPickedCategory || _type != type || _merchant.text.trim() != text) return;
    final cat = _catById(catId);
    if (cat == null) return;
    setState(() {
      _categoryId = catId;
      _autoNote = '\u2728 AI hula: ${_label(cat)} \u2014 palitan kung mali';
    });
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
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
    final note = _note.text.trim();

    setState(() => _saving = true);
    try {
      final payload = {
        'type': _type,
        'amount': amount,
        'category_id': _categoryId,
        'merchant': merchant.isEmpty ? null : merchant,
        'note': note.isEmpty ? null : note,
        'occurred_on': fmtDate(_date),
      };
      if (_isEdit) {
        await supabase
            .from('transactions')
            .update(payload)
            .eq('id', widget.transaction!['id']);
      } else {
        await supabase.from('transactions').insert({...payload, 'source': 'manual'});
      }
    } catch (e) {
      if (!mounted) return;
      showMsg(context, 'Hindi na-save: $e', error: true);
      setState(() => _saving = false);
      return;
    }

    // Remember "merchant -> category" so next time it's one tap.
    if (merchant.isNotEmpty && _categoryId != null) {
      try {
        await supabase.from('merchant_rules').upsert(
          {'keyword': merchant.toLowerCase(), 'category_id': _categoryId},
          onConflict: 'user_id,keyword',
        );
      } catch (_) {}
    }

    // Optional: make it repeat every month
    String? msg;
    var msgError = false;
    if (!_isEdit && _repeat) {
      try {
        await saveRecurringFromTransaction(
          type: _type,
          amount: amount,
          categoryId: _categoryId,
          merchant: merchant,
          day: _repeatDay ?? _date.day,
          loggedOn: _date,
        );
        msg = 'Na-save at naka-set na buwan-buwan 🔁';
      } catch (e) {
        msg = 'Na-save ang transaction pero hindi ma-set ang recurring: $e';
        msgError = true;
      }
    }

    // Budget heads-up (80% / 100%)
    if (_type == 'expense') {
      final catName = _categoryId == null
          ? ''
          : ((_catById(_categoryId!)?['name'] as String?) ?? '');
      final w = await budgetWarning(
        categoryId: _categoryId,
        categoryName: catName,
        date: _date,
      );
      if (w != null) msg = msg == null ? w : '$msg\n$w';
    }
    if (msg != null && mounted) showMsg(context, msg, error: msgError);

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
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
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await supabase
          .from('transactions')
          .delete()
          .eq('id', widget.transaction!['id']);
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
    _debounce?.cancel();
    _amount.dispose();
    _merchant.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final amountStyle = isNarrow(context) ? tt.headlineLarge : tt.displaySmall;
    final visible = _categories.where((c) => c['type'] == _type).toList();
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final isToday = _sameDay(_date, today);
    final isYesterday = _sameDay(_date, yesterday);

    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth(context, 560)),
              child: ListView(
                padding: EdgeInsets.fromLTRB(pagePad(context), 12, pagePad(context), 32),
                children: [
                  PageHeader(title: _isEdit ? 'Edit transaction' : 'Add transaction'),
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
                    onSelectionChanged: (s) {
                      setState(() {
                        _type = s.first;
                        _categoryId = null;
                        _userPickedCategory = false;
                        _autoNote = null;
                      });
                      _onMerchantChanged(_merchant.text);
                    },
                  ),
                  const SizedBox(height: 18),
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
                  ).animate().fadeIn().slideY(begin: 0.1),
                  const SizedBox(height: 18),
                  Text('Where / what', style: tt.labelLarge),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _merchant,
                    onChanged: _onMerchantChanged,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Jollibee, Grab, Meralco',
                      prefixIcon: Icon(Icons.storefront_rounded),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'AI hula kapag hindi kilala ang pangalan (pangalan lang ang ipapadala)',
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                      Switch(
                        value: _aiOn,
                        onChanged: (v) {
                          setState(() => _aiOn = v);
                          if (v) _onMerchantChanged(_merchant.text);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
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
                          onSelected: (_) => setState(() {
                            _categoryId = c['id'] as String;
                            _userPickedCategory = true;
                            _chipTapped = true;
                            _autoNote = null;
                          }),
                        ),
                    ],
                  ),
                  if (_aiBusy) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text('Hinuhulaan ng AI...', style: tt.bodySmall),
                      ],
                    ),
                  ] else if (_autoNote != null) ...[
                    const SizedBox(height: 10),
                    Text(_autoNote!, style: tt.bodySmall?.copyWith(color: cs.primary)),
                  ],
                  const SizedBox(height: 18),
                  Text('Date', style: tt.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Ngayon'),
                        selected: isToday,
                        onSelected: (_) => setState(() => _date = today),
                      ),
                      ChoiceChip(
                        label: const Text('Kahapon'),
                        selected: isYesterday,
                        onSelected: (_) => setState(() => _date = yesterday),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                        label: Text(isToday || isYesterday ? 'Ibang date' : fmtDate(_date)),
                        onPressed: _pickDate,
                      ),
                    ],
                  ),
                  if (!_isEdit) ...[
                    const SizedBox(height: 14),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _repeat,
                      onChanged: (v) => setState(() => _repeat = v),
                      title: const Text('I-repeat buwan-buwan 🔁'),
                      subtitle: const Text('Kusa nang ma-lo-log tuwing buwan (auto recurring)'),
                    ),
                    if (_repeat) ...[
                      const SizedBox(height: 6),
                      DropdownButtonFormField<int>(
                        initialValue: _repeatDay ?? _date.day,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Anong araw ng buwan?',
                          prefixIcon: Icon(Icons.calendar_month_rounded),
                        ),
                        items: [
                          for (var d = 1; d <= 31; d++)
                            DropdownMenuItem(value: d, child: Text('Ika-$d')),
                        ],
                        onChanged: (v) => setState(() => _repeatDay = v),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Ise-save ito ngayon, at susunod na ang buwan-buwan. Kung wala ang araw sa buwan (hal. 31), sa huling araw ito ma-lo-log.',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ] else if (widget.transaction?['source'] == 'recurring') ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(Icons.autorenew_rounded, size: 20, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Galing sa recurring',
                            style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(softRoute(const RecurringPage())),
                          child: const Text('Recurring'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  TextField(
                    controller: _note,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
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
                        label: const Text('I-delete ang transaction'),
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
