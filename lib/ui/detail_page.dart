import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../services/app_services.dart';
import '../services/library.dart';
import 'theme.dart';
import 'transcript_tab.dart';
import 'verbale_tab.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.services, required this.entry});
  final AppServices services;
  final RecordingEntry entry;

  @override
  State<DetailPage> createState() => DetailPageState();
}

class DetailPageState extends State<DetailPage> {
  AppServices get s => widget.services;
  RecordingEntry get entry => widget.entry;

  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<Object?>> _subs = [];
  Duration _position = Duration.zero;
  bool _playing = false;

  late Verbale verbale;

  /// Aumenta quando il verbale cambia da fuori dalla sua scheda.
  final ValueNotifier<int> verbaleVersion = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    verbale = entry.loadVerbale() ?? _newVerbale();
    _player.setReleaseMode(ReleaseMode.stop);
    _player.setSource(DeviceFileSource(entry.audio.path));
    _subs.add(_player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    }));
    _subs.add(_player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playing = state == PlayerState.playing);
    }));
  }

  Verbale _newVerbale() {
    final start = entry.meta.createdAt;
    return Verbale(
      ente: s.settings.text('ente'),
      tipoRiunione: s.settings.text('tipoRiunione'),
      luogo: s.settings.text('luogo'),
      presidente: s.settings.text('presidente'),
      segretario: s.settings.text('segretario'),
      data: formatDate(start),
      oraInizio: formatTime(start),
      oraFine: formatTime(start.add(entry.duration)),
    );
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _player.dispose();
    verbaleVersion.dispose();
    super.dispose();
  }

  void saveVerbale() {
    entry.saveVerbale(verbale);
    if (!entry.hasVerbale) {
      entry.hasVerbale = true;
      s.library.changed();
    }
  }

  void verbaleChangedExternally() {
    saveVerbale();
    verbaleVersion.value++;
  }

  Future<void> seekTo(int ms, {bool play = true}) async {
    await _player.seek(Duration(milliseconds: ms));
    if (play) await _player.resume();
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
    } else {
      await _player.resume();
    }
  }

  void _skip(int seconds) {
    final target = _position.inMilliseconds + seconds * 1000;
    seekTo(target.clamp(0, entry.duration.inMilliseconds), play: _playing);
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: entry.meta.title);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rinomina'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Salva')),
        ],
      ),
    );
    if (result != null) setState(() => s.library.rename(entry, result));
  }

  Future<void> _delete() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (s.transcriber.isFor(entry)) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Ferma prima la trascrizione di questa registrazione.'),
      ));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare la registrazione?'),
        content: const Text('Audio, trascrizione e verbale verranno cancellati definitivamente.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina')),
        ],
      ),
    );
    if (ok != true) return;
    await _player.stop();
    s.library.delete(entry);
    navigator.pop();
  }

  Future<void> _shareAudio() async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile(entry.audio.path, mimeType: 'audio/wav')],
      fileNameOverrides: ['${safeFileName(entry.meta.title)}.wav'],
      title: entry.meta.title,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final total = entry.duration;
    final totalMs = total.inMilliseconds.toDouble();
    final position = _position.inMilliseconds.toDouble().clamp(0.0, totalMs);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(entry.meta.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(fontSize: 18),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'rename') _rename();
                if (v == 'share') _shareAudio();
                if (v == 'delete') _delete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rinomina')),
                PopupMenuItem(value: 'share', child: Text('Condividi audio')),
                PopupMenuItem(value: 'delete', child: Text('Elimina')),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
                  child: Column(
                    children: [
                      Slider(
                        value: position,
                        max: totalMs <= 0 ? 1 : totalMs,
                        activeColor: Brand.orange,
                        onChanged: totalMs <= 0
                            ? null
                            : (v) => setState(() => _position = Duration(milliseconds: v.round())),
                        onChangeEnd: (v) => seekTo(v.round(), play: _playing),
                      ),
                      Row(
                        children: [
                          const SizedBox(width: 14),
                          Text(formatClock(_position)),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Indietro 10 secondi',
                            onPressed: () => _skip(-10),
                            icon: const Icon(Icons.replay_10),
                          ),
                          IconButton.filled(
                            tooltip: _playing ? 'Pausa' : 'Ascolta',
                            onPressed: _togglePlay,
                            icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                          ),
                          IconButton(
                            tooltip: 'Avanti 10 secondi',
                            onPressed: () => _skip(10),
                            icon: const Icon(Icons.forward_10),
                          ),
                          const Spacer(),
                          Text(formatClock(total)),
                          const SizedBox(width: 14),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const TabBar(tabs: [Tab(text: 'Trascrizione'), Tab(text: 'Verbale')]),
            Expanded(
              child: TabBarView(
                children: [
                  TranscriptTab(page: this),
                  VerbaleTab(page: this),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
