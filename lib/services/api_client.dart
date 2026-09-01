import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'auth_store.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status, this.needAuth = false});

  final String message;
  final int? status;
  final bool needAuth;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  final AuthStore auth = AuthStore();
  final http.Client _http = http.Client();

  String get baseUrl => auth.baseUrl ?? '';

  String? get _cookie => auth.cookie;
  String? get cookie => auth.cookie;

  bool get isConfigured => auth.hasSession;

  Map<String, String> get _headers {
    final headers = <String, String>{
      'X-JMW-Data-Source': 'builtin',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    final cookie = _cookie;
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
  }) async {
    final uri = _uri(path, query);
    final headers = _headers;
    final http.Response response;
    try {
      if (method == 'GET') {
        response = await _http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 70));
      } else {
        response = await _http
            .post(
              uri,
              headers: headers,
              body: body == null ? null : jsonEncode(body),
            )
            .timeout(const Duration(seconds: 70));
      }
    } catch (error) {
      throw ApiException('网络连接失败：$error');
    }
    await _captureCookie(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(_errorMessage(response), status: response.statusCode);
    }
    final payload = _decodeJson(response);
    final code = payload['code'];
    if (code != null && int.tryParse(code.toString()) != 200) {
      final message = payload['error'] is String
          ? payload['error'] as String
          : '服务端返回错误（$code）';
      throw ApiException(
        message,
        status: response.statusCode,
        needAuth: payload['needAuth'] == true,
      );
    }
    return payload['data'];
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = auth.baseUrl ?? '';
    final normalized = base.replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse('$normalized$path');
    if (query == null || query.isEmpty) return uri;
    final params = <String, String>{
      for (final entry in query.entries) entry.key: entry.value.toString(),
    };
    return uri.replace(queryParameters: params);
  }

  Future<void> _captureCookie(http.Response response) async {
    final raw = response.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    final match = RegExp(r'jmw_auth=([^;,]+)').firstMatch(raw);
    if (match == null) return;
    final cookie = 'jmw_auth=${match.group(1)}';
    if (cookie == _cookie) return;
    await auth.setCookie(cookie);
  }

  String _errorMessage(http.Response response) {
    try {
      final payload = _decodeObject(response);
      final message = payload['error'];
      if (message is String && message.isNotEmpty) return message;
    } catch (_) {}
    return '请求失败（HTTP ${response.statusCode}）';
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{'data': decoded};
  }

  Future<void> login(String rawBaseUrl, String password) async {
    final normalized = AuthStore.normalize(rawBaseUrl);
    await auth.setBase(normalized);
    try {
      await _request('POST', '/api/auth', body: {'password': password});
      await auth.persist();
    } catch (_) {
      await auth.clear();
      rethrow;
    }
  }

  Future<void> logout() => auth.clear();

  Future<List<HomeSection>> fetchHome() async {
    final data = await _request('GET', '/api/home');
    if (data is! List) return [];
    return data
        .map((e) => HomeSection.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<PagedAlbums> fetchPromoteList(String id, int page) async {
    final data = await _request(
      'GET',
      '/api/promote_list',
      query: {'id': id, 'page': page},
    );
    return PagedAlbums.fromJson(
      data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{'content': data},
    );
  }

  Future<AlbumDetail> fetchAlbum(String id) async {
    final data = await _request('GET', '/api/album', query: {'id': id});
    return AlbumDetail.fromJson(_asMap(data));
  }

  Future<ChapterData> fetchChapter(String id) async {
    final data = await _request(
      'GET',
      '/api/chapter',
      query: {'id': id, 'shunt': 1},
    );
    return ChapterData.fromJson(_asMap(data));
  }

  Future<PagedAlbums> search(String query, String order, int page) async {
    final data = await _request(
      'GET',
      '/api/search',
      query: {'q': query, 'o': order, 'page': page},
    );
    return PagedAlbums.fromJson(_asMap(data));
  }

  Future<List<CategoryInfo>> fetchCategories() async {
    final data = await _request('GET', '/api/categories');
    if (data is List) {
      return data.map((e) => CategoryInfo.fromJson(_asMap(e))).toList();
    }
    final raw = _asMap(data)['categories'];
    if (raw is List) {
      return raw.map((e) => CategoryInfo.fromJson(_asMap(e))).toList();
    }
    return const [];
  }

  Future<List<CategoryBlock>> fetchCategoryBlocks() async {
    final data = await _request('GET', '/api/categories');
    final raw = _asMap(data)['blocks'];
    if (raw is List) {
      return raw.map((e) => CategoryBlock.fromJson(_asMap(e))).toList();
    }
    return const [];
  }

  Future<PagedAlbums> fetchCategory(
    String category,
    String order,
    int page,
  ) async {
    final data = await _request(
      'GET',
      '/api/categories_filter',
      query: {'c': category, 'o': order, 'page': page},
    );
    return PagedAlbums.fromJson(_asMap(data));
  }

  Future<WeekData> fetchWeek() async {
    final data = await _request('GET', '/api/week');
    return WeekData.fromJson(_asMap(data));
  }

  Future<PagedAlbums> fetchWeekFilter(String id, String type, int page) async {
    final data = await _request(
      'GET',
      '/api/week_filter',
      query: {'id': id, 'type': type, 'page': page},
    );
    return PagedAlbums.fromJson(_asMap(data));
  }

  Future<List<AlbumCard>> fetchFavorites() async {
    final data = await _request(
      'GET',
      '/api/favorites',
      query: {'o': 'mr', 'page': 1, 'folder_id': 0},
    );
    final Iterable list;
    if (data is List) {
      list = data;
    } else if (data is Map) {
      final raw = data['content'] ?? data['list'];
      list = raw is List ? raw : const [];
    } else {
      return const [];
    }
    if (list is! List) return const [];
    return list.map((e) => AlbumCard.fromJson(_asMap(e))).toList();
  }

  Future<void> toggleLike(String albumId, bool liked) async {
    await _request('POST', '/api/like', query: {'id': albumId});
  }

  Future<void> toggleFavorite(String albumId, bool favorite) async {
    await _request('POST', '/api/favorite', query: {'aid': albumId});
  }

  Future<Uint8List> fetchImage(String url) async {
    final uri = Uri.parse(url);
    final response = await _http
        .get(
          uri,
          headers: <String, String>{
            'Accept': 'image/*',
            'X-JMW-Data-Source': 'builtin',
            if (_cookie != null && _cookie!.isNotEmpty) 'Cookie': _cookie!,
          },
        )
        .timeout(const Duration(seconds: 70));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('图片加载失败：${response.statusCode}');
    }
    return response.bodyBytes;
  }

  String albumImageUrl(Map<String, dynamic> item) {
    final rawImage = item['image'];
    final image = rawImage is String ? rawImage.trim() : '';
    if (image.isNotEmpty) {
      if (image.startsWith('http://') || image.startsWith('https://')) {
        return _proxyImageUrl(u: image);
      }
      if (image.startsWith('//')) {
        return _proxyImageUrl(u: 'https:$image');
      }
      if (image.startsWith('/media/')) {
        return _proxyImageUrl(path: image);
      }
      if (RegExp(
        r'^[\w.-]+\.(jpg|jpeg|png|webp|gif)$',
        caseSensitive: false,
      ).hasMatch(image)) {
        return _proxyImageUrl(path: '/media/albums/$image');
      }
    }
    final rawId = item['id'] ?? item['aid'];
    final idText = rawId?.toString().trim() ?? '';
    if (RegExp(r'^\d{1,12}$').hasMatch(idText)) {
      return _proxyImageUrl(path: '/media/albums/${idText}_3x4.jpg');
    }
    return '';
  }

  String albumCoverUrl(AlbumCard album) =>
      albumImageUrl({'id': album.id, 'image': album.image});

  String chapterImageUrl(String url) {
    final value = url.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return _proxyImageUrl(u: value);
    }
    if (value.startsWith('//')) return _proxyImageUrl(u: 'https:$value');
    return _proxyImageUrl(u: value);
  }

  String _proxyImageUrl({String? path, String? u}) {
    final uri = _uri('/api/img', {'path': ?path, 'u': ?u});
    return uri.toString();
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  Map<String, dynamic> _decodeJson(http.Response response) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{'data': decoded};
  }
}
