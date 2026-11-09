import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:d_recorder_lab/core/ai_prompt.dart';
import 'package:d_recorder_lab/core/format.dart';
import 'package:d_recorder_lab/core/models.dart';
import 'package:d_recorder_lab/core/transcript_text.dart';
import 'package:d_recorder_lab/core/verbale_document.dart';
import 'package:d_recorder_lab/core/wav.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WAV', () {
    test('ripara una registrazione interrotta', () async {
      final dir = await Directory.systemTemp.createTemp('wav');
      final f = File('${dir.path}/a.wav');
      f.writeAsBytesSync([...buildWavHeader(0), ...List.filled(32001, 7)]);
      expect(repairWav(f), isTrue);
      expect(f.lengthSync(), 44 + 32000);
      final bytes = f.readAsBytesSync();
      expect(bytes.buffer.asByteData().getUint32(40, Endian.little), 32000);
      expect(bytes.sublist(44).every((b) => b == 7), isTrue);
      expect(repairWav(f), isFalse);
      expect(wavDuration(f.lengthSync()), const Duration(seconds: 1));
    });
  });

  group('Formati', () {
    test('tempi e nomi', () {
      expect(formatClock(const Duration(hours: 1, minutes: 5, seconds: 9)), '1:05:09');
      expect(formatClock(const Duration(minutes: 5, seconds: 9)), '05:09');
      expect(formatLong(const Duration(minutes: 135)), '2 h 15 min');
      expect(safeFileName('Assemblea: 3/11?'), 'Assemblea 3 11');
    });
  });

  group('Trascrizione', () {
    test('scarta le frasi inventate sul silenzio', () {
      expect(cleanSegmentText('Sottotitoli creati dalla comunità Amara.org'), '');
      expect(cleanSegmentText('  ... '), '');
      expect(cleanSegmentText(' Il  bilancio è approvato. '), 'Il bilancio è approvato.');
    });

    test('unisce i punti segnati alla discussione', () {
      final t = Transcript(modelId: 'base', segments: [
        Segment(startMs: 0, endMs: 1000, text: 'Apertura.'),
        Segment(startMs: 5000, endMs: 6000, text: 'Si discute.'),
        Segment(startMs: 7000, endMs: 8000, text: 'Si approva.'),
      ]);
      final markers = [Marker(ms: 4000, label: 'Bilancio')];
      expect(transcriptToDiscussion(t, markers), 'Apertura.\n\nBilancio\n\nSi discute. Si approva.');
      expect(transcriptToText('X', t, markers), contains('[00:05] Si discute.'));
    });
  });

  group('Verbale', () {
    final v = Verbale(
      tipoRiunione: 'assemblea dei soci',
      ente: 'A & B <srl>',
      data: '9 novembre 2026',
      discussione: 'Primo paragrafo.\n\nSecondo paragrafo.',
    );

    test('testo con spazi da completare', () {
      final text = verbaleToText(v);
      expect(text, contains('VERBALE DI ASSEMBLEA DEI SOCI'));
      expect(text, contains('DISCUSSIONE\nPrimo paragrafo.\nSecondo paragrafo.'));
      expect(text, isNot(contains('DELIBERE')));
    });

    test('docx valido e con caratteri protetti', () {
      final out = Platform.environment['DREC_DOCX_OUT'];
      final bytes = verbaleToDocx(v);
      if (out != null) File(out).writeAsBytesSync(bytes);
      final zip = ZipDecoder().decodeBytes(bytes);
      expect(zip.files.map((f) => f.name), contains('word/document.xml'));
      final doc = utf8.decode(zip.findFile('word/document.xml')!.content);
      expect(doc, contains('A &amp; B &lt;srl&gt;'));
    });
  });

  group('IA', () {
    test('la richiesta contiene trascrizione e modello', () {
      final r = buildAiRequest(model: 'm', transcript: 'ciao', current: Verbale());
      expect(r['model'], 'm');
      expect(jsonEncode(r), contains('<trascrizione>'));
    });

    test('la bozza non cancella ciò che è già scritto', () {
      final draft = parseAiResponse({
        'content': [
          {
            'type': 'text',
            'text': 'Ecco:\n{"presenti":"Rossi","discussione":"Nuova","delibere":"Approvato"}',
          },
        ],
      });
      final v = Verbale(discussione: 'Mia');
      applyAiDraft(v, draft);
      expect(v.presenti, 'Rossi');
      expect(v.discussione, 'Mia');
      expect(v.delibere, 'Approvato');
    });

    test('risposta illeggibile', () {
      expect(
        () => parseAiResponse({
          'content': [
            {'type': 'text', 'text': 'non so'},
          ],
        }),
        throwsFormatException,
      );
    });
  });
}
