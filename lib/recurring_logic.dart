// Wais Wallet - recurring transactions: turns due rules into real transactions

import 'core.dart';

DateTime dateInMonth(int year, int month, int day) {
  final last = DateTime(year, month + 1, 0).day; // last day of that month
  return DateTime(year, month, day > last ? last : day);
}

/// Scheduled dates that are due: after [last] (if any) and on/before [today].
/// With no [last], only the current month counts (no backfill into the past).
/// At most the 3 most recent are returned.
List<DateTime> dueOccurrences(int day, DateTime? last, DateTime today) {
  final start = last == null
      ? DateTime(today.year, today.month)
      : DateTime(last.year, last.month);
  final out = <DateTime>[];
  var m = start;
  while (m.year < today.year || (m.year == today.year && m.month <= today.month)) {
    final d = dateInMonth(m.year, m.month, day);
    final afterLast = last == null || d.isAfter(last);
    if (afterLast && !d.isAfter(today)) out.add(d);
    m = DateTime(m.year, m.month + 1);
  }
  return out.length > 3 ? out.sublist(out.length - 3) : out;
}

/// Latest scheduled date on/before [today]. Used when a new rule should NOT
/// log the current month (so the next log is the upcoming date).
DateTime latestOccurrenceOnOrBefore(int day, DateTime today) {
  final thisMonth = dateInMonth(today.year, today.month, day);
  if (!thisMonth.isAfter(today)) return thisMonth;
  final prev = DateTime(today.year, today.month - 1);
  return dateInMonth(prev.year, prev.month, day);
}

/// Creates the transactions that are due. Returns how many were created.
/// Safe to call often: each rule is "claimed" first, so two devices opening
/// the app at the same time will not create duplicates.
Future<int> generateDueRecurring() async {
  final rules = await supabase
      .from('recurring_transactions')
      .select()
      .eq('active', true);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  var created = 0;

  for (final r in rules) {
    final id = r['id'];
    final day = (r['day_of_month'] as num).toInt();
    final lastStr = r['last_generated_on'] as String?;
    final last = lastStr == null ? null : DateTime.tryParse(lastStr);
    final due = dueOccurrences(day, last, today);
    if (due.isEmpty) continue;

    final target = fmtDate(due.last);

    // 1) claim: only succeeds if nobody else moved last_generated_on meanwhile
    try {
      final base = supabase
          .from('recurring_transactions')
          .update({'last_generated_on': target});
      final claimed = lastStr == null
          ? await base.eq('id', id).isFilter('last_generated_on', null).select()
          : await base.eq('id', id).eq('last_generated_on', lastStr).select();
      if (claimed.isEmpty) continue;
    } catch (_) {
      continue;
    }

    // 2) create the transactions (dated on the scheduled day)
    try {
      await supabase.from('transactions').insert([
        for (final d in due)
          {
            'type': r['type'],
            'amount': r['amount'],
            'category_id': r['category_id'],
            'merchant': r['merchant'],
            'occurred_on': fmtDate(d),
            'source': 'recurring',
          },
      ]);
      created += due.length;
    } catch (_) {
      // 3) give the claim back so it can be retried next time
      try {
        await supabase
            .from('recurring_transactions')
            .update({'last_generated_on': lastStr})
            .eq('id', id);
      } catch (_) {}
    }
  }
  return created;
}

/// Used by the Add transaction form ("I-repeat buwan-buwan").
/// Creates a recurring rule (or updates one with the same name and type) so the
/// month you just logged is NOT generated again; the next one is next month.
Future<void> saveRecurringFromTransaction({
  required String type,
  required double amount,
  required String? categoryId,
  required String merchant,
  required int day,
  required DateTime loggedOn,
}) async {
  var last = fmtDate(dateInMonth(loggedOn.year, loggedOn.month, day));
  final name = merchant.trim();

  Map<String, dynamic>? existing;
  if (name.isNotEmpty) {
    final rows = await supabase
        .from('recurring_transactions')
        .select()
        .eq('type', type);
    for (final r in rows) {
      final m = ((r['merchant'] as String?) ?? '').trim().toLowerCase();
      if (m == name.toLowerCase()) {
        existing = Map<String, dynamic>.from(r);
        break;
      }
    }
  }

  // never move an existing rule backwards (that could cause duplicates)
  final prev = existing?['last_generated_on'] as String?;
  if (prev != null && prev.compareTo(last) > 0) last = prev;

  final data = {
    'type': type,
    'amount': amount,
    'category_id': categoryId,
    'merchant': name.isEmpty ? null : name,
    'day_of_month': day,
    'active': true,
    'last_generated_on': last,
  };

  if (existing != null) {
    await supabase
        .from('recurring_transactions')
        .update(data)
        .eq('id', existing['id']);
  } else {
    await supabase.from('recurring_transactions').insert(data);
  }
}
