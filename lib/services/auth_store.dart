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
      (_baseUrl?.isNotEmpty ?? false);

  bool get hasJmSession => _cookie?.contains('jmw_sid=') ?? false;

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

  Future<void> mergeSetCookie(String rawSetCookie) async {
    final cookies = _cookieMap();
    final auth = RegExp(
      r'(jmw_auth|jmw_sid)=([^;,\s]+)',
      caseSensitive: false,
    ).allMatches(rawSetCookie);
    var changed = false;
    for (final match in auth) {
      final name = match.group(1)!.toLowerCase();
      final value = match.group(2) ?? '';
      if (value.isEmpty) {
        if (cookies.remove(name) != null) changed = true;
      } else if (cookies[name] != value) {
        cookies[name] = value;
        changed = true;
      }
    }
    if (!changed) return;
    _cookie = cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    await _persist();
    notifyListeners();
  }

  Future<void> removeCookie(String name) async {
    final cookies = _cookieMap();
    if (cookies.remove(name.toLowerCase()) == null) return;
    _cookie = cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
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

  Map<String, String> _cookieMap() {
    final map = <String, String>{};
    if (_cookie == null) return map;
    for (final part in _cookie!.split(';')) {
      final index = part.indexOf('=');
      if (index <= 0) continue;
      final name = part.substring(0, index).trim().toLowerCase();
      final value = part.substring(index + 1).trim();
      if (name.isNotEmpty) map[name] = value;
    }
    return map;
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
