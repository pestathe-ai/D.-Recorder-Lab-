import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/ai_prompt.dart';
import '../core/models.dart';

class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<AiDraft> requestAiDraft({
  required String apiKey,
  required String model,
  required String transcript,
  required Verbale current,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 25);
  try {
    final req = await client.postUrl(Uri.parse('https://api.anthropic.com/v1/messages'));
    req.headers.set('x-api-key', apiKey);
    req.headers.set('anthropic-version', '2023-06-01');
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode(jsonEncode(
      buildAiRequest(model: model, transcript: transcript, current: current),
    )));
    final res = await req.close().timeout(const Duration(minutes: 8));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) throw AiException(aiErrorMessage(res.statusCode));
    return parseAiResponse(Map<String, dynamic>.from(jsonDecode(body) as Map));
  } on AiException {
    rethrow;
  } on FormatException catch (e) {
    throw AiException(e.message);
  } on SocketException {
    throw AiException('Nessuna connessione a internet.');
  } on TimeoutException {
    throw AiException('Il servizio IA non ha risposto in tempo.');
  } finally {
    client.close(force: true);
  }
}
