import 'dart:async';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../services/app_services.dart';
import '../services/library.dart';
import '../services/native_bridge.dart';
import 'detail_page.dart';
import 'theme.dart';

class RecordingPage extends StatefulWidget {
  const RecordingPage({super.key, required this.services, required this.entry});
  final AppServices services;
  final RecordingEntry entry;

  @override
  State<RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends State<RecordingPage> {
  AppServices get s => widget.services;
  RecordingEntry get entry => widget.entry;
  Timer? _timer;
  RecorderStatus? _status;
  final List<double> _levels = List.filled(48, 0, growable: true);
  bool _finished = false;
  late final TextEditingController _title = TextEditingController(text: entry.meta.title);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 160), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    final title = _title.text.trim();
    if (!_finished && title.isNotEmpty && title != entry.meta.title) {
      entry.meta.title = title;
      entry.saveMeta();
    }
    _title.dispose();
    super.dispose();
  }

  void _saveTitle() => s.library.rename(entry, _title.text);

  Future<void> _poll() async {
    final status = await s.native.status();
    if (!mounted || _finished) return;
    if (!status.active) {
      _finished = true;
      _timer?.cancel();
      _saveTitle();
      s.library.scan();
      final fresh = s.library.items.where((e) => e.id == entry.id);
      if (fresh.isEmpty || fresh.first.bytes <= 44) {
        if (fresh.isNotEmpty) s.library.delete(fresh.first);
        if (status.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status.error!)));
          await s.native.clearNotice();
        }
        if (mounted) Navigator.of(context).pop();
        return;
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => DetailPage(services: s, entry: fresh.first),
      ));
      return;
    }
    setState(() {
      _status = status;
      _levels
        ..removeAt(0)
        ..add(status.paused ? 0 : status.level);
    });
  }

  void _mark() {
    final st = _status;
    if (st == null) return;
    final marker = Marker(
      ms: st.elapsed.inMilliseconds,
      label: 'Punto ${entry.meta.markers.length + 1}',
    );
    setState(() => entry.meta.markers.add(marker));
    entry.saveMeta();
  }

  Future<void> _renameMarker(Marker m) async {
    final c = TextEditingController(text: m.label);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nome del punto'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Salva')),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty) return;
    setState(() => m.label = result.trim());
    entry.saveMeta();
  }

  Future<void> _stop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fermare la registrazione?'),
        content: const Text('L\'audio verrà salvato nell\'archivio.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continua')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ferma e salva')),
        ],
      ),
    );
    if (ok == true) await s.native.stop();
  }

  @override
  Widget build(BuildContext context) {
    final st = _status;
    final theme = Theme.of(context);
    final paused = st?.paused ?? false;
    final elapsed = st?.elapsed ?? Duration.zero;
    return Scaffold(
      appBar: AppBar(title: Text(paused ? 'In pausa' : 'Registrazione')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Titolo'),
              ),
            ),
            if (st?.silenced ?? false)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Un\'altra app o una chiamata sta usando il microfono: in questo momento l\'audio è muto.',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            const SizedBox(height: 28),
            Text(
              formatClock(elapsed),
              style: theme.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 18),
            Semantics(
              label: 'Livello del microfono',
              child: SizedBox(
                height: 72,
                width: double.infinity,
                child: CustomPaint(
                  painter: _LevelPainter(_levels, theme.colorScheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Puoi spegnere lo schermo o cambiare app.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final m in entry.meta.markers.reversed)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.bookmark, color: Brand.orange),
                      title: Text(m.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Text(formatClock(Duration(milliseconds: m.ms))),
                      onTap: () => _renameMarker(m),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                        onPressed: st == null || paused ? null : _mark,
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text('Segna'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                        onPressed: st == null
                            ? null
                            : () => paused ? s.native.resume() : s.native.pause(),
                        icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                        label: Text(paused ? 'Riprendi' : 'Pausa'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Brand.orange,
                          foregroundColor: Brand.ink,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: st == null ? null : _stop,
                        icon: const Icon(Icons.stop),
                        label: const Text('Ferma'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelPainter extends CustomPainter {
  _LevelPainter(this.levels, this.color);
  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;
    final step = size.width / levels.length;
    final middle = size.height / 2;
    for (var i = 0; i < levels.length; i++) {
      final h = 3 + levels[i].clamp(0.0, 1.0) * (size.height / 2 - 3);
      final x = step * (i + 0.5);
      canvas.drawLine(Offset(x, middle - h), Offset(x, middle + h), paint);
    }
  }

  @override
  bool shouldRepaint(_LevelPainter old) => true;
}
