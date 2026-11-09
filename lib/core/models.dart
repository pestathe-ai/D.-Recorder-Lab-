/// Un punto segnato durante la registrazione (es. inizio di un argomento).
class Marker {
  Marker({required this.ms, required this.label});
  factory Marker.fromJson(Map<String, dynamic> j) =>
      Marker(ms: (j['ms'] as num).toInt(), label: j['label'] as String? ?? '');

  final int ms;
  String label;
  Map<String, dynamic> toJson() => {'ms': ms, 'label': label};
}

class RecordingMeta {
  RecordingMeta({
    required this.id,
    required this.title,
    required this.createdAt,
    this.imported = false,
    List<Marker>? markers,
  }) : markers = markers ?? [];

  factory RecordingMeta.fromJson(Map<String, dynamic> j) => RecordingMeta(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Registrazione',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        imported: j['imported'] as bool? ?? false,
        markers: [
          for (final m in (j['markers'] as List? ?? const []))
            Marker.fromJson(Map<String, dynamic>.from(m as Map)),
        ],
      );

  final String id;
  String title;
  final DateTime createdAt;

  /// True per i file importati: la data di importazione non è quella della riunione.
  final bool imported;
  final List<Marker> markers;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'imported': imported,
        'markers': [for (final m in markers) m.toJson()],
      };
}

class Segment {
  Segment({required this.startMs, required this.endMs, required this.text});
  factory Segment.fromJson(Map<String, dynamic> j) => Segment(
        startMs: (j['s'] as num).toInt(),
        endMs: (j['e'] as num).toInt(),
        text: j['t'] as String? ?? '',
      );

  final int startMs;
  final int endMs;
  String text;
  Map<String, dynamic> toJson() => {'s': startMs, 'e': endMs, 't': text};
}

class Transcript {
  Transcript({
    required this.modelId,
    List<Segment>? segments,
    this.completedMs = 0,
    this.done = false,
  }) : segments = segments ?? [];

  factory Transcript.fromJson(Map<String, dynamic> j) => Transcript(
        modelId: j['model'] as String? ?? '',
        completedMs: (j['completedMs'] as num?)?.toInt() ?? 0,
        done: j['done'] as bool? ?? false,
        segments: [
          for (final s in (j['segments'] as List? ?? const []))
            Segment.fromJson(Map<String, dynamic>.from(s as Map)),
        ],
      );

  final String modelId;
  final List<Segment> segments;

  /// Fin dove è arrivata l'analisi: serve per riprendere dopo un'interruzione.
  int completedMs;
  bool done;

  Map<String, dynamic> toJson() => {
        'model': modelId,
        'completedMs': completedMs,
        'done': done,
        'segments': [for (final s in segments) s.toJson()],
      };
}

/// Contenuto del verbale. Ogni campo è testo libero modificabile.
class Verbale {
  Verbale({
    this.ente = '',
    this.tipoRiunione = '',
    this.data = '',
    this.oraInizio = '',
    this.oraFine = '',
    this.luogo = '',
    this.presidente = '',
    this.segretario = '',
    this.presenti = '',
    this.assenti = '',
    this.ordineDelGiorno = '',
    this.discussione = '',
    this.delibere = '',
    this.varie = '',
  });

  factory Verbale.fromJson(Map<String, dynamic> j) {
    String f(String k) => j[k] as String? ?? '';
    return Verbale(
      ente: f('ente'),
      tipoRiunione: f('tipoRiunione'),
      data: f('data'),
      oraInizio: f('oraInizio'),
      oraFine: f('oraFine'),
      luogo: f('luogo'),
      presidente: f('presidente'),
      segretario: f('segretario'),
      presenti: f('presenti'),
      assenti: f('assenti'),
      ordineDelGiorno: f('ordineDelGiorno'),
      discussione: f('discussione'),
      delibere: f('delibere'),
      varie: f('varie'),
    );
  }

  String ente, tipoRiunione, data, oraInizio, oraFine, luogo, presidente,
      segretario, presenti, assenti, ordineDelGiorno, discussione, delibere,
      varie;

  Map<String, dynamic> toJson() => {
        'ente': ente,
        'tipoRiunione': tipoRiunione,
        'data': data,
        'oraInizio': oraInizio,
        'oraFine': oraFine,
        'luogo': luogo,
        'presidente': presidente,
        'segretario': segretario,
        'presenti': presenti,
        'assenti': assenti,
        'ordineDelGiorno': ordineDelGiorno,
        'discussione': discussione,
        'delibere': delibere,
        'varie': varie,
      };
}
