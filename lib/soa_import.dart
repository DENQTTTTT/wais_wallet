// Wais Wallet - SOA import page
// 1) pick the PDF  2) read it ON THIS DEVICE  3) (optional) ask AI for the
// missing fields, after showing exactly what text would be sent.
// Returns a SoaResult to the previous page via Navigator.pop.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core.dart';
import 'soa_parser.dart';
import 'widgets.dart';

class SoaImportPage extends StatefulWidget {
  const SoaImportPage({super.key, required this.cardName});

  final String cardName;

  @override
  State<SoaImportPage> createState() => _SoaImportPageState();
}

class _SoaImportPageState extends State<SoaImportPage> {
  final _password = TextEditingController();

  Uint8List? _bytes;
  String? _fileName;

  bool _reading = false;
  bool _aiBusy = false;
  bool _needsPassword = false;

  SoaResult? _result;
  List<String> _warnings = [];
  String? _snippet; // what WOULD be sent to AI
  bool _showSnippet = false;
  bool _aiUsed = false;

  Future<void> _pick() async {
    try {
      // file_picker v12+: static API, returns PlatformFile? (null = cancelled)
      final f = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (f == null) return;
      // bytes are read on demand now (no more withData); kept in memory only
      final bytes = await f.readAsBytes();
      if (bytes.isEmpty) {
        if (mounted) showMsg(context, 'Hindi mabasa ang file. Subukan ulit.', error: true);
        return;
      }
      if (bytes.length > 15 * 1024 * 1024) {
        if (mounted) showMsg(context, 'Masyadong malaki ang PDF (max 15 MB).', error: true);
        return;
      }
      setState(() {
        _bytes = bytes;
        _fileName = f.name;
        _result = null;
        _snippet = null;
        _warnings = [];
        _needsPassword = false;
        _aiUsed = false;
        _showSnippet = false;
      });
    } catch (e) {
      if (mounted) showMsg(context, 'Hindi mabuksan ang file picker: $e', error: true);
    }
  }

  Future<void> _read() async {
    final bytes = _bytes;
    if (bytes == null) return;
    setState(() => _reading = true);
    await Future<void>.delayed(const Duration(milliseconds: 60)); // let the spinner paint
    try {
      final text = extractPdfText(bytes, password: _password.text);
      final res = parseSoaLocally(text);
      final warn = res.sanitize();
      if (!mounted) return;
      setState(() {
        _result = res;
        _warnings = warn;
        _snippet = buildAiSnippet(text);
        _needsPassword = false;
        _reading = false;
      });
      // the password is not needed anymore
      _password.clear();
      return;
    } on SoaPasswordRequired {
      if (mounted) {
        setState(() => _needsPassword = true);
        showMsg(context, 'Naka-password ang PDF. Ilagay ang password sa baba.', error: true);
      }
    } on SoaWrongPassword {
      if (mounted) {
        setState(() => _needsPassword = true);
        showMsg(context, 'Maling password. Subukan ulit.', error: true);
      }
    } on SoaNoText {
      if (mounted) {
        showMsg(
          context,
          'Walang mabasang text (mukhang scanned/litrato ang PDF). Ilagay na lang ang amounts nang mano-mano.',
          error: true,
        );
      }
    } on SoaReadError catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
    } catch (e) {
      if (mounted) showMsg(context, 'May error sa pagbasa: $e', error: true);
    }
    if (mounted) setState(() => _reading = false);
  }

  Future<void> _askAi() async {
    final snippet = _snippet;
    if (snippet == null || snippet.isEmpty) return;
    setState(() => _aiBusy = true);
    try {
      final resp = await supabase.functions.invoke(
        'super-handler',
        body: {'snippet': snippet},
      );
      final data = resp.data;
      if (data is! Map) throw 'Hindi inaasahang sagot mula sa server.';
      if (data['error'] != null) throw data['error'].toString();
      final ai = soaFromAiJson(Map<String, dynamic>.from(data));
      if (!mounted) return;
      if (ai == null) {
        showMsg(context, 'Walang nakita ang AI sa snippet.', error: true);
      } else {
        final cur = _result ?? SoaResult();
        cur.fillBlanksFrom(ai);
        final warn = cur.sanitize();
        setState(() {
          _result = cur;
          _warnings = warn;
          _aiUsed = true;
        });
      }
    } on FunctionException catch (e) {
      if (mounted) {
        final msg = e.status == 429
            ? 'Naubos na ang libreng limit ng AI sa ngayon. Subukan mamaya o i-type na lang.'
            : 'Hindi gumana ang AI (${e.status}). Puwede mong i-type na lang ang natitira.';
        showMsg(context, msg, error: true);
      }
    } catch (e) {
      if (mounted) showMsg(context, 'Hindi gumana ang AI: $e', error: true);
    }
    if (mounted) setState(() => _aiBusy = false);
  }

  void _use() {
    final r = _result;
    if (r == null || !r.hasAny) return;
    Navigator.of(context).pop(r);
  }

  @override
  void dispose() {
    _password.dispose();
    _bytes = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final res = _result;

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
                  const PageHeader(title: 'Upload SOA'),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 56),
                    child: Text(widget.cardName,
                        style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                  const SizedBox(height: 16),

                  // privacy note
                  GlassCard(
                    radius: 18,
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_rounded, color: cs.primary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Binabasa ang PDF dito mismo sa device mo. Hindi ina-upload ang file at '
                            'hindi sine-save ang password.',
                            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // pick
                  GestureDetector(
                    onTap: _reading || _aiBusy ? null : _pick,
                    child: GlassCard(
                      radius: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      child: Row(
                        children: [
                          Icon(
                            _bytes == null ? Icons.upload_file_rounded : Icons.picture_as_pdf_rounded,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _fileName ?? 'Pumili ng SOA (PDF)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text(_bytes == null ? 'Browse' : 'Palitan',
                              style: tt.labelLarge?.copyWith(color: cs.primary)),
                        ],
                      ),
                    ),
                  ),

                  if (_bytes != null) ...[
                    const SizedBox(height: 14),
                    PasswordField(
                      controller: _password,
                      label: _needsPassword
                          ? 'PDF password (kailangan)'
                          : 'PDF password (kung naka-lock)',
                      onSubmitted: (_) => _read(),
                    ),
                    const SizedBox(height: 16),
                    PrimaryButton(
                      label: 'Basahin ang SOA',
                      icon: Icons.document_scanner_rounded,
                      loading: _reading,
                      onPressed: _reading ? null : _read,
                    ),
                  ],

                  if (res != null) ...[
                    const SizedBox(height: 22),
                    Text('Nabasa mula sa SOA',
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    _FoundRow('Total amount due',
                        res.totalDue == null ? null : peso(res.totalDue!)),
                    const SizedBox(height: 8),
                    _FoundRow('Minimum amount due',
                        res.minDue == null ? null : peso(res.minDue!)),
                    const SizedBox(height: 8),
                    _FoundRow('Statement date',
                        res.statementDate == null ? null : fmtDate(res.statementDate!)),
                    const SizedBox(height: 8),
                    _FoundRow('Due date', res.dueDate == null ? null : fmtDate(res.dueDate!)),
                    for (final w in _warnings) ...[
                      const SizedBox(height: 8),
                      Text(w, style: tt.bodySmall?.copyWith(color: cs.error)),
                    ],
                    if (_aiUsed) ...[
                      const SizedBox(height: 8),
                      Text('May laman na galing sa AI — i-check muna bago i-save.',
                          style: tt.bodySmall?.copyWith(color: Colors.orange)),
                    ],

                    // optional AI help
                    if (!res.isComplete && !_aiUsed && (_snippet ?? '').isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _AiConsentCard(
                        snippet: _snippet!,
                        expanded: _showSnippet,
                        busy: _aiBusy,
                        onToggle: () => setState(() => _showSnippet = !_showSnippet),
                        onSend: _askAi,
                      ),
                    ],

                    const SizedBox(height: 22),
                    PrimaryButton(
                      label: res.hasAny ? 'Gamitin sa form' : 'Walang nabasa — i-type na lang',
                      icon: Icons.check_rounded,
                      onPressed: res.hasAny ? _use : () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'I-check pa rin ang numbers sa form bago i-save.',
                      textAlign: TextAlign.center,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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

class _FoundRow extends StatelessWidget {
  const _FoundRow(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ok = value != null;
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.help_outline_rounded,
              color: ok ? cs.primary : cs.onSurfaceVariant, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: tt.bodyMedium)),
          Text(
            value ?? 'Hindi nakita',
            style: tt.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: ok ? null : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiConsentCard extends StatelessWidget {
  const _AiConsentCard({
    required this.snippet,
    required this.expanded,
    required this.busy,
    required this.onToggle,
    required this.onSend,
  });

  final String snippet;
  final bool expanded;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Text('Tulungan ng AI? (optional)',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'May hindi nakita kaya puwedeng magpadala ng maliit na bahagi ng SOA sa AI (Google Gemini). '
            'Mga linya lang tungkol sa totals at dates ang ipapadala — walang transactions, at naka-mask na '
            'ang card/account numbers, email, at phone.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            'Paalala: sa libreng tier ng Gemini, puwedeng gamitin ng Google ang ipinadala para mag-improve '
            'ng products nila, at puwedeng may human reviewer na makabasa. Kung ayaw mo, laktawan lang ito.',
            style: tt.bodySmall?.copyWith(color: Colors.orange),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onToggle,
            child: Row(
              children: [
                Text(expanded ? 'Itago ang ipapadala' : 'Tingnan ang eksaktong ipapadala',
                    style: tt.labelLarge?.copyWith(color: cs.primary)),
                Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: cs.primary),
              ],
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                snippet,
                style: tt.bodySmall?.copyWith(fontFamily: 'monospace', height: 1.35),
              ),
            ),
          ],
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Oo, ipadala ang snippet na ito',
            icon: Icons.send_rounded,
            loading: busy,
            onPressed: busy ? null : onSend,
          ),
        ],
      ),
    );
  }
}