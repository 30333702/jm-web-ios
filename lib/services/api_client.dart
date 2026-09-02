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

  Future<Map<String, dynamic>> _requestPayload(
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
      throw ApiException(_networkErrorMessage(error));
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
    return payload;
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
  }) async {
    final payload = await _requestPayload(
      method,
      path,
      query: query,
      body: body,
    );
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
    await auth.mergeSetCookie(raw);
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

  String _networkErrorMessage(Object error) {
    final text = error.toString();
    if (text.contains('No route to host') || text.contains('errno 65')) {
      return '网络连接失败：无法到达 $baseUrl。请确认服务器地址可访问，并允许 App 的“本地网络”权限。';
    }
    if (text.contains('Connection refused') || text.contains('Connection reset')) {
      return '网络连接失败：服务器拒绝了连接，请确认服务已启动且地址可访问。';
    }
    return '网络连接失败：$text';
  }

  Future<void> login(String rawBaseUrl, String password) async {
    final normalized = AuthStore.normalize(rawBaseUrl);
    await auth.setBase(normalized);
    try {
      if (password.trim().isEmpty) {
        // 服务器未开启访问口令时，只需要记住地址即可进入。
        await auth.persist();
      } else {
        await _requestPayload('POST', '/api/auth', body: {'password': password});
        await auth.persist();
      }
    } catch (_) {
      await auth.clear();
      rethrow;
    }
  }

  Future<void> connect(String rawBaseUrl) async {
    await auth.setBase(AuthStore.normalize(rawBaseUrl));
    await auth.persist();
  }

  Future<void> loginJm(String username, String password) async {
    final payload = await _requestPayload(
      'POST',
      '/api/login',
      body: {'username': username, 'password': password},
    );
    final raw = payload['data'];
    if (raw is! Map) {
      throw ApiException('登录返回的用户资料格式异常');
    }
    await auth.persist();
    UserProfile.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<UserProfile?> fetchMe() async {
    final payload = await _requestPayload('GET', '/api/me');
    final raw = payload['user'];
    if (raw is Map) {
      return UserProfile.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  Future<void> logoutJm() async {
    try {
      await _requestPayload('POST', '/api/logout');
    } catch (_) {
      // 本地会话仍然要清理，即使服务端已离线。
    }
    await auth.removeCookie('jmw_sid');
  }

  Future<void> logout() async {
    try {
      await _requestPayload('POST', '/api/logout');
    } catch (_) {
      // 本地会话仍然要清理，即使服务端已离线。
    }
    await auth.clear();
  }

  Future<DailySignIn> fetchDaily(String userId) async {
    final data = await _request(
      'GET',
      '/api/daily',
      query: {'user_id': userId},
    );
    return DailySignIn.fromJson(_asMap(data));
  }

  Future<Map<String, dynamic>> dailyCheckIn(String userId, String dailyId) async {
    final payload = await _requestPayload(
      'POST',
      '/api/daily_chk',
      body: {'user_id': userId, 'daily_id': dailyId},
    );
    return Map<String, dynamic>.from(payload);
  }

  Future<PagedComments> fetchComments(String aid, int page) async {
    final data = await _request(
      'GET',
      '/api/comments',
      query: {'aid': aid, 'page': page},
    );
    return PagedComments.fromJson(_asMap(data));
  }

  Future<PagedComments> fetchUserComments(String uid, int page) async {
    final data = await _request(
      'GET',
      '/api/user_comments',
      query: {'uid': uid, 'page': page},
    );
    return PagedComments.fromJson(_asMap(data));
  }

  Future<void> publishComment(
    String aid,
    String content,
    String status, [
    String? commentId,
  ]) async {
    await _requestPayload(
      'POST',
      '/api/comment',
      body: {
        'aid': aid,
        'content': content,
        'status': status,
        if (commentId != null && commentId.isNotEmpty)
          'comment_id': commentId,
      },
    );
  }

  Future<void> voteComment(String commentId, {String voteType = 'up'}) async {
    await _requestPayload(
      'POST',
      '/api/comment_vote',
      body: {'comment_id': commentId, 'vote_type': voteType},
    );
  }

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

  Future<FavoritesData> fetchFavoritesData({
    String order = 'mr',
    int page = 1,
    String folderId = '0',
  }) async {
    final payload = await _requestPayload(
      'GET',
      '/api/favorites',
      query: {'o': order, 'page': page, 'folder_id': folderId},
    );
    final raw = _asMap(payload['data'] ?? payload);
    raw['scope'] = payload['scope'] ?? raw['scope'];
    return FavoritesData.fromJson(raw);
  }

  Future<void> favoriteFolder(
    String type, {
    String folderId = '',
    String folderName = '',
    String aid = '',
  }) async {
    final payload = await _requestPayload(
      'POST',
      '/api/favorite_folder',
      body: {
        'type': type,
        'folder_id': folderId,
        'folder_name': folderName,
        'aid': aid,
      },
    );
    final status = (payload['data'] is Map)
        ? _asMap(payload['data'])['status']?.toString().toLowerCase()
        : '';
    if (status != null &&
        status.isNotEmpty &&
        !['ok', 'success', 'true', '1'].contains(status)) {
      throw ApiException(
        _asMap(payload['data'])['msg']?.toString() ?? '收藏夹操作失败',
      );
    }
  }

  Future<HistoryData> fetchHistory(int page) async {
    final payload = await _requestPayload('GET', '/api/history', query: {
      'page': page,
    });
    final raw = _asMap(payload['data'] ?? payload);
    raw['scope'] = payload['scope'] ?? raw['scope'];
    return HistoryData.fromMap(raw);
  }

  Future<void> deleteHistory(String id) async {
    await _requestPayload('POST', '/api/history/delete', body: {'id': id});
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

  String avatarImageUrl(String? photo) {
    final value = (photo ?? '').trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return _proxyImageUrl(u: value);
    }
    if (value.startsWith('//')) return _proxyImageUrl(u: 'https:$value');
    if (value.startsWith('/')) return _proxyImageUrl(path: value);
    return _proxyImageUrl(path: '/$value');
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
