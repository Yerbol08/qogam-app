import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'backend.dart';

class CivicPage {
  final List<Json> items;
  final String? cursor;
  final bool hasMore;
  CivicPage.fromJson(Json json)
    : items = (json['items'] as List).cast<Json>(),
      cursor = json['next_cursor'],
      hasMore = json['has_more'];
}

class CivicDraft {
  String id, city, description, title, address;
  String? category;
  List<String> mediaIds;
  double? latitude, longitude;
  bool confirmed, consent, uncertain;
  CivicDraft({
    String? id,
    this.city = 'astana',
    this.category,
    List<String>? mediaIds,
    this.description = '',
    this.title = '',
    this.address = '',
    this.latitude,
    this.longitude,
    this.confirmed = false,
    this.consent = false,
    this.uncertain = false,
  }) : id = id ?? const Uuid().v4(),
       mediaIds = mediaIds ?? [];
  factory CivicDraft.fromJson(Json j) => CivicDraft(
    id: j['client_request_id'],
    city: j['city_code'],
    category: j['category_code'],
    mediaIds: (j['media_ids'] as List? ?? []).cast<String>(),
    description: j['description'],
    title: j['title'] ?? '',
    address: j['address_text'],
    latitude: (j['location']?['lat'] as num?)?.toDouble(),
    longitude: (j['location']?['lng'] as num?)?.toDouble(),
    confirmed: j['location_confirmed'],
    consent: j['publication_confirmed'],
    uncertain: j['uncertain'] ?? false,
  );
  Json payload() => {
    'client_request_id': id,
    'city_code': city,
    'category_code': category,
    'title': title.trim().isEmpty ? null : title.trim(),
    'description': description.trim(),
    'address_text': address.trim(),
    'location': {'lat': latitude, 'lng': longitude},
    'location_confirmed': confirmed,
    'publication_confirmed': consent,
    'media_ids': [...mediaIds],
  };
  Json stored() => {...payload(), 'uncertain': uncertain};
  List<String> validate(int step) => [
    if (category == null || category!.isEmpty) 'category',
    if (description.trim().runes.length < 10 ||
        description.trim().runes.length > 2000)
      'description',
    if (title.trim().runes.length > 120) 'title',
    if (step >= 1 &&
        (!confirmed ||
            address.trim().runes.length < 3 ||
            address.trim().runes.length > 300 ||
            latitude == null ||
            longitude == null ||
            !latitude!.isFinite ||
            !longitude!.isFinite ||
            latitude! < -90 ||
            latitude! > 90 ||
            longitude! < -180 ||
            longitude! > 180))
      'place',
    if (step >= 2 && !consent) 'consent',
    if (mediaIds.length > 5) 'media',
  ];
}

abstract interface class CivicRepository {
  Future<CivicPage> problems(Map<String, String?> filters);
  Future<Json> map(Map<String, String?> filters);
  Future<Json> detail(String id, {bool own = false});
  Future<CivicPage> history(String id, {bool own = false, String? cursor});
  Future<CivicPage> mine({String? cursor});
  Future<CivicPage> joined({String? cursor});
  Future<Json> join(String id, {bool undo = false});
  Future<Json> submit(CivicDraft draft);
  Future<CivicDraft?> loadDraft();
  Future<void> saveDraft(CivicDraft? draft);
}

class ServerCivicRepository implements CivicRepository {
  final QogamApi api;
  final String? ownerId;
  final SessionStore Function(String) draftStore;
  ServerCivicRepository(
    this.api, {
    this.ownerId,
    SessionStore Function(String)? draftStore,
  }) : draftStore = draftStore ?? ((key) => SecureSessionStore(key));
  String get _draftKey => 'civic.draft.${ownerId ?? api.user?.id ?? 'guest'}';
  Future<T> _read<T>(
    String path, {
    Map<String, String?> query = const {},
    bool private = false,
  }) async =>
      await api.request(
            'GET',
            path,
            query: query,
            authenticated: private || api.user != null,
          )
          as T;
  @override
  Future<CivicPage> problems(Map<String, String?> filters) async =>
      CivicPage.fromJson(await _read<Json>('/v1/problems', query: filters));
  @override
  Future<Json> map(Map<String, String?> filters) =>
      _read('/v1/problems/map', query: filters);
  @override
  Future<Json> detail(String id, {bool own = false}) => _read(
    own
        ? '/v1/me/reports/${Uri.encodeComponent(id)}'
        : '/v1/problems/${Uri.encodeComponent(id)}',
    private: own,
  );
  @override
  Future<CivicPage> history(
    String id, {
    bool own = false,
    String? cursor,
  }) async => CivicPage.fromJson(
    await _read<Json>(
      '${own ? '/v1/me/reports' : '/v1/problems'}/${Uri.encodeComponent(id)}/history',
      private: own,
      query: {'cursor': cursor},
    ),
  );
  @override
  Future<CivicPage> mine({String? cursor}) async => CivicPage.fromJson(
    await _read<Json>(
      '/v1/me/reports',
      private: true,
      query: {'cursor': cursor},
    ),
  );
  @override
  Future<CivicPage> joined({String? cursor}) async => CivicPage.fromJson(
    await _read<Json>(
      '/v1/me/joined-problems',
      private: true,
      query: {'cursor': cursor},
    ),
  );
  @override
  Future<Json> join(String id, {bool undo = false}) async =>
      await api.request(
            undo ? 'DELETE' : 'POST',
            '/v1/problems/${Uri.encodeComponent(id)}/join',
            authenticated: true,
          )
          as Json;

  Future<Json?> findSubmission(String id) async {
    try {
      return await _read<Json>(
        '/v1/me/reports/by-client-request/${Uri.encodeComponent(id)}',
        private: true,
      );
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  final Map<String, Future<Json>> _submissions = {};
  final Map<String, String> _payloads = {};
  @override
  Future<Json> submit(CivicDraft draft) {
    final existing = _submissions[draft.id];
    if (existing != null) {
      if (_payloads[draft.id] != jsonEncode(draft.payload())) {
        return Future.error(
          const ApiException(409, 'http', code: 'idempotency.payload_mismatch'),
        );
      }
      return existing;
    }
    final id = draft.id;
    _payloads[id] = jsonEncode(draft.payload());
    final future = _submit(draft);
    _submissions[draft.id] = future;
    future.then<void>(
      (_) {
        _submissions.remove(id);
        _payloads.remove(id);
      },
      onError: (Object _, StackTrace stack) {
        _submissions.remove(id);
        _payloads.remove(id);
      },
    );
    return future;
  }

  Future<Json> _submit(CivicDraft draft) async {
    if (api.user == null || (ownerId != null && api.user!.id != ownerId)) {
      throw const ApiException(401, 'session');
    }
    if (draft.validate(2).isNotEmpty) {
      throw const ApiException(422, 'validation');
    }
    final payload = draft.payload();
    if (draft.uncertain) {
      final found = await findSubmission(draft.id);
      if (found != null) {
        await saveDraft(null);
        return found;
      }
    }
    // Save the exact payload before sending: even a process crash requires lookup on restart.
    draft.uncertain = true;
    await saveDraft(CivicDraft.fromJson({...payload, 'uncertain': true}));
    try {
      final response =
          await api.request(
                'POST',
                '/v1/reports',
                body: payload,
                authenticated: true,
                idempotencyKey: payload['client_request_id'],
              )
              as Json;
      await saveDraft(null);
      return response;
    } on ApiException catch (e) {
      if (e.status >= 400 && e.status < 500 && e.status != 408) {
        draft.uncertain = false;
        await saveDraft(CivicDraft.fromJson({...payload, 'uncertain': false}));
      }
      rethrow;
    }
  }

  /// Drafts are account/origin scoped and use the same native secure storage as sessions.
  Future<void> saveDraftFor(String key, CivicDraft? draft) async {
    final store = draftStore('${api.baseUri}#$key');
    if (draft == null) {
      await store.clear();
    } else {
      await store.write(jsonEncode(draft.stored()));
    }
  }

  @override
  Future<void> saveDraft(CivicDraft? draft) => saveDraftFor(_draftKey, draft);
  @override
  Future<CivicDraft?> loadDraft() async {
    final raw = await draftStore('${api.baseUri}#$_draftKey').read();
    return raw == null ? null : CivicDraft.fromJson(jsonDecode(raw) as Json);
  }
}
