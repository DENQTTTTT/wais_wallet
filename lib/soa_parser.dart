// Wais Wallet - SOA (statement of account) reader
// Everything here runs ON THE DEVICE: PDF decrypt, text extraction, parsing.
// The PDF file and its password are never uploaded or stored.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

// ---------------------------------------------------------------- result

class SoaResult {
  SoaResult({this.totalDue, this.minDue, this.statementDate, this.dueDate});

  double? totalDue;
  double? minDue;
  DateTime? statementDate;
  DateTime? dueDate;

  int get foundCount => [totalDue, minDue, statementDate, dueDate].where((e) => e != null).length;
  bool get isComplete => foundCount == 4;
  bool get hasAny => foundCount > 0;

  /// Fill only the empty fields from [other] (local results win over AI).
  void fillBlanksFrom(SoaResult other) {
    totalDue ??= other.totalDue;
    minDue ??= other.minDue;
    statementDate ??= other.statementDate;
    dueDate ??= other.dueDate;
  }

  /// Drops values that make no sense, returns warnings to show the person.
  List<String> sanitize() {
    final w = <String>[];
    if (totalDue != null && (totalDue! < 0 || totalDue! > 100000000)) {
      totalDue = null;
    }
    if (minDue != null && (minDue! < 0 || minDue! > 100000000)) {
      minDue = null;
    }
    if (totalDue != null && minDue != null && minDue! > totalDue!) {
      w.add('Mas malaki ang minimum kaysa sa total — tingnan mo ulit.');
      minDue = null;
    }
    if (statementDate != null && dueDate != null && dueDate!.isBefore(statementDate!)) {
      w.add('Mas maaga ang due date kaysa statement date — tingnan mo ulit.');
      dueDate = null;
    }
    return w;
  }
}

// ---------------------------------------------------------------- errors

class SoaPasswordRequired implements Exception {}

class SoaWrongPassword implements Exception {}

class SoaNoText implements Exception {}

class SoaReadError implements Exception {
  SoaReadError(this.message);
  final String message;
}

// ---------------------------------------------------------------- PDF -> text

/// Reads the text of the first pages of the PDF (that is where totals and
/// dates live). Throws [SoaPasswordRequired], [SoaWrongPassword], [SoaNoText].
String extractPdfText(Uint8List bytes, {String? password}) {
  PdfDocument? doc;
  try {
    final pw = (password == null || password.isEmpty) ? null : password;
    doc = PdfDocument(inputBytes: bytes, password: pw);
    final pages = doc.pages.count;
    final last = math.min(pages, 3) - 1; // first 3 pages is plenty
    final extractor = PdfTextExtractor(doc);
    var text = extractor.extractText(startPageIndex: 0, endPageIndex: last, layoutText: true);
    if (text.trim().isEmpty) {
      text = extractor.extractText(startPageIndex: 0, endPageIndex: last);
    }
    if (text.trim().isEmpty) throw SoaNoText();
    return text;
  } on SoaNoText {
    rethrow;
  } catch (e) {
    final m = e.toString().toLowerCase();
    if (m.contains('password') || m.contains('encrypt') || m.contains('decrypt')) {
      if (password == null || password.isEmpty) throw SoaPasswordRequired();
      throw SoaWrongPassword();
    }
    throw SoaReadError('Hindi mabasa ang PDF: $e');
  } finally {
    doc?.dispose();
  }
}

// ---------------------------------------------------------------- tokens

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

const _monAlt = 'jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec';

final _amountRe = RegExp(r'(\d{1,3}(?:,\d{3})+\.\d{2}|\d+\.\d{2})');
final _dateMonthFirst = RegExp('($_monAlt)[a-z]*\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?,?\\s+(\\d{4})', caseSensitive: false);
final _dateDayFirst = RegExp('(\\d{1,2})[\\s\\-]+($_monAlt)[a-z]*\\.?[\\s,\\-]+(\\d{4})', caseSensitive: false);
final _dateSlash = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})');
final _dateIso = RegExp(r'(\d{4})-(\d{2})-(\d{2})');

class _Tok {
  _Tok(this.start, this.end, {this.amount, this.date});
  final int start;
  final int end;
  final double? amount;
  final DateTime? date;
  bool get isDate => date != null;
}

DateTime? _mk(int y, int m, int d) {
  if (y < 2000 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(y, m, d);
  if (dt.month != m) return null; // e.g. Feb 31
  return dt;
}

List<_Tok> _tokens(String s) {
  final out = <_Tok>[];
  final taken = <List<int>>[]; // ranges used by dates, so amounts don't overlap
  bool overlaps(int a, int b) => taken.any((r) => a < r[1] && b > r[0]);

  void addDate(Match m, DateTime? d) {
    if (d == null || overlaps(m.start, m.end)) return;
    taken.add([m.start, m.end]);
    out.add(_Tok(m.start, m.end, date: d));
  }

  for (final m in _dateMonthFirst.allMatches(s)) {
    addDate(m, _mk(int.parse(m.group(3)!), _months[m.group(1)!.toLowerCase().substring(0, 3)]!, int.parse(m.group(2)!)));
  }
  for (final m in _dateDayFirst.allMatches(s)) {
    addDate(m, _mk(int.parse(m.group(3)!), _months[m.group(2)!.toLowerCase().substring(0, 3)]!, int.parse(m.group(1)!)));
  }
  for (final m in _dateIso.allMatches(s)) {
    addDate(m, _mk(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!)));
  }
  for (final m in _dateSlash.allMatches(s)) {
    final a = int.parse(m.group(1)!);
    final b = int.parse(m.group(2)!);
    final y = int.parse(m.group(3)!);
    // PH banks mostly use MM/DD/YYYY. If the first part can't be a month, it's DD/MM.
    final d = a > 12 ? _mk(y, b, a) : _mk(y, a, b);
    addDate(m, d);
  }
  for (final m in _amountRe.allMatches(s)) {
    if (overlaps(m.start, m.end)) continue;
    final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
    if (v == null) continue;
    out.add(_Tok(m.start, m.end, amount: v));
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

// ---------------------------------------------------------------- labels

enum _Key { total, min, stmt, due }

bool _isDateKey(_Key k) => k == _Key.stmt || k == _Key.due;

// Order matters inside each key (more specific first).
final _labelPatterns = <_Key, List<RegExp>>{
  _Key.min: [
    RegExp(r'min(?:imum)?\.?\s+(?:amount\s+|amt\.?\s+)?(?:due|payment)', caseSensitive: false),
    RegExp(r'min(?:imum)?\.?\s+amt', caseSensitive: false),
  ],
  _Key.due: [
    RegExp(r'payment\s+due\s+date', caseSensitive: false),
    RegExp(r'due\s+date', caseSensitive: false),
    RegExp(r'pay(?:ment)?\s+on\s+or\s+before', caseSensitive: false),
  ],
  _Key.stmt: [
    RegExp(r'statement\s+(?:closing\s+|cut-?\s?off\s+)?date', caseSensitive: false),
    RegExp(r'(?:cut-?\s?off|closing|billing)\s+date', caseSensitive: false),
    RegExp(r'statement\s+cut-?\s?off', caseSensitive: false),
  ],
  _Key.total: [
    RegExp(r'total\s+amount\s+due', caseSensitive: false),
    RegExp(r'total\s+amt\.?\s+due', caseSensitive: false),
    RegExp(r'total\s+due', caseSensitive: false),
    RegExp(r'amount\s+due', caseSensitive: false),
    RegExp(r'new\s+balance', caseSensitive: false),
    RegExp(r'outstanding\s+balance', caseSensitive: false),
  ],
};

class _Label {
  _Label(this.key, this.start, this.end);
  final _Key key;
  final int start;
  final int end;
}

List<_Label> _labelsIn(String line) {
  final all = <_Label>[];
  _labelPatterns.forEach((key, pats) {
    for (final p in pats) {
      for (final m in p.allMatches(line)) {
        // "Minimum amount due" must not count as the TOTAL "amount due".
        if (key == _Key.total) {
          final before = line.substring(math.max(0, m.start - 14), m.start).toLowerCase();
          if (before.contains('min')) continue;
        }
        all.add(_Label(key, m.start, m.end));
      }
    }
  });
  // Resolve overlaps: earliest start wins, then the longest.
  all.sort((a, b) {
    final c = a.start.compareTo(b.start);
    return c != 0 ? c : (b.end - b.start).compareTo(a.end - a.start);
  });
  final out = <_Label>[];
  var lastEnd = -1;
  for (final l in all) {
    if (l.start >= lastEnd) {
      out.add(l);
      lastEnd = l.end;
    }
  }
  return out;
}

// ---------------------------------------------------------------- parser

SoaResult parseSoaLocally(String text) {
  final lines = text.split(RegExp(r'\r?\n')).map((l) => l.trimRight()).toList();
  final res = SoaResult();

  void put(_Key k, _Tok t) {
    switch (k) {
      case _Key.total:
        res.totalDue ??= t.amount;
      case _Key.min:
        res.minDue ??= t.amount;
      case _Key.stmt:
        res.statementDate ??= t.date;
      case _Key.due:
        res.dueDate ??= t.date;
    }
  }

  bool has(_Key k) => switch (k) {
        _Key.total => res.totalDue != null,
        _Key.min => res.minDue != null,
        _Key.stmt => res.statementDate != null,
        _Key.due => res.dueDate != null,
      };

  bool typeOk(_Key k, _Tok t) => _isDateKey(k) ? t.isDate : (t.amount != null);

  final labelsByLine = [for (final l in lines) _labelsIn(l)];

  // Pass A: value on the same line, right after the label.
  for (var i = 0; i < lines.length; i++) {
    final ls = labelsByLine[i];
    for (var j = 0; j < ls.length; j++) {
      final l = ls[j];
      if (has(l.key)) continue;
      final segEnd = j + 1 < ls.length ? ls[j + 1].start : lines[i].length;
      final seg = lines[i].substring(l.end, math.min(segEnd, lines[i].length));
      if (seg.length > 120) continue;
      final toks = _tokens(seg).where((t) => typeOk(l.key, t));
      if (toks.isNotEmpty) put(l.key, toks.first);
    }
  }

  // Pass B: a header row with several labels, values on the next row(s).
  for (var i = 0; i < lines.length; i++) {
    final ls = labelsByLine[i];
    if (ls.length < 2) continue;
    if (_tokens(lines[i]).isNotEmpty) continue; // not a header-only line
    // find the next non-empty line (look at most 3 lines ahead)
    for (var k = i + 1; k < math.min(lines.length, i + 4); k++) {
      if (lines[k].trim().isEmpty) continue;
      final toks = _tokens(lines[k]);
      final dates = toks.where((t) => t.isDate).toList();
      final amts = toks.where((t) => !t.isDate).toList();
      var di = 0, ai = 0;
      for (final l in ls) {
        if (_isDateKey(l.key)) {
          if (di < dates.length) {
            if (!has(l.key)) put(l.key, dates[di]);
            di++;
          }
        } else {
          if (ai < amts.length) {
            if (!has(l.key)) put(l.key, amts[ai]);
            ai++;
          }
        }
      }
      break;
    }
  }

  // Pass C: single label on its own line, value on the next line.
  for (var i = 0; i < lines.length - 1; i++) {
    final ls = labelsByLine[i];
    if (ls.length != 1) continue;
    final l = ls.first;
    if (has(l.key)) continue;
    for (var k = i + 1; k < math.min(lines.length, i + 3); k++) {
      if (lines[k].trim().isEmpty) continue;
      final toks = _tokens(lines[k]).where((t) => typeOk(l.key, t));
      if (toks.isNotEmpty) put(l.key, toks.first);
      break;
    }
  }

  return res;
}

// ---------------------------------------------------------------- AI snippet (privacy)

final _keywordRe = RegExp(
  r'due|minimum|min\.|statement|cut-?\s?off|closing|billing|payment|balance|amount|credit\s+limit',
  caseSensitive: false,
);

/// Builds the SMALL piece of text that may be sent to the AI:
/// only lines about totals/dates, with card/account numbers, emails and
/// phone numbers masked. Transactions, names and addresses are not included.
String buildAiSnippet(String text, {int maxLines = 40, int maxChars = 3500}) {
  final lines = text.split(RegExp(r'\r?\n')).map((l) => l.trim()).toList();
  final keep = <int>{};
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].isEmpty) continue;
    if (_keywordRe.hasMatch(lines[i])) {
      keep.add(i);
      // header rows often have their values on the next line
      if (i + 1 < lines.length && lines[i + 1].isNotEmpty) keep.add(i + 1);
    }
  }
  final order = keep.toList()..sort();
  final buf = StringBuffer();
  var n = 0;
  for (final i in order) {
    final line = redact(lines[i]);
    if (line.isEmpty) continue;
    if (n >= maxLines || buf.length + line.length > maxChars) break;
    buf.writeln(line.length > 220 ? line.substring(0, 220) : line);
    n++;
  }
  return buf.toString().trim();
}

String _maskDigits(String s) {
  final digits = s.replaceAll(RegExp(r'\D'), '');
  final last4 = digits.length >= 4 ? digits.substring(digits.length - 4) : digits;
  return '****$last4';
}

String redact(String s) {
  var out = s;
  // 16-digit style numbers written in groups (5432 1234 5678 9012 / 5432-1234-...)
  out = out.replaceAllMapped(RegExp(r'(?:\d{4}[ \-]){2,}\d{2,4}'), (m) => _maskDigits(m.group(0)!));
  // long digit runs (card / account numbers without separators)
  out = out.replaceAllMapped(RegExp(r'\d{9,}'), (m) => _maskDigits(m.group(0)!));
  out = out.replaceAll(RegExp(r'[\w.+\-]+@[\w\-]+\.[\w.\-]+'), '[email]');
  out = out.replaceAll(RegExp(r'(?:\+?63|0)[\s\-]?9\d{2}[\s\-]?\d{3}[\s\-]?\d{4}'), '[phone]');
  return out;
}

// ---------------------------------------------------------------- AI response

SoaResult? soaFromAiJson(Map<String, dynamic> j) {
  double? numOf(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '').trim());
    return null;
  }

  DateTime? dateOf(dynamic v) {
    if (v is! String) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v.trim());
    if (m == null) return null;
    return _mk(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }

  final r = SoaResult(
    totalDue: numOf(j['total_due']),
    minDue: numOf(j['min_due']),
    statementDate: dateOf(j['statement_date']),
    dueDate: dateOf(j['due_date']),
  );
  return r.hasAny ? r : null;
}
