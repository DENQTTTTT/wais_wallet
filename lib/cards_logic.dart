// Wais Wallet - credit card due-date logic (shared by Home and Cards pages)

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'core.dart';

class DueItem {
  DueItem({
    required this.cardId,
    required this.cardName,
    required this.dueDate,
    this.last4,
    this.amount,
    this.minDue,
    this.statementId,
  });

  final String cardId;
  final String cardName;
  final String? last4;
  final DateTime dueDate;
  final double? amount; // total due from the statement (null = just a reminder)
  final double? minDue;
  final String? statementId;

  bool get fromStatement => statementId != null;

  int get daysLeft {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return dueDate.difference(today).inDays;
  }
}

DateTime _clampDay(int year, int month, int day) {
  final last = DateTime(year, month + 1, 0).day; // last day of that month
  return DateTime(year, month, math.min(day, last));
}

/// Next calendar date (today or later) that falls on [dueDay] of the month.
DateTime nextDueDate(int dueDay, DateTime from) {
  final today = DateTime(from.year, from.month, from.day);
  final thisMonth = _clampDay(today.year, today.month, dueDay);
  if (!thisMonth.isBefore(today)) return thisMonth;
  return _clampDay(today.year, today.month + 1, dueDay);
}

String dueLabel(int d) {
  if (d < 0) return 'Overdue ${-d}d';
  if (d == 0) return 'Due today';
  if (d == 1) return 'Due tomorrow';
  return 'In $d days';
}

Color dueColor(int d, ColorScheme cs) {
  if (d <= 3) return cs.error;
  if (d <= 7) return Colors.orange;
  return cs.primary;
}

/// One entry per card: the earliest UNPAID statement, or (if there is none)
/// a reminder based on the card's due day.
List<DueItem> buildDueItems(
  List<Map<String, dynamic>> cards,
  List<Map<String, dynamic>> unpaidStatements,
) {
  final sorted = [...unpaidStatements]
    ..sort((a, b) => (a['due_date'] as String).compareTo(b['due_date'] as String));
  final firstByCard = <String, Map<String, dynamic>>{};
  for (final s in sorted) {
    firstByCard.putIfAbsent(s['card_id'] as String, () => s);
  }

  final items = <DueItem>[];
  for (final c in cards) {
    final id = c['id'] as String;
    final name = (c['nickname'] as String?) ?? 'Card';
    final last4 = (c['last4'] as String?)?.trim();
    final s = firstByCard[id];
    if (s != null) {
      items.add(DueItem(
        cardId: id,
        cardName: name,
        last4: last4,
        dueDate: DateTime.parse(s['due_date'] as String),
        amount: (s['total_due'] as num).toDouble(),
        minDue: (s['min_due'] as num).toDouble(),
        statementId: s['id'] as String,
      ));
    } else if (c['due_day'] != null) {
      final n = DateTime.now();
      items.add(DueItem(
        cardId: id,
        cardName: name,
        last4: last4,
        dueDate: nextDueDate(c['due_day'] as int, DateTime(n.year, n.month, n.day)),
      ));
    }
  }
  items.sort((a, b) => a.dueDate.compareTo(b.dueDate));
  return items;
}

Future<List<DueItem>> loadDueItems() async {
  final cards = List<Map<String, dynamic>>.from(
    await supabase.from('cards').select().eq('active', true),
  );
  final stmts = List<Map<String, dynamic>>.from(
    await supabase.from('statements').select().eq('status', 'unpaid'),
  );
  return buildDueItems(cards, stmts);
}
