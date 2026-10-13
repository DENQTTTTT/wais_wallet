// Wais Wallet - budgets: load, compute spent, warnings, "safe to spend today"

import 'package:flutter/material.dart';

import 'core.dart';

class Budget {
  Budget({required this.id, required this.categoryId, required this.amount});

  final String id;

  /// null = overall monthly budget (all expenses)
  final String? categoryId;
  final double amount;

  factory Budget.fromRow(Map<String, dynamic> r) => Budget(
        id: r['id'] as String,
        categoryId: r['category_id'] as String?,
        amount: (r['amount'] as num).toDouble(),
      );
}

Future<List<Budget>> loadBudgets() async {
  final rows = await supabase.from('budgets').select();
  return [
    for (final r in rows) Budget.fromRow(Map<String, dynamic>.from(r)),
  ];
}

/// Expense totals per category id (rows without a category are skipped).
Map<String, double> spentByCategory(List<Map<String, dynamic>> items) {
  final map = <String, double>{};
  for (final t in items) {
    if (t['type'] != 'expense') continue;
    final id = t['category_id'] as String?;
    if (id == null) continue;
    map.update(id, (v) => v + (t['amount'] as num).toDouble(),
        ifAbsent: () => (t['amount'] as num).toDouble());
  }
  return map;
}

double totalExpenseOf(List<Map<String, dynamic>> items) {
  var sum = 0.0;
  for (final t in items) {
    if (t['type'] == 'expense') sum += (t['amount'] as num).toDouble();
  }
  return sum;
}

const budgetWarnColor = Color(0xFFF59E0B);

/// normal -> orange at 80% -> red at 100%
Color budgetColor(double pct, ColorScheme cs) {
  if (pct >= 1) return cs.error;
  if (pct >= 0.8) return budgetWarnColor;
  return cs.primary;
}

int daysLeftInMonth(DateTime now) =>
    DateTime(now.year, now.month + 1, 0).day - now.day + 1; // counts today

/// How much you can spend per day for the rest of the month.
/// Uses the overall budget if there is one, else the sum of what is left in
/// each category budget. Returns null when there are no budgets.
double? safeToSpendPerDay(
  List<Budget> budgets,
  Map<String, double> spent,
  double total,
  DateTime now,
) {
  if (budgets.isEmpty) return null;
  Budget? overall;
  for (final b in budgets) {
    if (b.categoryId == null) overall = b;
  }
  double remaining;
  if (overall != null) {
    remaining = overall.amount - total;
  } else {
    remaining = 0;
    for (final b in budgets) {
      final left = b.amount - (spent[b.categoryId] ?? 0);
      if (left > 0) remaining += left;
    }
  }
  if (remaining < 0) remaining = 0;
  return remaining / daysLeftInMonth(now);
}

/// Message to show after saving an expense (null = nothing to warn about).
/// Never throws: if the budgets table does not exist yet, returns null.
Future<String?> budgetWarning({
  required String? categoryId,
  required String categoryName,
  required DateTime date,
}) async {
  try {
    final budgets = await loadBudgets();
    if (budgets.isEmpty) return null;
    final start = DateTime(date.year, date.month);
    final next = DateTime(date.year, date.month + 1);
    final rows = await supabase
        .from('transactions')
        .select('category_id, amount')
        .eq('type', 'expense')
        .gte('occurred_on', fmtDate(start))
        .lt('occurred_on', fmtDate(next));
    var total = 0.0;
    var cat = 0.0;
    for (final r in rows) {
      final a = (r['amount'] as num).toDouble();
      total += a;
      if (categoryId != null && r['category_id'] == categoryId) cat += a;
    }

    final msgs = <String>[];
    void check(String name, double spent, double limit) {
      if (limit <= 0) return;
      final pct = spent / limit;
      if (pct >= 1) {
        msgs.add('$name: lampas na sa budget (${peso(spent)} / ${peso(limit)})');
      } else if (pct >= 0.8) {
        msgs.add('$name: ${(pct * 100).round()}% na ng budget (${peso(spent)} / ${peso(limit)})');
      }
    }

    for (final b in budgets) {
      if (b.categoryId == null) {
        check('Overall', total, b.amount);
      } else if (b.categoryId == categoryId) {
        check(categoryName.isEmpty ? 'Category' : categoryName, cat, b.amount);
      }
    }
    return msgs.isEmpty ? null : msgs.join('\n');
  } catch (_) {
    return null;
  }
}
