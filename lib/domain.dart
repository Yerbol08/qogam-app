import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum Category { roads, lighting, waste, water, yards, other }

class Draft {
  String requestId;
  Category? category;
  String description;
  String address;
  double? latitude;
  double? longitude;
  bool confirmed;
  bool consent;
  Draft({
    String? requestId,
    this.category,
    this.description = '',
    this.address = '',
    this.latitude,
    this.longitude,
    this.confirmed = false,
    this.consent = false,
  }) : requestId =
           requestId ?? DateTime.now().microsecondsSinceEpoch.toString();
  List<String> validate({int step = 2}) => [
    if (category == null) 'categoryError',
    if (description.trim().runes.length < 10 ||
        description.trim().runes.length > 2000)
      'descriptionError',
    if (step >= 1 &&
        (!confirmed ||
            address.trim().isEmpty ||
            latitude == null ||
            longitude == null ||
            !latitude!.isFinite ||
            !longitude!.isFinite ||
            latitude! < -90 ||
            latitude! > 90 ||
            longitude! < -180 ||
            longitude! > 180))
      'locationError',
    if (step >= 2 && !consent) 'consentError',
  ];
  Map<String, dynamic> toJson() => {
    'id': requestId,
    'category': category?.name,
    'description': description,
    'address': address,
    'lat': latitude,
    'lon': longitude,
    'confirmed': confirmed,
    'consent': consent,
  };
  factory Draft.fromJson(Map<String, dynamic> j) => Draft(
    requestId: j['id'],
    category: j['category'] == null
        ? null
        : Category.values.byName(j['category']),
    description: j['description'] ?? '',
    address: j['address'] ?? '',
    latitude: (j['lat'] as num?)?.toDouble(),
    longitude: (j['lon'] as num?)?.toDouble(),
    confirmed: j['confirmed'] ?? false,
    consent: j['consent'] ?? false,
  );
}

class Problem {
  final String id, title, address, status;
  final String description;
  final DateTime createdAt;
  final double? latitude, longitude;
  final Category category;
  final int supporters;
  final bool published;
  final List<String> history;
  Problem({
    required this.id,
    required this.title,
    required this.address,
    required this.category,
    this.description = '',
    DateTime? createdAt,
    this.latitude,
    this.longitude,
    this.status = 'pending',
    this.supporters = 0,
    this.published = false,
    this.history = const ['received'],
  }) : createdAt = createdAt ?? DateTime.utc(2026, 10, 5, 4);
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'address': address,
    'category': category.name,
    'status': status,
    'supporters': supporters,
    'published': published,
    'history': history,
    'description': description,
    'createdAt': createdAt.toIso8601String(),
    'lat': latitude,
    'lon': longitude,
  };
  factory Problem.fromJson(Map<String, dynamic> j) => Problem(
    id: j['id'],
    title: j['title'],
    description: j['description'] ?? '',
    latitude: (j['lat'] as num?)?.toDouble(),
    longitude: (j['lon'] as num?)?.toDouble(),
    createdAt: j['createdAt'] == null ? null : DateTime.parse(j['createdAt']),
    address: j['address'],
    category: Category.values.byName(j['category']),
    status: j['status'],
    supporters: j['supporters'],
    published: j['published'],
    history: List<String>.from(j['history']),
  );
}

abstract interface class DraftRepository {
  Future<Draft?> loadDraft();
  Future<void> saveDraft(Draft draft);
}

abstract interface class ProblemRepository {
  Future<List<Problem>> published();
  Future<List<Problem>> mine();
  Future<Set<String>> joined();
  Future<void> join(String id);
  Future<Problem> submit(Draft draft);
}

abstract interface class QogamRepository
    implements DraftRepository, ProblemRepository {}

class DemoRepository implements QogamRepository {
  final SharedPreferences preferences;
  DemoRepository(this.preferences);
  static final seeds = [
    Problem(
      id: 'DEMO-101',
      latitude: 51.1282,
      longitude: 71.4295,
      title: 'Яма у перехода',
      description:
          'Демонстрационный пример: рядом с пешеходным переходом повреждён асфальт. После дождя углубление заполняется водой, и его сложно заметить.',
      address: 'Астана, ул. Достык, 13',
      category: Category.roads,
      status: 'progress',
      supporters: 18,
      published: true,
      history: ['published', 'assigned', 'progress'],
    ),
    Problem(
      id: 'DEMO-102',
      latitude: 51.1252,
      longitude: 71.4218,
      title: 'Не горит фонарь',
      description:
          'Демонстрационный пример: фонарь у дорожки не освещает проход вечером. Просим проверить светильник и восстановить освещение.',
      address: 'Астана, ул. Сауран, 7',
      category: Category.lighting,
      status: 'published',
      supporters: 7,
      published: true,
      history: ['published'],
    ),
    Problem(
      id: 'DEMO-103',
      latitude: 51.1311,
      longitude: 71.4341,
      title: 'Убрали мусор во дворе',
      description:
          'Демонстрационный пример завершённой проблемы: мусор возле контейнерной площадки убран. Статус и история показаны для знакомства с приложением.',
      address: 'Астана, ул. Достык, 15',
      category: Category.waste,
      status: 'resolved',
      supporters: 12,
      published: true,
      history: ['published', 'progress', 'resolved'],
    ),
  ];
  Future<void> _write(String key, String value) async {
    if (!await preferences.setString(key, value)) {
      throw StateError('Storage write failed');
    }
  }

  @override
  Future<Draft?> loadDraft() async {
    final value = preferences.getString('demo.draft');
    return value == null ? null : Draft.fromJson(jsonDecode(value));
  }

  @override
  Future<void> saveDraft(Draft draft) =>
      _write('demo.draft', jsonEncode(draft.toJson()));
  @override
  Future<List<Problem>> published() async => List.of(seeds);
  @override
  Future<List<Problem>> mine() async =>
      (jsonDecode(preferences.getString('demo.mine') ?? '[]') as List)
          .map((j) => Problem.fromJson(j))
          .toList();
  @override
  Future<Set<String>> joined() async => Set<String>.from(
    jsonDecode(preferences.getString('demo.joined') ?? '[]'),
  );
  Future<void> _queue = Future.value();
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return result;
  }

  @override
  Future<void> join(String id) => _serial(() async {
    if (!seeds.any((p) => p.id == id)) {
      throw ArgumentError('Unknown public problem');
    }
    final ids = await joined();
    ids.add(id);
    await _write('demo.joined', jsonEncode(ids.toList()));
  });
  @override
  Future<Problem> submit(Draft draft) => _serial(() async {
    if (draft.validate().isNotEmpty) {
      throw ArgumentError('Invalid draft');
    }
    final items = await mine();
    for (final item in items) {
      if (item.id == 'DEMO-${draft.requestId}') {
        if (item.description != draft.description.trim() ||
            item.address != draft.address ||
            item.category != draft.category) {
          throw StateError('Idempotency conflict');
        }
        return item;
      }
    }
    final item = Problem(
      id: 'DEMO-${draft.requestId}',
      title: String.fromCharCodes(draft.description.trim().runes.take(120)),
      description: draft.description.trim(),
      createdAt: DateTime.now().toUtc(),
      latitude: draft.latitude,
      longitude: draft.longitude,
      address: draft.address,
      category: draft.category!,
    );
    items.insert(0, item);
    await _write(
      'demo.mine',
      jsonEncode(items.map((p) => p.toJson()).toList()),
    );
    return item;
  });
}
