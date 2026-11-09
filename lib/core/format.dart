const _months = [
  'gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno', 'luglio',
  'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre',
];

String two(int n) => n.toString().padLeft(2, '0');

/// 1:05:09 oppure 05:09.
String formatClock(Duration d) {
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// "2 h 15 min" oppure "12 min".
String formatLong(Duration d) {
  final minutes = (d.inSeconds / 60).ceil();
  if (minutes < 60) return '$minutes min';
  final m = minutes % 60;
  return m == 0 ? '${minutes ~/ 60} h' : '${minutes ~/ 60} h $m min';
}

String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
String formatTime(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} GB';
  }
  return '${(bytes / (1024 * 1024)).round()} MB';
}

/// Nome di file sicuro su ogni sistema.
String safeFileName(String title) {
  final cleaned = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return 'registrazione';
  return cleaned.length > 60 ? cleaned.substring(0, 60).trim() : cleaned;
}
