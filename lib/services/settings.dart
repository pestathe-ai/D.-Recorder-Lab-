import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Settings extends ChangeNotifier {
  Settings._(this._prefs);

  static Future<Settings> load() async =>
      Settings._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  String get modelId => _prefs.getString('model') ?? 'small';
  set modelId(String v) {
    _prefs.setString('model', v);
    notifyListeners();
  }

  String text(String key) => _prefs.getString('default_$key') ?? '';
  void setText(String key, String value) => _prefs.setString('default_$key', value);
}
