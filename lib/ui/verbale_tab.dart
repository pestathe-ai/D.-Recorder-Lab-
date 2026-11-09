import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/chatbot.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/transcript_text.dart';
import '../core/verbale_document.dart';
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

  String _chatbotText(Transcript t) => buildChatbotPrompt(
        transcript: transcriptToText(page.entry.meta.title, t, page.entry.meta.markers),
        current: page.verbale,
      );

  Future<void> _openChatbotSheet() async {
    final t = _doneTranscript();
    if (t == null) return _needTranscript();
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Copia il testo e incollalo in un chatbot gratuito, come ChatGPT, '
                'Gemini o Claude. Poi copia la risposta, torna qui e premi '
                '"Incolla risposta".\n\n'
                'Il contenuto della riunione verrà letto dal servizio che scegli. '
                'Per i verbali riservati valuta di non usarlo.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copia il testo'),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('Invia come file'),
              subtitle: const Text('Meglio per le riunioni molto lunghe'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: _chatbotText(t)));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Copiato: ora incollalo nel chatbot.'),
      ));
    } else if (choice == 'file') {
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'Per chatbot - ${safeFileName(page.entry.meta.title)}.txt'));
      await file.writeAsString(_chatbotText(t));
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        title: page.entry.meta.title,
      ));
    }
  }

  Future<void> _pasteReply() async {
    final messenger = ScaffoldMessenger.of(context);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final fields = parseChatbotReply(data?.text ?? '');
    if (fields.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Non ci sono testi copiati. Copia prima la risposta del chatbot.'),
      ));
      return;
    }
    var replace = true;
    if (replyTouchesFilledFields(page.verbale, fields)) {
      if (!mounted) return;
      final answer = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Alcuni campi sono già compilati'),
          content: const Text('Vuoi sostituirli con la risposta del chatbot?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Solo i vuoti')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sostituisci')),
          ],
        ),
      );
      if (answer == null) return;
      replace = answer;
    }
    applyChatbotReply(page.verbale, fields, replace: replace);
    page.verbaleChangedExternally();
    messenger.showSnackBar(const SnackBar(
      content: Text('Bozza inserita: rileggila, soprattutto i punti [da verificare].'),
    ));
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
            OutlinedButton.icon(
              onPressed: _openChatbotSheet,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Riassumi con chatbot'),
            ),
            OutlinedButton.icon(
              onPressed: _pasteReply,
              icon: const Icon(Icons.content_paste),
              label: const Text('Incolla risposta'),
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
