import 'dart:io';
import 'dart:typed_data';

const int kSampleRate = 16000;
const int kBytesPerSecond = kSampleRate * 2;
const int kWavHeaderSize = 44;

/// Intestazione WAV PCM 16 bit mono a 16 kHz.
Uint8List buildWavHeader(int dataLength) {
  final b = ByteData(kWavHeaderSize);
  void tag(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + dataLength, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, kSampleRate, Endian.little);
  b.setUint32(28, kBytesPerSecond, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  b.setUint32(40, dataLength, Endian.little);
  return b.buffer.asUint8List();
}

/// Durata dell'audio contenuto in un file creato dall'app.
Duration wavDuration(int fileLength) {
  final data = fileLength <= kWavHeaderSize ? 0 : fileLength - kWavHeaderSize;
  return Duration(milliseconds: data * 1000 ~/ kBytesPerSecond);
}

/// Sistema l'intestazione di una registrazione interrotta all'improvviso.
/// Restituisce true se il file è stato modificato.
bool repairWav(File file) {
  final length = file.lengthSync();
  if (length < kWavHeaderSize) return false;
  final raf = file.openSync(mode: FileMode.append);
  try {
    raf.setPositionSync(0);
    final current = ByteData.sublistView(raf.readSync(kWavHeaderSize));
    var data = length - kWavHeaderSize;
    data -= data % 2;
    if (current.getUint32(40, Endian.little) == data &&
        length == kWavHeaderSize + data) {
      return false;
    }
    if (length != kWavHeaderSize + data) {
      raf.truncateSync(kWavHeaderSize + data);
    }
    raf.setPositionSync(0);
    raf.writeFromSync(buildWavHeader(data));
    raf.flushSync();
    return true;
  } finally {
    raf.closeSync();
  }
}
