import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 持久化服务器地址与服务端下发的会话 Cookie。
class AuthStore extends ChangeNotifier {
  static const _baseKey = 'jm_server_base_url';
  static const _cookieKey = 'jmw_auth';

  SharedPreferences? _prefs;
  String? _baseUrl;
  String? _cookie;

  String? get baseUrl => _baseUrl;
  String? get cookie => _cookie;

  bool get hasSession =>
      (_baseUrl?.isNotEmpty ?? false) && (_cookie?.isNotEmpty ?? false);

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _baseUrl = _prefs?.getString(_baseKey);
    _cookie = _prefs?.getString(_cookieKey);
    notifyListeners();
  }

  Future<void> setSession({
    required String baseUrl,
    required String cookie,
  }) async {
    await setBase(baseUrl);
    _cookie = cookie;
    await _persist();
    notifyListeners();
  }

  Future<void> setBase(String baseUrl) async {
    _baseUrl = normalize(baseUrl);
    notifyListeners();
  }

  Future<void> persist() => _persist();

  Future<void> setCookie(String cookie) async {
    _cookie = cookie;
    await _persist();
    notifyListeners();
  }

  Future<void> clear() async {
    _baseUrl = null;
    _cookie = null;
    await _prefs?.remove(_baseKey);
    await _prefs?.remove(_cookieKey);
    notifyListeners();
  }

  Future<void> _persist() async {
    if (_prefs == null) return;
    if (_baseUrl != null) {
      await _prefs!.setString(_baseKey, _baseUrl!);
    }
    if (_cookie != null) {
      await _prefs!.setString(_cookieKey, _cookie!);
    }
  }

  static String normalize(String input) {
    var value = input.trim();
    if (!value.contains('://') && !value.startsWith('localhost')) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
