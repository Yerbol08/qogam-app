import 'package:http_parser/http_parser.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

typedef Json = Map<String, dynamic>;

class ApiUpload {
  final List<int> bytes;
  final String filename, clientMediaId, kind;
  const ApiUpload({
    required this.bytes,
    required this.filename,
    required this.clientMediaId,
    this.kind = 'photo',
  });
}

class ApiException implements Exception {
  final int status;
  final String kind;
  final List<String> fields;
  final int? retryAfter;
  final String? code, requestId, message;
  const ApiException(
    this.status,
    this.kind, {
    this.fields = const [],
    this.retryAfter,
    this.code,
    this.requestId,
    this.message,
  });
}

class ApiUser {
  final String id, locale, role;
  final String? phone, name, city, consentVersion;
  final DateTime createdAt;
  ApiUser.fromJson(Json j)
    : id = j['id'],
      locale = j['locale'],
      role = j['role'],
      phone = j['phone'],
      name = j['display_name'],
      city = j['city_code'],
      consentVersion = j['consent_version'],
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
  final String? name, address, city;
  final bool notificationsEnabled;
  final double latitude, longitude;
  final int radius;
  final DateTime createdAt;
  ApiPlace.fromJson(Json j)
    : id = j['id'],
      label = j['label'],
      name = j['name'],
      address = j['address_text'],
      city = j['city_code'],
      notificationsEnabled = j['notifications_enabled'] ?? true,
      latitude = (j['location']['lat'] as num).toDouble(),
      longitude = (j['location']['lng'] as num).toDouble(),
      radius = j['radius_m'],
      createdAt = DateTime.parse(j['created_at']);
}

class ApiConsent {
  final String purpose;
  final bool required, granted;
  final String? version;
  final DateTime? grantedAt;
  ApiConsent.fromJson(Json j)
    : purpose = j['purpose'],
      required = j['required'],
      granted = j['granted'],
      version = j['version'],
      grantedAt = j['granted_at'] == null
          ? null
          : DateTime.parse(j['granted_at']);
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

/// All routes from Qogam API 0.2.0. No demo fallback or logging of credentials.
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
  final String? deviceId;
  String language;
  ApiSession? _session;
  ApiSession? get session => _session;
  bool get mfa => _session?._json['mfa'] == true;
  ApiUser? get user => _session?.user;
  Future<void> _tail = Future.value();
  bool _disposed = false;
  QogamApi({
    String baseUrl = defaultBaseUrl,
    required this.store,
    http.Client? client,
    this.language = 'ru',
    this.deviceId,
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
    Map<String, String>? headers,
    ApiUpload? upload,
  }) async {
    if (upload != null &&
        (upload.bytes.isEmpty ||
            upload.bytes.length > 10 * 1024 * 1024 ||
            !['photo', 'result_photo'].contains(upload.kind))) {
      throw const ApiException(422, 'http', fields: ['file']);
    }
    final http.BaseRequest request = upload == null
        ? http.Request(method, baseUri.resolve(path))
        : (http.MultipartRequest(method, baseUri.resolve(path))
            ..fields.addAll({
              'client_media_id': upload.clientMediaId,
              'kind': upload.kind,
            })
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                upload.bytes,
                filename: upload.filename,
                contentType: MediaType(
                  'image',
                  upload.filename.toLowerCase().endsWith('.png')
                      ? 'png'
                      : upload.filename.toLowerCase().endsWith('.heic') ||
                            upload.filename.toLowerCase().endsWith('.heif')
                      ? 'heic'
                      : 'jpeg',
                ),
              ),
            ));
    request
      ..followRedirects = false
      ..headers['Accept'] = 'application/json'
      ..headers['Accept-Language'] = language;
    if (headers != null) request.headers.addAll(headers);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      (request as http.Request).body = jsonEncode(body);
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
      if (data is Map && data['field_errors'] is List) {
        for (final error in data['field_errors']) {
          if (error is Map && error['field'] is String) {
            fields.add(error['field'] as String);
          }
        }
      }
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
        retryAfter:
            int.tryParse(response.headers['retry-after'] ?? '') ??
            (data is Map ? data['retry_after'] as int? : null),
        code: data is Map ? data['code'] as String? : null,
        message: data is Map ? data['message'] as String? : null,
        requestId:
            response.headers['x-request-id'] ??
            (data is Map
                ? (data['trace_id'] ?? data['request_id']) as String?
                : null),
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
    Map<String, String>? headers,
    ApiUpload? upload,
  }) async {
    if (_session == null) throw const ApiException(401, 'session');
    bool refreshed = false;
    if (!_session!.expiresAt.isAfter(now().add(const Duration(seconds: 30)))) {
      await _refresh();
      refreshed = true;
    }
    try {
      return await _send(
        method,
        path,
        body: body,
        token: _session!.access,
        headers: headers,
        upload: upload,
      );
    } on ApiException catch (e) {
      if (e.status != 401) rethrow;
      if (refreshed) {
        await _clear();
        rethrow;
      }
      await _refresh();
      try {
        return await _send(
          method,
          path,
          body: body,
          token: _session!.access,
          headers: headers,
          upload: upload,
        );
      } on ApiException catch (retry) {
        if (retry.status == 401) await _clear();
        rethrow;
      }
    }
  }

  Future<ApiMeta> meta() async =>
      ApiMeta.fromJson(await _send('GET', '/v1/meta') as Json);

  /// Versioned JSON operations share session rotation, errors and origin restrictions.
  Future<dynamic> request(
    String method,
    String path, {
    Json? body,
    Map<String, String?> query = const {},
    bool authenticated = false,
    String? idempotencyKey,
    Map<String, String> headers = const {},
    ApiUpload? upload,
  }) {
    if (!path.startsWith('/v1/') || path.contains('?') || path.contains('#')) {
      throw ArgumentError('Expected a versioned API path');
    }
    final uri = Uri.parse(path).replace(
      queryParameters: {
        for (final entry in query.entries)
          if (entry.value != null) entry.key: entry.value!,
      },
    );
    final requestHeaders = {...headers, 'Idempotency-Key': ?idempotencyKey};
    Future<dynamic> perform() async {
      final result = authenticated
          ? await _authorizedUnlocked(
              method,
              uri.toString(),
              body: body,
              headers: requestHeaders,
              upload: upload,
            )
          : await _send(
              method,
              uri.toString(),
              body: body,
              headers: requestHeaders,
              upload: upload,
            );
      if (method == 'POST' &&
          [
            '/v1/auth/otp/verify',
            '/v1/auth/refresh',
            '/v1/auth/mfa/confirm',
          ].contains(path)) {
        await _save(ApiSession.fromTokens(result as Json, now()));
      } else if (path == '/v1/me' &&
          ['GET', 'PATCH'].contains(method) &&
          _session != null) {
        await _save(_session!.withUser(result as Json));
      } else if ((path == '/v1/me' && method == 'DELETE') ||
          path == '/v1/auth/logout') {
        await _clear();
      }
      return result;
    }

    return authenticated || path.startsWith('/v1/auth/')
        ? _serial(perform)
        : perform();
  }

  Future<List<ApiCategory>> categories() async =>
      (await _send('GET', '/v1/categories') as List)
          .map((j) => ApiCategory.fromJson(j as Json))
          .toList();
  Future<List<ApiCity>> cities() async =>
      (await _send('GET', '/v1/cities') as List)
          .map((j) => ApiCity.fromJson(j as Json))
          .toList();
  Future<int> requestOtp(String phone) async {
    if (!RegExp(r'^\+77\d{9}$').hasMatch(phone)) {
      throw const ApiException(422, 'phone');
    }
    final response = await _send(
      'POST',
      '/v1/auth/otp/request',
      body: {'phone': phone},
      headers: {'X-Device-Id': ?deviceId},
    );
    return response is Map ? response['retry_after'] as int : 60;
  }

  Future<void> verifyOtp(
    String phone,
    String code,
    String version,
    Set<String> consents, {
    String? totp,
  }) => _serial(() async {
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
        'totp': ?totp,
      },
    );
    await _save(ApiSession.fromTokens(j as Json, now()));
  });
  Future<void> logout({String? pushToken}) => _serial(() async {
    final value = _session;
    if (value != null) {
      try {
        await _send(
          'POST',
          '/v1/auth/logout',
          body: {'refresh_token': value.refresh, 'push_token': ?pushToken},
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
  Future<ApiUser> patchMe({
    String? name,
    String? locale,
    String? cityCode,
    bool clearName = false,
    bool clearCity = false,
  }) async {
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
                  if (clearName || name != null)
                    'display_name': clearName ? null : name!.trim(),
                  if (clearCity || cityCode != null)
                    'city_code': clearCity ? null : cityCode,
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
    String? name,
    String? address,
    bool notificationsEnabled = true,
  }) async {
    if ((name != null && name.runes.length > 64) ||
        (address != null && address.runes.length > 300) ||
        !['home', 'work', 'other'].contains(label) ||
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
              'name': ?name,
              'address_text': ?address,
              'notifications_enabled': notificationsEnabled,
            },
          )
          as Json,
    );
  }

  Future<List<ApiConsent>> consents() async =>
      (await _authorized('GET', '/v1/me/consents') as List)
          .map((j) => ApiConsent.fromJson(j as Json))
          .toList();
  Future<List<ApiConsent>> putConsent(
    String purpose, {
    required bool granted,
    required String version,
  }) async {
    if (!['processing', 'gov_transfer', 'push'].contains(purpose) ||
        version.isEmpty ||
        version.length > 32 ||
        (purpose == 'processing' && !granted)) {
      throw const ApiException(422, 'consent');
    }
    return (await _authorized(
              'PUT',
              '/v1/me/consents/$purpose',
              body: {'granted': granted, 'version': version},
            )
            as List)
        .map((j) => ApiConsent.fromJson(j as Json))
        .toList();
  }

  Future<void> deleteDevice(String token) async {
    if (token.length < 8 || token.length > 512) {
      throw const ApiException(422, 'deviceValidation');
    }
    await _authorized('DELETE', '/v1/me/devices', body: {'push_token': token});
  }

  Future<ApiPlace> patchPlace(String id, Json changes) async {
    const allowed = [
      'label',
      'name',
      'address_text',
      'location',
      'radius_m',
      'notifications_enabled',
    ];
    if (changes.keys.any((k) => !allowed.contains(k))) {
      throw const ApiException(422, 'place');
    }
    return ApiPlace.fromJson(
      await _authorized(
            'PATCH',
            '/v1/me/places/${Uri.encodeComponent(id)}',
            body: changes,
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
