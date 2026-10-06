import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

typedef Json = Map<String, dynamic>;

class ApiException implements Exception {
  final int status;
  final String kind;
  final List<String> fields;
  final int? retryAfter;
  const ApiException(
    this.status,
    this.kind, {
    this.fields = const [],
    this.retryAfter,
  });
}

class ApiUser {
  final String id, locale, role;
  final String? phone, name, city;
  final DateTime createdAt;
  ApiUser.fromJson(Json j)
    : id = j['id'],
      locale = j['locale'],
      role = j['role'],
      phone = j['phone'],
      name = j['display_name'],
      city = j['city_code'],
      createdAt = DateTime.parse(j['created_at']);
}

class ApiCategory {
  final String code, name;
  final String? parent, icon;
  final int sla;
  ApiCategory.fromJson(Json j)
    : code = j['code'],
      name = j['name'],
      parent = j['parent_code'],
      icon = j['icon'],
      sla = j['sla_working_days'];
}

class ApiCity {
  final String code, name;
  ApiCity.fromJson(Json j) : code = j['code'], name = j['name'];
}

class ApiMeta {
  final String consentVersion, environment;
  ApiMeta.fromJson(Json j)
    : consentVersion = j['consent_version'],
      environment = j['environment'];
}

class ApiPlace {
  final String id, label;
  final double latitude, longitude;
  final int radius;
  final DateTime createdAt;
  ApiPlace.fromJson(Json j)
    : id = j['id'],
      label = j['label'],
      latitude = (j['location']['lat'] as num).toDouble(),
      longitude = (j['location']['lng'] as num).toDouble(),
      radius = j['radius_m'],
      createdAt = DateTime.parse(j['created_at']);
}

class ApiSession {
  final String access, refresh;
  final DateTime expiresAt;
  final ApiUser user;
  final Json _json;
  ApiSession._(
    this.access,
    this.refresh,
    this.expiresAt,
    this.user,
    this._json,
  );
  factory ApiSession.fromTokens(Json j, DateTime now) {
    final data = {
      ...j,
      'expires_at': now
          .add(Duration(seconds: j['expires_in'] as int))
          .toIso8601String(),
    };
    return ApiSession.fromStored(data);
  }
  factory ApiSession.fromStored(Json j) => ApiSession._(
    j['access_token'],
    j['refresh_token'],
    DateTime.parse(j['expires_at']),
    ApiUser.fromJson(j['user']),
    j,
  );
  String encode() => jsonEncode(_json);
  ApiSession withUser(Json user) =>
      ApiSession.fromStored({..._json, 'user': user});
}

abstract interface class SessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  final FlutterSecureStorage storage;
  final String key;
  SecureSessionStore(
    String baseUrl, {
    this.storage = const FlutterSecureStorage(),
  }) : key = 'qogam.session.${base64Url.encode(utf8.encode(baseUrl))}';
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String value) => storage.write(key: key, value: value);
  @override
  Future<void> clear() => storage.delete(key: key);
}

/// All routes from Qogam API 0.1.0. No demo fallback or logging of credentials.
class QogamApi extends ChangeNotifier {
  static const defaultBaseUrl = String.fromEnvironment(
    'QOGAM_API_URL',
    defaultValue: 'http://10.8.0.53:8000',
  );
  final Uri baseUri;
  final http.Client client;
  final SessionStore store;
  final DateTime Function() now;
  final Duration timeout;
  String language;
  ApiSession? _session;
  ApiSession? get session => _session;
  ApiUser? get user => _session?.user;
  Future<void> _tail = Future.value();
  bool _disposed = false;
  QogamApi({
    String baseUrl = defaultBaseUrl,
    required this.store,
    http.Client? client,
    this.language = 'ru',
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 15),
  }) : baseUri = Uri.parse(baseUrl),
       client = client ?? http.Client(),
       now = now ?? DateTime.now {
    if (!['http', 'https'].contains(baseUri.scheme) ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        (baseUri.path.isNotEmpty && baseUri.path != '/')) {
      throw ArgumentError(
        'Base URL must be an HTTP(S) origin without credentials or path',
      );
    }
  }
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _save(ApiSession value) async {
    await store.write(value.encode());
    _session = value;
    _changed();
  }

  Future<void> _clear() async {
    _session = null;
    _changed();
    await store.clear();
  }

  Future<void> restore() => _serial(() async {
    final raw = await store.read();
    if (raw == null) return;
    try {
      _session = ApiSession.fromStored(jsonDecode(raw) as Json);
    } on FormatException {
      await _clear();
      return;
    } on TypeError {
      await _clear();
      return;
    }
    _changed();
  });

  Future<dynamic> _send(
    String method,
    String path, {
    Json? body,
    String? token,
  }) async {
    final request = http.Request(method, baseUri.resolve(path))
      ..followRedirects = false
      ..headers['Accept'] = 'application/json'
      ..headers['Accept-Language'] = language;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    http.Response response;
    try {
      response = await (() async => http.Response.fromStream(
        await client.send(request),
      ))().timeout(timeout);
    } on TimeoutException {
      throw const ApiException(0, 'timeout');
    } on http.ClientException {
      throw const ApiException(0, 'network');
    }
    dynamic data;
    if (response.bodyBytes.isNotEmpty) {
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          throw const ApiException(0, 'invalidResponse');
        }
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final fields = <String>[];
      if (data is Map && data['detail'] is List) {
        for (final error in data['detail']) {
          if (error is Map && error['loc'] is List) {
            fields.add(
              (error['loc'] as List).where((e) => e != 'body').join('.'),
            );
          }
        }
      }
      throw ApiException(
        response.statusCode,
        'http',
        fields: fields,
        retryAfter: int.tryParse(response.headers['retry-after'] ?? ''),
      );
    }
    return data;
  }

  Future<void> _refresh() async {
    final previous = _session;
    if (previous == null) throw const ApiException(401, 'session');
    try {
      final j = await _send(
        'POST',
        '/v1/auth/refresh',
        body: {'refresh_token': previous.refresh},
      );
      await _save(ApiSession.fromTokens(j as Json, now()));
    } catch (_) {
      // A timed-out rotation may have consumed the refresh token. Never reuse it.
      await _clear();
      rethrow;
    }
  }

  Future<void> refreshSession() => _serial(_refresh);
  Future<dynamic> _authorized(String method, String path, {Json? body}) =>
      _serial(() => _authorizedUnlocked(method, path, body: body));

  Future<dynamic> _authorizedUnlocked(
    String method,
    String path, {
    Json? body,
  }) async {
    if (_session == null) throw const ApiException(401, 'session');
    bool refreshed = false;
    if (!_session!.expiresAt.isAfter(now().add(const Duration(seconds: 30)))) {
      await _refresh();
      refreshed = true;
    }
    try {
      return await _send(method, path, body: body, token: _session!.access);
    } on ApiException catch (e) {
      if (e.status != 401) rethrow;
      if (refreshed) {
        await _clear();
        rethrow;
      }
      await _refresh();
      try {
        return await _send(method, path, body: body, token: _session!.access);
      } on ApiException catch (retry) {
        if (retry.status == 401) await _clear();
        rethrow;
      }
    }
  }

  Future<ApiMeta> meta() async =>
      ApiMeta.fromJson(await _send('GET', '/v1/meta') as Json);
  Future<List<ApiCategory>> categories() async =>
      (await _send('GET', '/v1/categories') as List)
          .map((j) => ApiCategory.fromJson(j as Json))
          .toList();
  Future<List<ApiCity>> cities() async =>
      (await _send('GET', '/v1/cities') as List)
          .map((j) => ApiCity.fromJson(j as Json))
          .toList();
  Future<void> requestOtp(String phone) async {
    if (!RegExp(r'^\+77\d{9}$').hasMatch(phone)) {
      throw const ApiException(422, 'phone');
    }
    await _send('POST', '/v1/auth/otp/request', body: {'phone': phone});
  }

  Future<void> verifyOtp(
    String phone,
    String code,
    String version,
    Set<String> consents,
  ) => _serial(() async {
    if (!RegExp(r'^\+77\d{9}$').hasMatch(phone)) {
      throw const ApiException(422, 'phone');
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const ApiException(422, 'code');
    }
    if (version.isEmpty ||
        !consents.contains('processing') ||
        !consents.every(['processing', 'gov_transfer', 'push'].contains)) {
      throw const ApiException(422, 'consent');
    }
    final j = await _send(
      'POST',
      '/v1/auth/otp/verify',
      body: {
        'phone': phone,
        'code': code,
        'consent_version': version,
        'consents': consents.toList(),
      },
    );
    await _save(ApiSession.fromTokens(j as Json, now()));
  });
  Future<void> logout() => _serial(() async {
    final value = _session;
    if (value != null) {
      try {
        await _send(
          'POST',
          '/v1/auth/logout',
          body: {'refresh_token': value.refresh},
        );
      } on ApiException catch (e) {
        if (e.status != 401) rethrow;
      }
    }
    await _clear();
  });
  Future<ApiUser> getMe() => _serial(() async {
    final j = await _authorizedUnlocked('GET', '/v1/me') as Json;
    await _save(_session!.withUser(j));
    return ApiUser.fromJson(j);
  });
  Future<ApiUser> patchMe({String? name, String? locale}) async {
    if (name != null &&
        (name.trim().runes.isEmpty || name.trim().runes.length > 64)) {
      throw const ApiException(422, 'name');
    }
    if (locale != null && !['ru', 'kk', 'en'].contains(locale)) {
      throw const ApiException(422, 'locale');
    }
    return _serial(() async {
      final j =
          await _authorizedUnlocked(
                'PATCH',
                '/v1/me',
                body: {
                  if (name != null) 'display_name': name.trim(),
                  'locale': ?locale,
                },
              )
              as Json;
      await _save(_session!.withUser(j));
      return ApiUser.fromJson(j);
    });
  }

  Future<void> deleteMe() => _serial(() async {
    await _authorizedUnlocked('DELETE', '/v1/me');
    await _clear();
  });
  Future<Json> exportMe() async =>
      await _authorized('GET', '/v1/me/export') as Json;
  Future<void> putDevice({
    required String platform,
    required String token,
  }) async {
    if (!['ios', 'android'].contains(platform) ||
        token.length < 8 ||
        token.length > 512) {
      throw const ApiException(422, 'deviceValidation');
    }
    await _authorized(
      'PUT',
      '/v1/me/devices',
      body: {'platform': platform, 'push_token': token},
    );
  }

  Future<List<ApiPlace>> places() async =>
      (await _authorized('GET', '/v1/me/places') as List)
          .map((j) => ApiPlace.fromJson(j as Json))
          .toList();
  Future<ApiPlace> createPlace({
    required String label,
    required double latitude,
    required double longitude,
    int radius = 300,
  }) async {
    if (!['home', 'work', 'other'].contains(label) ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180 ||
        radius < 50 ||
        radius > 5000) {
      throw const ApiException(422, 'place');
    }
    return ApiPlace.fromJson(
      await _authorized(
            'POST',
            '/v1/me/places',
            body: {
              'label': label,
              'location': {'lat': latitude, 'lng': longitude},
              'radius_m': radius,
            },
          )
          as Json,
    );
  }

  Future<void> deletePlace(String id) async {
    await _authorized('DELETE', '/v1/me/places/${Uri.encodeComponent(id)}');
  }

  @override
  void dispose() {
    _disposed = true;
    client.close();
    super.dispose();
  }
}
