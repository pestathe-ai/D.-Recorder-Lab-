import 'dart:async';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../services/app_services.dart';
import '../services/library.dart';
import '../services/native_bridge.dart';
import 'detail_page.dart';
import 'recording_page.dart';
import 'settings_page.dart';
import 'theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.services});
  final AppServices services;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppServices get s => widget.services;
  Timer? _timer;
  RecorderStatus? _status;
  String _query = '';
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    final status = await s.native.status();
    if (!mounted) return;
    final wasActive = _status?.active ?? false;
    setState(() => _status = status);
    if (wasActive && !status.active) s.library.scan();
    if (status.error != null && ModalRoute.of(context)?.isCurrent == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status.error!)));
      await s.native.clearNotice();
    }
    if (status.active && !_opened) {
      _opened = true;
      _openActive(status);
    }
  }

  void _openActive(RecorderStatus status) {
    final entry = s.library.byAudioPath(status.path);
    if (entry == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecordingPage(services: s, entry: entry),
    ));
  }

  Future<void> _record() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (s.transcriber.busy) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Ferma prima la trascrizione in corso: il telefono non regge entrambe.'),
      ));
      return;
    }
    final allowed = await s.native.requestMic();
    if (!allowed) {
      messenger.showSnackBar(SnackBar(
        content: const Text('Serve il permesso del microfono per registrare.'),
        action: SnackBarAction(label: 'Apri', onPressed: s.native.openSettings),
      ));
      return;
    }
    final entry = s.library.create();
    await s.native.start(entry.audio.path);
    _opened = true;
    navigator.push(MaterialPageRoute(
      builder: (_) => RecordingPage(services: s, entry: entry),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final active = _status?.active ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('D. Recorder Lab'),
        actions: [
          IconButton(
            tooltip: 'Impostazioni',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SettingsPage(services: s),
            )),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: s.library,
        builder: (context, _) {
          final q = _query.toLowerCase();
          final items = s.library.items
              .where((e) => !(active && e.audio.path == _status?.path))
              .where((e) => e.meta.title.toLowerCase().contains(q))
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              if (s.library.items.length > 4)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Cerca una registrazione',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              if (items.isEmpty) const _Empty(),
              for (final e in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RecordingCard(
                    entry: e,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => DetailPage(services: s, entry: e),
                    )),
                  ),
                ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  "un'app Dom Studio",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: SizedBox(
          height: 60,
          child: active
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  onPressed: () => _openActive(_status!),
                  icon: const Icon(Icons.graphic_eq),
                  label: Text('In corso · ${formatClock(_status!.elapsed)}'),
                )
              : FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Brand.orange,
                    foregroundColor: Brand.ink,
                    textStyle: const TextStyle(
                      fontFamily: 'Sora',
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  onPressed: _record,
                  icon: const Icon(Icons.mic),
                  label: const Text('Registra'),
                ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 12),
      child: Column(
        children: [
          Icon(Icons.graphic_eq, size: 54, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 18),
          Text(
            'Nessuna registrazione',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Premi Registra all\'inizio della riunione: potrai spegnere lo schermo e trascrivere tutto dopo.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _RecordingCard extends StatelessWidget {
  const _RecordingCard({required this.entry, required this.onTap});
  final RecordingEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tag = entry.hasVerbale
        ? 'Verbale'
        : entry.transcribed
            ? 'Trascritta'
            : null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.meta.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${formatDate(entry.meta.createdAt)} · ${formatLong(entry.duration)} · ${formatBytes(entry.bytes)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (tag != null) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(tag, style: theme.textTheme.labelSmall),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
