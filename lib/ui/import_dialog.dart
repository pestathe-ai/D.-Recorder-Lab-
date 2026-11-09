import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_services.dart';
import 'theme.dart';

/// Converte il file scelto e si chiude con true quando è pronto.
class ImportDialog extends StatefulWidget {
  const ImportDialog({
    super.key,
    required this.services,
    required this.uri,
    required this.outPath,
    required this.name,
  });

  final AppServices services;
  final String uri;
  final String outPath;
  final String name;

  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog> {
  AppServices get s => widget.services;
  Timer? _timer;
  double _progress = 0;
  String? _error;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  Future<void> _begin() async {
    await s.native.importStart(widget.uri, widget.outPath);
    await s.native.processingUpdate('Importo l\'audio', widget.name, -1);
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) => _poll());
  }

  Future<void> _poll() async {
    final status = await s.native.importStatus();
    if (!mounted) return;
    final state = status['state'] as String? ?? 'idle';
    final progress = (status['progress'] as num? ?? 0).toDouble();
    if (state == 'running') {
      setState(() => _progress = progress);
      if (++_ticks % 30 == 0) {
        await s.native.processingUpdate(
          'Importo l\'audio',
          widget.name,
          (progress * 100).round(),
        );
      }
      return;
    }
    _timer?.cancel();
    await s.native.processingStop();
    if (!mounted) return;
    if (state == 'error') {
      setState(() => _error = status['error'] as String? ?? 'Importazione non riuscita.');
      return;
    }
    Navigator.of(context).pop(state == 'done');
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(error == null ? 'Importo l\'audio' : 'Importazione non riuscita'),
        content: error != null
            ? Text(error)
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 14),
                  LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    color: Brand.orange,
                  ),
                ],
              ),
        actions: [
          if (error != null)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Chiudi'),
            )
          else
            TextButton(onPressed: s.native.importCancel, child: const Text('Annulla')),
        ],
      ),
    );
  }
}
