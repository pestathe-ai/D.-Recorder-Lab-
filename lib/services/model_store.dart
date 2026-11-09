import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/format.dart';
import '../core/whisper_catalog.dart';
import 'native_bridge.dart';

/// Scarica ed elimina i modelli di trascrizione. I download interrotti
/// riprendono da dove si erano fermati.
class ModelStore extends ChangeNotifier {
  ModelStore(this._native);
  final NativeBridge _native;

  late Directory _root;
  final Map<String, double> _progress = {};
  final Map<String, HttpClient> _clients = {};
  final Set<String> _cancelled = {};

  Future<void> init() async {
    final support = await getApplicationSupportDirectory();
    _root = Directory(p.join(support.path, 'models'));
    await _root.create(recursive: true);
  }

  String path(ModelFile f) => p.join(_root.path, f.asset);

  bool _has(ModelFile f) {
    final file = File(path(f));
    return file.existsSync() && file.lengthSync() == f.bytes;
  }

  bool isInstalled(WhisperModel m) => m.files.every(_has) && _has(kVadFile);
  bool isBusy(WhisperModel m) => _progress.containsKey(m.id);
  double? progress(WhisperModel m) => _progress[m.id];

  Future<void> download(WhisperModel m) async {
    if (isBusy(m)) return;
    _cancelled.remove(m.id);
    _progress[m.id] = 0;
    notifyListeners();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 25);
    _clients[m.id] = client;
    final total = m.totalBytes + kVadFile.bytes;
    var lastNative = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      var doneBytes = 0;
      for (final f in [...m.files, kVadFile]) {
        if (_has(f)) {
          doneBytes += f.bytes;
          continue;
        }
        await _fetch(client, m, f, (received) {
          final value = (doneBytes + received) / total;
          _progress[m.id] = value;
          notifyListeners();
          final now = DateTime.now();
          if (now.difference(lastNative).inSeconds >= 3) {
            lastNative = now;
            _native.processingUpdate(
              'Scarico il modello ${m.name}',
              '${formatBytes(doneBytes + received)} di ${formatBytes(total)}',
              (value * 100).round(),
            );
          }
        });
        doneBytes += f.bytes;
      }
    } catch (e) {
      if (!_cancelled.contains(m.id)) rethrow;
    } finally {
      client.close(force: true);
      _clients.remove(m.id);
      _progress.remove(m.id);
      await _native.processingStop();
      notifyListeners();
    }
  }

  Future<void> _fetch(
    HttpClient client,
    WhisperModel m,
    ModelFile f,
    void Function(int) onBytes,
  ) async {
    final part = File('${path(f)}.part');
    var have = part.existsSync() ? part.lengthSync() : 0;
    if (have > f.bytes) {
      part.deleteSync();
      have = 0;
    }
    final req = await client.getUrl(Uri.parse('$kModelsBaseUrl/${f.asset}'));
    if (have > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
    final res = await req.close();
    if (res.statusCode != 200 && res.statusCode != 206) {
      throw HttpException('Download non riuscito (codice ${res.statusCode})');
    }
    if (res.statusCode == 200) have = 0;
    final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
    var received = have;
    var last = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await for (final chunk in res) {
        if (_cancelled.contains(m.id)) throw const _Cancelled();
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now();
        if (now.difference(last).inMilliseconds > 200) {
          last = now;
          onBytes(received);
        }
      }
    } finally {
      await sink.close();
    }
    if (part.lengthSync() != f.bytes) {
      throw const HttpException('Download incompleto: riprova.');
    }
    part.renameSync(path(f));
  }

  void cancel(WhisperModel m) {
    _cancelled.add(m.id);
    _clients[m.id]?.close(force: true);
  }

  void delete(WhisperModel m) {
    for (final f in m.files) {
      final file = File(path(f));
      if (file.existsSync()) file.deleteSync();
    }
    notifyListeners();
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
