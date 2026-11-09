import 'library.dart';
import 'model_store.dart';
import 'native_bridge.dart';
import 'settings.dart';
import 'transcription_manager.dart';

class AppServices {
  AppServices._(this.native, this.library, this.models, this.settings, this.transcriber);

  static Future<AppServices> create() async {
    final native = NativeBridge();
    final status = await native.status();
    final library = RecordingLibrary();
    await library.init(activePath: status.active ? status.path : null);
    final models = ModelStore(native);
    await models.init();
    final settings = await Settings.load();
    return AppServices._(
      native,
      library,
      models,
      settings,
      TranscriptionManager(library, models, native),
    );
  }

  final NativeBridge native;
  final RecordingLibrary library;
  final ModelStore models;
  final Settings settings;
  final TranscriptionManager transcriber;
}
