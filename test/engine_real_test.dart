// Prova "vera" della trascrizione: gira solo in CI con i modelli scaricati.
import 'dart:io';

import 'package:d_recorder_lab/services/transcription_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dir = Platform.environment['DREC_MODELS'];
  test('trascrive un audio italiano e riprende a metà', () {
    final m = 'whisper-base';
    List<Map<String, Object?>> run(int startMs) {
      final out = <Map<String, Object?>>[];
      runTranscription(
        'test/fixtures/verbale_it.wav',
        '$dir/$m-encoder.int8.onnx',
        '$dir/$m-decoder.int8.onnx',
        '$dir/$m-tokens.txt',
        '$dir/silero_vad.onnx',
        2,
        startMs,
        out.add,
      );
      return out;
    }

    final all = run(0);
    expect(all.first['type'], 'loaded');
    expect(all.last['type'], 'done');
    final segments = all.where((m) => m['type'] == 'segment').toList();
    final text = segments.map((s) => s['t']).join(' ').toLowerCase();
    // ignore: avoid_print
    print('DREC_RESULT $text');
    expect(segments.length, greaterThanOrEqualTo(4));
    expect(text, contains('seduta'));
    expect(text, contains('bilancio'));
    expect(segments[1]['s'] as int, inInclusiveRange(7000, 10000));

    final resumed = run(15000).where((m) => m['type'] == 'segment').toList();
    expect(resumed.length, lessThan(segments.length));
    expect(resumed.first['s'] as int, greaterThanOrEqualTo(15000));
  }, skip: dir == null ? 'DREC_MODELS non impostata' : null, timeout: const Timeout(Duration(minutes: 8)));
}
