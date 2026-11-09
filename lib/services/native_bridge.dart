import 'package:flutter/services.dart';

class RecorderStatus {
  const RecorderStatus({
    required this.state,
    required this.path,
    required this.elapsed,
    required this.level,
    required this.silenced,
    required this.error,
  });

  factory RecorderStatus.fromMap(Map<Object?, Object?> m) => RecorderStatus(
        state: m['state'] as String? ?? 'idle',
        path: m['path'] as String?,
        elapsed: Duration(milliseconds: (m['elapsedMs'] as num? ?? 0).toInt()),
        level: (m['level'] as num? ?? 0).toDouble(),
        silenced: m['silenced'] as bool? ?? false,
        error: m['error'] as String?,
      );

  final String state;
  final String? path;
  final Duration elapsed;
  final double level;
  final bool silenced;
  final String? error;

  bool get active => state != 'idle';
  bool get paused => state == 'paused';
}

/// Collegamento con il codice Android (registratore e servizi in primo piano).
class NativeBridge {
  static const _channel = MethodChannel('d_recorder/native');

  Future<bool> requestMic() async =>
      await _channel.invokeMethod<bool>('requestMic') ?? false;
  Future<void> openSettings() => _channel.invokeMethod('openSettings');
  Future<void> start(String path) => _channel.invokeMethod('start', {'path': path});
  Future<void> pause() => _channel.invokeMethod('pause');
  Future<void> resume() => _channel.invokeMethod('resume');
  Future<void> stop() => _channel.invokeMethod('stop');
  Future<void> clearNotice() => _channel.invokeMethod('clearNotice');

  Future<RecorderStatus> status() async {
    final map = await _channel.invokeMethod<Map<Object?, Object?>>('status');
    return RecorderStatus.fromMap(map ?? const {});
  }

  /// Apre il selettore di file. Null se l'utente annulla.
  Future<({String uri, String name})?> pickAudio() async {
    final map = await _channel.invokeMethod<Map<Object?, Object?>>('pickAudio');
    if (map == null) return null;
    return (uri: map['uri'] as String, name: map['name'] as String);
  }

  Future<void> importStart(String uri, String path) =>
      _channel.invokeMethod('importStart', {'uri': uri, 'path': path});
  Future<void> importCancel() => _channel.invokeMethod('importCancel');
  Future<Map<Object?, Object?>> importStatus() async =>
      await _channel.invokeMethod<Map<Object?, Object?>>('importStatus') ?? const {};

  Future<void> processingUpdate(String title, String text, int percent) =>
      _channel.invokeMethod('processingUpdate', {
        'title': title,
        'text': text,
        'percent': percent,
      });
  Future<void> processingStop() => _channel.invokeMethod('processingStop');
}
