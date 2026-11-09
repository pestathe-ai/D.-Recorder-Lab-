class ModelFile {
  const ModelFile(this.asset, this.bytes);
  final String asset;
  final int bytes;
}

class WhisperModel {
  const WhisperModel({
    required this.id,
    required this.name,
    required this.note,
    required this.encoder,
    required this.decoder,
    required this.tokens,
  });

  final String id;
  final String name;
  final String note;
  final ModelFile encoder;
  final ModelFile decoder;
  final ModelFile tokens;

  List<ModelFile> get files => [encoder, decoder, tokens];
  int get totalBytes => encoder.bytes + decoder.bytes + tokens.bytes;
}

const kModelsBaseUrl =
    'https://github.com/pestathe-ai/D.-Recorder-Lab-/releases/download/models-v1';

const kVadFile = ModelFile('silero_vad.onnx', 643854);

const kWhisperModels = [
  WhisperModel(
    id: 'small',
    name: 'Precisa',
    note: 'Consigliata per i verbali. Più lenta, sbaglia meno parole.',
    encoder: ModelFile('whisper-small-encoder.int8.onnx', 112442483),
    decoder: ModelFile('whisper-small-decoder.int8.onnx', 262226114),
    tokens: ModelFile('whisper-small-tokens.txt', 816730),
  ),
  WhisperModel(
    id: 'base',
    name: 'Veloce',
    note: 'Circa 3-4 volte più rapida, ma commette più errori.',
    encoder: ModelFile('whisper-base-encoder.int8.onnx', 29120534),
    decoder: ModelFile('whisper-base-decoder.int8.onnx', 130672026),
    tokens: ModelFile('whisper-base-tokens.txt', 816730),
  ),
];

WhisperModel? whisperById(String id) {
  for (final m in kWhisperModels) {
    if (m.id == id) return m;
  }
  return null;
}
