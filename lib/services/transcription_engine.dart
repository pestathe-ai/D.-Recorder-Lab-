import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../core/transcript_text.dart';
import '../core/wav.dart';

class EngineRequest {
  EngineRequest({
    required this.wavPath,
    required this.encoder,
    required this.decoder,
    required this.tokens,
    required this.vad,
    required this.threads,
    required this.startMs,
    required this.out,
  });

  final String wavPath, encoder, decoder, tokens, vad;
  final int threads, startMs;
  final SendPort out;
}

/// Messaggi inviati dall'isolate.
/// {type: 'loaded'} · {type: 'segment', s, e, t, pos} ·
/// {type: 'progress', pos} · {type: 'done'} · {type: 'error', message}
void transcriptionIsolate(EngineRequest r) {
  try {
    runTranscription(r.wavPath, r.encoder, r.decoder, r.tokens, r.vad, r.threads,
        r.startMs, r.out.send);
  } catch (e) {
    r.out.send({'type': 'error', 'message': e.toString()});
  }
}

/// Analizza il file a blocchi: anche una registrazione di molte ore non viene
/// mai caricata tutta in memoria.
void runTranscription(
  String wavPath,
  String encoder,
  String decoder,
  String tokens,
  String vadPath,
  int threads,
  int startMs,
  void Function(Map<String, Object?>) send,
) {
  sherpa.initBindings();
  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: encoder,
          decoder: decoder,
          language: 'it',
          task: 'transcribe',
        ),
        tokens: tokens,
        numThreads: threads,
        modelType: 'whisper',
        debug: false,
      ),
    ),
  );
  final vad = sherpa.VoiceActivityDetector(
    config: sherpa.VadModelConfig(
      sileroVad: sherpa.SileroVadModelConfig(
        model: vadPath,
        minSilenceDuration: 0.5,
        minSpeechDuration: 0.25,
        maxSpeechDuration: 28,
      ),
      sampleRate: kSampleRate,
      numThreads: 1,
      debug: false,
    ),
    bufferSizeInSeconds: 90,
  );
  send({'type': 'loaded'});

  final startOffset = kWavHeaderSize + (startMs * kSampleRate ~/ 1000) * 2;
  final file = File(wavPath).openSync();

  void drain() {
    while (!vad.isEmpty()) {
      final segment = vad.front();
      final stream = recognizer.createStream();
      stream.acceptWaveform(samples: segment.samples, sampleRate: kSampleRate);
      recognizer.decode(stream);
      final text = cleanSegmentText(recognizer.getResult(stream).text);
      stream.free();
      final begin = startMs + segment.start * 1000 ~/ kSampleRate;
      final end = begin + segment.samples.length * 1000 ~/ kSampleRate;
      send({'type': 'segment', 's': begin, 'e': end, 't': text, 'pos': end});
      vad.pop();
    }
  }

  try {
    file.setPositionSync(startOffset);
    const window = 512;
    final chunkBytes = window * 2 * 40;
    var position = startOffset;
    var leftover = Float32List(0);
    while (true) {
      final bytes = file.readSync(chunkBytes);
      if (bytes.isEmpty) break;
      position += bytes.length;
      final evenLength = bytes.length & ~1;
      final view = ByteData.sublistView(bytes, 0, evenLength);
      final count = evenLength ~/ 2;
      final samples = Float32List(leftover.length + count);
      samples.setAll(0, leftover);
      for (var i = 0; i < count; i++) {
        samples[leftover.length + i] = view.getInt16(i * 2, Endian.little) / 32768.0;
      }
      var at = 0;
      while (at + window <= samples.length) {
        vad.acceptWaveform(Float32List.sublistView(samples, at, at + window));
        at += window;
        drain();
      }
      leftover = Float32List.fromList(Float32List.sublistView(samples, at));
      send({
        'type': 'progress',
        'pos': (position - kWavHeaderSize) * 1000 ~/ kBytesPerSecond,
      });
    }
    if (leftover.isNotEmpty) vad.acceptWaveform(leftover);
    vad.flush();
    drain();
    send({'type': 'done'});
  } finally {
    file.closeSync();
    vad.free();
    recognizer.free();
  }
}
