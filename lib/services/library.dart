import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/wav.dart';

void writeJsonAtomic(File file, Map<String, dynamic> data) {
  final tmp = File('${file.path}.tmp');
  tmp.writeAsStringSync(jsonEncode(data), flush: true);
  tmp.renameSync(file.path);
}

Map<String, dynamic>? readJson(File file) {
  try {
    if (!file.existsSync()) return null;
    return Map<String, dynamic>.from(jsonDecode(file.readAsStringSync()) as Map);
  } catch (_) {
    return null;
  }
}

class RecordingEntry {
  RecordingEntry(this.dir, this.meta);

  final Directory dir;
  final RecordingMeta meta;
  int bytes = 0;
  Duration duration = Duration.zero;
  bool transcribed = false;
  bool hasVerbale = false;

  String get id => meta.id;
  File get audio => File(p.join(dir.path, 'audio.wav'));
  File get metaFile => File(p.join(dir.path, 'meta.json'));
  File get transcriptFile => File(p.join(dir.path, 'transcript.json'));
  File get verbaleFile => File(p.join(dir.path, 'verbale.json'));

  void refreshInfo() {
    bytes = audio.existsSync() ? audio.lengthSync() : 0;
    duration = wavDuration(bytes);
    final t = loadTranscript();
    transcribed = t?.done ?? false;
    hasVerbale = verbaleFile.existsSync();
  }

  void saveMeta() => writeJsonAtomic(metaFile, meta.toJson());

  Transcript? loadTranscript() {
    final j = readJson(transcriptFile);
    return j == null ? null : Transcript.fromJson(j);
  }

  void saveTranscript(Transcript t) => writeJsonAtomic(transcriptFile, t.toJson());

  Verbale? loadVerbale() {
    final j = readJson(verbaleFile);
    return j == null ? null : Verbale.fromJson(j);
  }

  void saveVerbale(Verbale v) => writeJsonAtomic(verbaleFile, v.toJson());
}

/// Archivio delle registrazioni: una cartella per ognuna.
class RecordingLibrary extends ChangeNotifier {
  late Directory root;
  List<RecordingEntry> items = [];

  Future<void> init({String? activePath}) async {
    final support = await getApplicationSupportDirectory();
    root = Directory(p.join(support.path, 'recordings'));
    await root.create(recursive: true);
    scan(activePath: activePath);
  }

  /// Rilegge l'archivio. Le registrazioni interrotte vengono riparate,
  /// tranne quella eventualmente ancora in corso.
  void scan({String? activePath}) {
    final found = <RecordingEntry>[];
    for (final d in root.listSync().whereType<Directory>()) {
      final j = readJson(File(p.join(d.path, 'meta.json')));
      if (j == null) continue;
      final entry = RecordingEntry(d, RecordingMeta.fromJson(j));
      if (entry.audio.existsSync() && entry.audio.path != activePath) {
        try {
          repairWav(entry.audio);
        } catch (_) {}
      }
      entry.refreshInfo();
      found.add(entry);
    }
    found.sort((a, b) => b.meta.createdAt.compareTo(a.meta.createdAt));
    items = found;
    notifyListeners();
  }

  RecordingEntry? byAudioPath(String? path) {
    if (path == null) return null;
    for (final e in items) {
      if (e.audio.path == path) return e;
    }
    return null;
  }

  RecordingEntry create() {
    final now = DateTime.now();
    final id = now.millisecondsSinceEpoch.toString();
    final dir = Directory(p.join(root.path, id))..createSync(recursive: true);
    final entry = RecordingEntry(
      dir,
      RecordingMeta(
        id: id,
        title: 'Riunione del ${formatDate(now)}, ${formatTime(now)}',
        createdAt: now,
      ),
    );
    entry.saveMeta();
    items = [entry, ...items];
    notifyListeners();
    return entry;
  }

  void rename(RecordingEntry e, String title) {
    final t = title.trim();
    if (t.isEmpty) return;
    e.meta.title = t;
    e.saveMeta();
    notifyListeners();
  }

  void delete(RecordingEntry e) {
    if (e.dir.existsSync()) e.dir.deleteSync(recursive: true);
    items = items.where((x) => x.id != e.id).toList();
    notifyListeners();
  }

  void changed() => notifyListeners();
}
