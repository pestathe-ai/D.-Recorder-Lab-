import 'package:flutter/material.dart';

import '../core/ai_prompt.dart';
import '../core/format.dart';
import '../core/whisper_catalog.dart';
import '../services/app_services.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.services});
  final AppServices services;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppServices get s => widget.services;
  late final _key = TextEditingController(text: s.settings.aiKey ?? '');
  late final _aiModel = TextEditingController(text: s.settings.aiModel);
  bool _showKey = false;

  @override
  void dispose() {
    _key.dispose();
    _aiModel.dispose();
    super.dispose();
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      );

  Widget _defaultField(String key, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          initialValue: s.settings.text(key),
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label),
          onChanged: (v) => s.settings.setText(key, v),
        ),
      );

  Future<void> _download(WhisperModel m) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await s.models.download(m);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Download non riuscito: $e')));
    }
  }

  Widget _model(WhisperModel m) {
    final busy = s.models.isBusy(m);
    final installed = s.models.isInstalled(m);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${m.name} · ${formatBytes(m.totalBytes)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (busy)
                    TextButton(onPressed: () => s.models.cancel(m), child: const Text('Annulla'))
                  else if (installed)
                    TextButton(onPressed: () => s.models.delete(m), child: const Text('Elimina'))
                  else
                    TextButton(onPressed: () => _download(m), child: const Text('Scarica')),
                ],
              ),
              Text(m.note, style: Theme.of(context).textTheme.bodySmall),
              if (busy) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: s.models.progress(m), color: Brand.orange),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListenableBuilder(
        listenable: s.models,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            _heading('Modelli di trascrizione'),
            ...kWhisperModels.map(_model),
            _heading('Dati predefiniti del verbale'),
            _defaultField('ente', 'Ente o organizzazione'),
            _defaultField('tipoRiunione', 'Tipo di riunione'),
            _defaultField('luogo', 'Luogo'),
            _defaultField('presidente', 'Presidente'),
            _defaultField('segretario', 'Segretario'),
            _heading('Bozza con IA (facoltativa)'),
            Text(
              'Inserisci una chiave API di Anthropic per attivare il pulsante "Bozza con IA". '
              'La trascrizione viene inviata solo quando lo premi e confermi.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _key,
              obscureText: !_showKey,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Chiave API',
                suffixIcon: IconButton(
                  tooltip: _showKey ? 'Nascondi' : 'Mostra',
                  icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showKey = !_showKey),
                ),
              ),
              onChanged: s.settings.setAiKey,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _aiModel,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Modello IA',
                hintText: kDefaultAiModel,
              ),
              onChanged: (v) => s.settings.aiModel = v,
            ),
          ],
        ),
      ),
    );
  }
}
