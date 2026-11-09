import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/ai_prompt.dart';

class Settings extends ChangeNotifier {
  Settings._(this._prefs);

  static Future<Settings> load() async {
    final s = Settings._(await SharedPreferences.getInstance());
    try {
      s._aiKey = await s._secure.read(key: _keyName);
    } catch (_) {
      s._aiKey = null;
    }
    return s;
  }

  static const _keyName = 'ai_key';
  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  String? _aiKey;

  String get modelId => _prefs.getString('model') ?? 'small';
  set modelId(String v) {
    _prefs.setString('model', v);
    notifyListeners();
  }

  String text(String key) => _prefs.getString('default_$key') ?? '';
  void setText(String key, String value) => _prefs.setString('default_$key', value);

  String get aiModel {
    final v = _prefs.getString('ai_model') ?? '';
    return v.trim().isEmpty ? kDefaultAiModel : v.trim();
  }

  set aiModel(String v) => _prefs.setString('ai_model', v);

  String? get aiKey => _aiKey;
  bool get hasAiKey => (_aiKey ?? '').isNotEmpty;

  Future<void> setAiKey(String key) async {
    final k = key.trim();
    if (k.isEmpty) {
      await _secure.delete(key: _keyName);
      _aiKey = null;
    } else {
      await _secure.write(key: _keyName, value: k);
      _aiKey = k;
    }
    notifyListeners();
  }
}
