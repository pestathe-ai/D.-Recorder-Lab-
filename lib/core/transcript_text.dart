import 'format.dart';
import 'models.dart';

final _hallucinations = RegExp(
  r'sottotitoli|amara\.org|qtss|grazie per (la visione|aver guardato)|'
  r'iscriviti al canale',
  caseSensitive: false,
);

/// Pulisce il testo di un segmento. Whisper, sui rumori o sul silenzio, a volte
/// inventa frasi tipiche dei sottotitoli: quelle vengono scartate.
String cleanSegmentText(String raw) {
  final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return '';
  if (_hallucinations.hasMatch(text) && text.length < 90) return '';
  if (!RegExp(r'[0-9A-Za-zÀ-ÿ]').hasMatch(text)) return '';
  return text;
}

/// Unisce segmenti e punti segnati in ordine di tempo.
List<Object> mergeTimeline(List<Segment> segments, List<Marker> markers) {
  final out = <Object>[];
  final sortedMarkers = [...markers]..sort((a, b) => a.ms.compareTo(b.ms));
  var m = 0;
  for (final s in segments) {
    while (m < sortedMarkers.length && sortedMarkers[m].ms <= s.startMs) {
      out.add(sortedMarkers[m++]);
    }
    out.add(s);
  }
  while (m < sortedMarkers.length) {
    out.add(sortedMarkers[m++]);
  }
  return out;
}

/// Trascrizione completa, con i tempi, per l'esportazione.
String transcriptToText(String title, Transcript t, List<Marker> markers) {
  final b = StringBuffer('$title\n\n');
  for (final item in mergeTimeline(t.segments, markers)) {
    if (item is Marker) {
      b.write('\n--- ${formatClock(Duration(milliseconds: item.ms))} '
          '${item.label} ---\n\n');
    } else if (item is Segment) {
      b.write('[${formatClock(Duration(milliseconds: item.startMs))}] '
          '${item.text}\n');
    }
  }
  return b.toString();
}

/// Trascrizione senza tempi, divisa per punti segnati: base della discussione.
String transcriptToDiscussion(Transcript t, List<Marker> markers) {
  final blocks = <String>[];
  var current = StringBuffer();
  void close() {
    final text = current.toString().trim();
    if (text.isNotEmpty) blocks.add(text);
    current = StringBuffer();
  }

  for (final item in mergeTimeline(t.segments, markers)) {
    if (item is Marker) {
      close();
      if (item.label.trim().isNotEmpty) blocks.add(item.label.trim());
    } else if (item is Segment) {
      if (current.isNotEmpty) current.write(' ');
      current.write(item.text);
    }
  }
  close();
  return blocks.join('\n\n');
}
