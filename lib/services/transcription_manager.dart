import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/whisper_catalog.dart';
import 'library.dart';
import 'model_store.dart';
import 'native_bridge.dart';
import 'transcription_engine.dart';

/// Gestisce una trascrizione alla volta, in un isolate separato.
/// Ogni frase viene salvata subito: se il lavoro si interrompe, riparte da lì.
class TranscriptionManager extends ChangeNotifier {
  TranscriptionManager(this._library, this._models, this._native);

  final RecordingLibrary _library;
  final ModelStore _models;
  final NativeBridge _native;

  RecordingEntry? entry;
  Transcript? transcript;
  bool loading = false;
  double progress = 0;
  Duration? remaining;
  String? error;

  Isolate? _isolate;
  ReceivePort? _port;
  DateTime _startedAt = DateTime.now();
  int _startMs = 0;
  DateTime _lastNative = DateTime.fromMillisecondsSinceEpoch(0);

  bool get busy => entry != null;
  bool isFor(RecordingEntry e) => entry?.id == e.id;

  Future<void> start(RecordingEntry e, WhisperModel model) async {
    if (busy) return;
    final saved = e.loadTranscript();
    final resume = saved != null && !saved.done && saved.modelId == model.id;
    final t = resume ? saved : Transcript(modelId: model.id);
    if (!resume) e.saveTranscript(t);

    entry = e;
    transcript = t;
    loading = true;
    error = null;
    _startMs = t.completedMs;
    progress = e.duration.inMilliseconds == 0
        ? 0
        : _startMs / e.duration.inMilliseconds;
    remaining = null;
    _startedAt = DateTime.now();
    notifyListeners();
    unawaited(_native.processingUpdate('Trascrizione in corso', e.meta.title, -1));

    final port = ReceivePort();
    _port = port;
    port.listen(_onMessage);
    _isolate = await Isolate.spawn(
      transcriptionIsolate,
      EngineRequest(
        wavPath: e.audio.path,
        encoder: _models.path(model.encoder),
        decoder: _models.path(model.decoder),
        tokens: _models.path(model.tokens),
        vad: _models.path(kVadFile),
        threads: min(4, max(1, Platform.numberOfProcessors)),
        startMs: _startMs,
        out: port.sendPort,
      ),
      debugName: 'trascrizione',
    );
  }

  void _onMessage(dynamic raw) {
    final msg = raw as Map;
    final e = entry;
    final t = transcript;
    if (e == null || t == null) return;
    switch (msg['type']) {
      case 'loaded':
        loading = false;
        _startedAt = DateTime.now();
        notifyListeners();
      case 'segment':
        final text = msg['t'] as String;
        if (text.isNotEmpty) {
          t.segments.add(Segment(
            startMs: msg['s'] as int,
            endMs: msg['e'] as int,
            text: text,
          ));
        }
        t.completedMs = msg['e'] as int;
        e.saveTranscript(t);
        _updateProgress(msg['pos'] as int);
      case 'progress':
        _updateProgress(msg['pos'] as int);
      case 'done':
        t.done = true;
        t.completedMs = e.duration.inMilliseconds;
        e.saveTranscript(t);
        e.refreshInfo();
        _library.changed();
        _finish();
      case 'error':
        error = 'La trascrizione si è fermata: ${msg['message']}';
        _finish();
    }
  }

  void _updateProgress(int pos) {
    final e = entry!;
    final total = e.duration.inMilliseconds;
    if (total == 0) return;
    progress = (pos / total).clamp(0.0, 1.0);
    final doneMs = pos - _startMs;
    final elapsed = DateTime.now().difference(_startedAt).inMilliseconds;
    if (doneMs > 20000 && elapsed > 5000) {
      remaining = Duration(milliseconds: ((total - pos) * elapsed / doneMs).round());
    }
    notifyListeners();
    final now = DateTime.now();
    if (now.difference(_lastNative).inSeconds >= 10) {
      _lastNative = now;
      final left = remaining;
      unawaited(_native.processingUpdate(
        'Trascrizione ${(progress * 100).round()}%',
        left == null ? e.meta.title : 'Tempo stimato: ${formatLong(left)}',
        (progress * 100).round(),
      ));
    }
  }

  /// Ferma il lavoro: quanto già trascritto resta salvato.
  void stop() => _finish();

  void _finish() {
    _isolate?.kill(priority: Isolate.immediate);
    _port?.close();
    _isolate = null;
    _port = null;
    entry = null;
    transcript = null;
    loading = false;
    remaining = null;
    unawaited(_native.processingStop());
    notifyListeners();
  }
}
