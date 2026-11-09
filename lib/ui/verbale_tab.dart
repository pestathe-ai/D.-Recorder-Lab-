import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/ai_prompt.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/transcript_text.dart';
import '../core/verbale_document.dart';
import '../services/ai_client.dart';
import 'detail_page.dart';

class _Field {
  const _Field(this.label, this.get, this.set, {this.lines = 1, this.hint});
  final String label;
  final String Function(Verbale) get;
  final void Function(Verbale, String) set;
  final int lines;
  final String? hint;
}

final _header = <_Field>[
  _Field('Ente o organizzazione', (v) => v.ente, (v, t) => v.ente = t),
  _Field('Tipo di riunione', (v) => v.tipoRiunione, (v, t) => v.tipoRiunione = t,
      hint: 'es. assemblea dei soci'),
  _Field('Data', (v) => v.data, (v, t) => v.data = t),
  _Field('Ora di inizio', (v) => v.oraInizio, (v, t) => v.oraInizio = t),
  _Field('Ora di fine', (v) => v.oraFine, (v, t) => v.oraFine = t),
  _Field('Luogo', (v) => v.luogo, (v, t) => v.luogo = t),
  _Field('Presidente', (v) => v.presidente, (v, t) => v.presidente = t),
  _Field('Segretario', (v) => v.segretario, (v, t) => v.segretario = t),
];

final _body = <_Field>[
  _Field('Presenti', (v) => v.presenti, (v, t) => v.presenti = t, lines: 3),
  _Field('Assenti', (v) => v.assenti, (v, t) => v.assenti = t, lines: 2),
  _Field('Ordine del giorno', (v) => v.ordineDelGiorno, (v, t) => v.ordineDelGiorno = t, lines: 4),
  _Field('Discussione', (v) => v.discussione, (v, t) => v.discussione = t, lines: 12),
  _Field('Delibere', (v) => v.delibere, (v, t) => v.delibere = t, lines: 6),
  _Field('Varie ed eventuali', (v) => v.varie, (v, t) => v.varie = t, lines: 3),
];

class VerbaleTab extends StatefulWidget {
  const VerbaleTab({super.key, required this.page});
  final DetailPageState page;

  @override
  State<VerbaleTab> createState() => _VerbaleTabState();
}

class _VerbaleTabState extends State<VerbaleTab> with AutomaticKeepAliveClientMixin {
  DetailPageState get page => widget.page;
  late final Map<_Field, TextEditingController> _controllers = {
    for (final f in [..._header, ..._body])
      f: TextEditingController(text: f.get(page.verbale)),
  };
  bool _aiRunning = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    page.verbaleVersion.addListener(_reload);
  }

  @override
  void dispose() {
    page.verbaleVersion.removeListener(_reload);
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _reload() {
    _controllers.forEach((field, controller) {
      final value = field.get(page.verbale);
      if (controller.text != value) controller.text = value;
    });
  }

  Transcript? _doneTranscript() {
    final t = page.entry.loadTranscript();
    return t != null && t.done ? t : null;
  }

  void _needTranscript() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Prima completa la trascrizione.'),
    ));
  }

  Future<void> _fillDiscussion() async {
    final t = _doneTranscript();
    if (t == null) return _needTranscript();
    if (page.verbale.discussione.trim().isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sostituire la discussione?'),
          content: const Text('Il testo attuale verrà sostituito dalla trascrizione.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sostituisci')),
          ],
        ),
      );
      if (ok != true) return;
    }
    page.verbale.discussione = transcriptToDiscussion(t, page.entry.meta.markers);
    page.verbaleChangedExternally();
  }

  Future<void> _aiDraft() async {
    final t = _doneTranscript();
    if (t == null) return _needTranscript();
    final messenger = ScaffoldMessenger.of(context);
    final s = page.s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Inviare la trascrizione?'),
        content: const Text(
          'Il testo della trascrizione verrà inviato ad Anthropic per preparare la bozza. '
          'L\'audio resta sul telefono. I campi già compilati non verranno toccati.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Invia')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _aiRunning = true);
    try {
      final draft = await requestAiDraft(
        apiKey: s.settings.aiKey!,
        model: s.settings.aiModel,
        transcript: transcriptToText(page.entry.meta.title, t, page.entry.meta.markers),
        current: page.verbale,
      );
      applyAiDraft(page.verbale, draft);
      page.verbaleChangedExternally();
      messenger.showSnackBar(const SnackBar(
        content: Text('Bozza pronta: rileggila con attenzione, soprattutto [da verificare].'),
      ));
    } on AiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Bozza non riuscita. Riprova.')));
    } finally {
      if (mounted) setState(() => _aiRunning = false);
    }
  }

  Future<void> _export(bool word) async {
    final dir = await getTemporaryDirectory();
    final name = 'Verbale - ${safeFileName(page.entry.meta.title)}';
    final file = File(p.join(dir.path, word ? '$name.docx' : '$name.txt'));
    if (word) {
      await file.writeAsBytes(verbaleToDocx(page.verbale));
    } else {
      await file.writeAsString(verbaleToText(page.verbale));
    }
    await SharePlus.instance.share(ShareParams(
      files: [
        XFile(
          file.path,
          mimeType: word
              ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
              : 'text/plain',
        ),
      ],
      title: name,
    ));
  }

  Widget _input(_Field f) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _controllers[f],
        minLines: f.lines,
        maxLines: f.lines == 1 ? 1 : null,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: f.label,
          hintText: f.hint,
          alignLabelWithHint: f.lines > 1,
        ),
        onChanged: (text) {
          f.set(page.verbale, text);
          page.saveVerbale();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final hasAi = page.s.settings.hasAiKey;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _fillDiscussion,
              icon: const Icon(Icons.notes),
              label: const Text('Usa la trascrizione'),
            ),
            if (hasAi)
              OutlinedButton.icon(
                onPressed: _aiRunning ? null : _aiDraft,
                icon: _aiRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(_aiRunning ? 'Preparo la bozza…' : 'Bozza con IA'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        ..._header.map(_input),
        const Divider(height: 28),
        ..._body.map(_input),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: () => _export(true),
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('Word'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 54,
                child: OutlinedButton.icon(
                  onPressed: () => _export(false),
                  icon: const Icon(Icons.text_snippet_outlined),
                  label: const Text('Testo'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
