import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/transcript_text.dart';
import '../core/whisper_catalog.dart';
import 'detail_page.dart';
import 'settings_page.dart';
import 'theme.dart';

class TranscriptTab extends StatefulWidget {
  const TranscriptTab({super.key, required this.page});
  final DetailPageState page;

  @override
  State<TranscriptTab> createState() => _TranscriptTabState();
}

class _TranscriptTabState extends State<TranscriptTab>
    with AutomaticKeepAliveClientMixin {
  DetailPageState get page => widget.page;
  Transcript? _saved;
  String _query = '';
  bool _wasRunning = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _saved = page.entry.loadTranscript();
    page.s.transcriber.addListener(_onJob);
    _wasRunning = page.s.transcriber.isFor(page.entry);
  }

  @override
  void dispose() {
    page.s.transcriber.removeListener(_onJob);
    super.dispose();
  }

  void _onJob() {
    final running = page.s.transcriber.isFor(page.entry);
    if (_wasRunning && !running) {
      final error = page.s.transcriber.error;
      _saved = page.entry.loadTranscript();
      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
    }
    _wasRunning = running;
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    final s = page.s;
    final messenger = ScaffoldMessenger.of(context);
    final model = whisperById(s.settings.modelId) ?? kWhisperModels.first;
    final status = await s.native.status();
    if (status.active) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Ferma prima la registrazione in corso.'),
      ));
      return;
    }
    if (!s.models.isInstalled(model)) {
      try {
        await s.models.download(model);
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Download non riuscito: $e')));
        return;
      }
      if (!s.models.isInstalled(model)) return;
    }
    await s.transcriber.start(page.entry, model);
  }

  Future<void> _redo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trascrivere di nuovo?'),
        content: const Text('La trascrizione attuale, comprese le correzioni, verrà sostituita.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Trascrivi')),
        ],
      ),
    );
    if (ok != true) return;
    page.entry.transcriptFile.deleteSync();
    page.entry.refreshInfo();
    setState(() => _saved = null);
    await _start();
  }

  Future<void> _edit(Transcript t, Segment segment) async {
    final c = TextEditingController(text: segment.text);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(formatClock(Duration(milliseconds: segment.startMs))),
        content: TextField(controller: c, autofocus: true, maxLines: 7, minLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Salva')),
        ],
      ),
    );
    if (result == null) return;
    setState(() => segment.text = result.trim());
    page.entry.saveTranscript(t);
  }

  Future<void> _addToVerbale(Segment segment) async {
    final messenger = ScaffoldMessenger.of(context);
    final field = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Aggiungi al verbale')),
            for (final (key, label) in const [
              ('discussione', 'Discussione'),
              ('delibere', 'Delibere'),
              ('varie', 'Varie ed eventuali'),
            ])
              ListTile(title: Text(label), onTap: () => Navigator.pop(ctx, key)),
          ],
        ),
      ),
    );
    if (field == null) return;
    final v = page.verbale;
    String join(String current) =>
        current.trim().isEmpty ? segment.text : '${current.trimRight()}\n\n${segment.text}';
    switch (field) {
      case 'discussione':
        v.discussione = join(v.discussione);
      case 'delibere':
        v.delibere = join(v.delibere);
      case 'varie':
        v.varie = join(v.varie);
    }
    page.verbaleChangedExternally();
    messenger.showSnackBar(const SnackBar(content: Text('Aggiunto al verbale.')));
  }

  Future<void> _export(Transcript t) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '${safeFileName(page.entry.meta.title)} - trascrizione.txt'));
    await file.writeAsString(transcriptToText(page.entry.meta.title, t, page.entry.meta.markers));
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/plain')],
      title: page.entry.meta.title,
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = page.s;
    final job = s.transcriber;
    if (job.isFor(page.entry)) return _running(job.transcript!);
    final t = _saved;
    if (t != null && t.done) return _finished(t);
    return ListenableBuilder(
      listenable: Listenable.merge([s.models, s.settings]),
      builder: (context, _) => _startView(t),
    );
  }

  Widget _running(Transcript t) {
    final job = page.s.transcriber;
    final theme = Theme.of(context);
    final left = job.remaining;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      job.loading
                          ? 'Preparo il modello…'
                          : left == null
                              ? 'Trascrizione ${(job.progress * 100).round()}%'
                              : '${(job.progress * 100).round()}% · circa ${formatLong(left)} al termine',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  TextButton(onPressed: job.stop, child: const Text('Ferma')),
                ],
              ),
              LinearProgressIndicator(
                value: job.loading ? null : job.progress,
                color: Brand.orange,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 8),
              Text(
                'Puoi spegnere lo schermo. Se la fermi, riprende da dove era arrivata.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Expanded(child: _segmentList(t, editable: false)),
      ],
    );
  }

  Widget _finished(Transcript t) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Cerca nel testo',
                    prefixIcon: Icon(Icons.search),
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (v) => setState(() => _query = v.toLowerCase()),
                ),
              ),
              IconButton(
                tooltip: 'Esporta testo',
                icon: const Icon(Icons.ios_share),
                onPressed: () => _export(t),
              ),
              IconButton(
                tooltip: 'Trascrivi di nuovo',
                icon: const Icon(Icons.refresh),
                onPressed: _redo,
              ),
            ],
          ),
        ),
        Expanded(child: _segmentList(t, editable: true)),
      ],
    );
  }

  Widget _segmentList(Transcript t, {required bool editable}) {
    final theme = Theme.of(context);
    final items = mergeTimeline(t.segments, page.entry.meta.markers).where((item) {
      if (_query.isEmpty) return true;
      return item is Segment && item.text.toLowerCase().contains(_query);
    }).toList();
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Nessun testo da mostrare.', textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item is Marker) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.bookmark, size: 18, color: Brand.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.label,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(formatClock(Duration(milliseconds: item.ms)), style: theme.textTheme.bodySmall),
              ],
            ),
          );
        }
        final segment = item as Segment;
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: editable ? () => _edit(t, segment) : null,
          onLongPress: editable ? () => _addToVerbale(segment) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => page.seekTo(segment.startMs),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12, top: 2, bottom: 6),
                    child: Text(
                      formatClock(Duration(milliseconds: segment.startMs)),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Expanded(child: Text(segment.text, style: const TextStyle(height: 1.4))),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _startView(Transcript? partial) {
    final s = page.s;
    final theme = Theme.of(context);
    final selected = whisperById(s.settings.modelId) ?? kWhisperModels.first;
    final downloading = s.models.isBusy(selected);
    final installed = s.models.isInstalled(selected);
    final resuming = partial != null && !partial.done && partial.modelId == selected.id && partial.completedMs > 0;
    final otherJob = s.transcriber.busy;
    final String label;
    if (downloading) {
      label = 'Scarico ${((s.models.progress(selected) ?? 0) * 100).round()}%';
    } else if (!installed) {
      label = 'Scarica e trascrivi (${formatBytes(selected.totalBytes + kVadFile.bytes)})';
    } else {
      label = resuming ? 'Riprendi la trascrizione' : 'Trascrivi';
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'La trascrizione avviene sul telefono: l\'audio non viene inviato a nessuno.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        SegmentedButton<String>(
          segments: [
            for (final m in kWhisperModels) ButtonSegment(value: m.id, label: Text(m.name)),
          ],
          selected: {selected.id},
          onSelectionChanged: downloading ? null : (v) => s.settings.modelId = v.first,
        ),
        const SizedBox(height: 8),
        Text(selected.note, style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        SizedBox(
          height: 54,
          child: FilledButton(
            onPressed: downloading || otherJob ? null : _start,
            child: Text(label),
          ),
        ),
        if (downloading) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(value: s.models.progress(selected), color: Brand.orange),
          TextButton(onPressed: () => s.models.cancel(selected), child: const Text('Annulla il download')),
        ],
        if (otherJob) ...[
          const SizedBox(height: 10),
          const Text('È già in corso un\'altra trascrizione: attendi che finisca.', textAlign: TextAlign.center),
        ],
        if (resuming) ...[
          const SizedBox(height: 10),
          Text(
            'Già trascritti ${formatClock(Duration(milliseconds: partial.completedMs))} su ${formatClock(page.entry.duration)}.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 14),
        TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SettingsPage(services: s),
          )),
          child: const Text('Gestisci i modelli'),
        ),
      ],
    );
  }
}
