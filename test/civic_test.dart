import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qogam/backend.dart';
import 'package:qogam/civic_repository.dart';
import 'package:qogam/civic_form.dart';
import 'package:qogam/civic_strings.dart';
import 'package:qogam/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qogam/domain.dart';
import 'package:qogam/ui.dart';
import 'backend_test.dart' as fixture;

CivicDraft validDraft() => CivicDraft(
  category: 'roads.pothole',
  description: 'Описание проблемы',
  address: 'Астана, Достык 13',
  latitude: 51.13,
  longitude: 71.43,
  confirmed: true,
  consent: true,
);
void main() {
  testWidgets(
    'Default server app renders real map and filtered list without demo repository',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final calls = <Uri>[];
      final api = QogamApi(
        store: fixture.MemoryStore(),
        client: MockClient((r) async {
          calls.add(r.url);
          switch (r.url.path) {
            case '/v1/categories':
              return fixture.reply([
                {
                  'code': 'roads.pothole',
                  'name': 'Яма',
                  'parent_code': 'roads',
                  'icon': 'road',
                  'sla_working_days': 15,
                },
              ]);
            case '/v1/cities':
              return fixture.reply([
                {'code': 'astana', 'name': 'Астана'},
              ]);
            case '/v1/cities/astana':
              return fixture.reply({
                'center': {'lat': 51.13, 'lng': 71.43},
                'default_zoom': 15,
                'boundary': {},
              });
            case '/v1/statuses':
              return fixture.reply({
                'statuses': [
                  {'code': 'published', 'name': 'Опубликовано'},
                ],
                'moderation_states': [],
                'workflow_states': [],
                'event_types': [],
              });
            case '/v1/problems/map':
              return fixture.reply({
                'mode': 'markers',
                'clusters': [],
                'markers': [
                  {
                    'id': 'p1',
                    'location': {'lat': 51.13, 'lng': 71.43},
                    'category_code': 'roads.pothole',
                    'status': 'published',
                    'supporters_count': 2,
                  },
                ],
                'truncated': false,
              });
            case '/v1/problems':
              return fixture.reply({
                'items': [
                  {
                    'id': 'p1',
                    'title': 'Серверная проблема',
                    'address_text': 'Адрес',
                    'status': 'published',
                    'supporters_count': 2,
                  },
                ],
                'has_more': false,
                'next_cursor': null,
              });
            case '/v1/houses':
              return fixture.reply({
                'items': [],
                'has_more': false,
                'next_cursor': null,
              });
            default:
              fail(r.url.path);
          }
        }),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        QogamApp(
          preferences: preferences,
          repository: DemoRepository(preferences),
          api: api,
          mapTilesEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      expect(find.text('Демо'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Список'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Список'));
      await tester.pumpAndSettle();
      expect(find.text('Серверная проблема'), findsOneWidget);
      expect(
        calls.any(
          (u) =>
              u.path == '/v1/problems/map' &&
              u.queryParameters.containsKey('bbox'),
        ),
        true,
      );
      expect(
        calls
            .lastWhere((u) => u.path == '/v1/problems')
            .queryParameters['bbox'],
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'Server draft validates Unicode, point, category and separate consent',
    () {
      final d = validDraft();
      expect(d.validate(2), isEmpty);
      d.description = '😀' * 10;
      expect(d.validate(2), isEmpty);
      d.description = '😀' * 9;
      expect(d.validate(2), contains('description'));
      d.description = 'a' * 2001;
      expect(d.validate(2), contains('description'));
      d.description = '0123456789';
      d.latitude = double.nan;
      expect(d.validate(2), contains('place'));
      d.latitude = 51;
      d.category = null;
      d.consent = false;
      expect(d.validate(2), containsAll(['category', 'consent']));
      expect(CivicStrings.ru.keys.toSet(), CivicStrings.kk.keys.toSet());
    },
  );
  test(
    'Draft survives restart and is isolated by account and server origin',
    () async {
      final stores = <String, fixture.MemoryStore>{};
      SessionStore storage(String key) =>
          stores.putIfAbsent(key, fixture.MemoryStore.new);
      final api = QogamApi(store: fixture.MemoryStore());
      addTearDown(api.dispose);
      final a = ServerCivicRepository(api, ownerId: 'a', draftStore: storage);
      final draft = validDraft();
      await a.saveDraft(draft);
      final restored = await ServerCivicRepository(
        api,
        ownerId: 'a',
        draftStore: storage,
      ).loadDraft();
      expect(restored!.stored(), draft.stored());
      expect(
        await ServerCivicRepository(
          api,
          ownerId: 'b',
          draftStore: storage,
        ).loadDraft(),
        null,
      );
      final other = QogamApi(
        baseUrl: 'https://other.example',
        store: fixture.MemoryStore(),
      );
      addTearDown(other.dispose);
      expect(
        await ServerCivicRepository(
          other,
          ownerId: 'a',
          draftStore: storage,
        ).loadDraft(),
        null,
      );
    },
  );
  test(
    'Concurrent submission sends once, preserves Idempotency-Key, clears successful draft',
    () async {
      final gate = Completer<http.Response>();
      int posts = 0;
      Json? payload;
      String? key;
      final store = fixture.MemoryStore();
      final api = QogamApi(
        store: fixture.MemoryStore(),
        client: MockClient((r) async {
          if (r.url.path.endsWith('/verify')) {
            return fixture.reply(fixture.tokens());
          }
          posts++;
          expect(r.method, 'POST');
          expect(r.url.path, '/v1/reports');
          expect(r.headers['Authorization'], 'Bearer access1');
          payload = jsonDecode(r.body) as Json;
          key = r.headers['Idempotency-Key'];
          return gate.future;
        }),
      );
      addTearDown(api.dispose);
      await fixture.login(api);
      final repo = ServerCivicRepository(
        api,
        ownerId: 'user1',
        draftStore: (_) => store,
      );
      final draft = validDraft();
      final first = repo.submit(draft), second = repo.submit(draft);
      final conflicting = CivicDraft.fromJson(draft.stored())
        ..description = 'Другое описание проблемы';
      await expectLater(
        repo.submit(conflicting),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 409)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(posts, 1);
      expect(key, draft.id);
      expect(payload!['category_code'], 'roads.pothole');
      expect((await repo.loadDraft())!.uncertain, true);
      gate.complete(
        fixture.reply({'id': 'report1', 'display_number': 'QG-1'}, 201),
      );
      final results = await Future.wait([first, second]);
      expect(results[0], results[1]);
      expect(await repo.loadDraft(), null);
    },
  );
  test(
    'Uncertain send looks up client ID before any retry and keeps original payload',
    () async {
      final calls = <String>[];
      int posts = 0;
      final store = fixture.MemoryStore();
      final api = QogamApi(
        store: fixture.MemoryStore(),
        client: MockClient((r) async {
          if (r.url.path.endsWith('/verify')) {
            return fixture.reply(fixture.tokens());
          }
          calls.add('${r.method} ${r.url.path}');
          if (r.method == 'POST') {
            posts++;
            throw http.ClientException('connection lost');
          }
          return fixture.reply({
            'id': 'saved-report',
            'display_number': 'QG-1',
          });
        }),
      );
      addTearDown(api.dispose);
      await fixture.login(api);
      final repo = ServerCivicRepository(
        api,
        ownerId: 'user1',
        draftStore: (_) => store,
      );
      final draft = validDraft();
      await expectLater(repo.submit(draft), throwsA(isA<ApiException>()));
      expect(draft.uncertain, true);
      final restored = (await repo.loadDraft())!;
      expect((await repo.submit(restored))['id'], 'saved-report');
      expect(posts, 1);
      expect(calls.last, 'GET /v1/me/reports/by-client-request/${draft.id}');
      expect(store.value, null);
    },
  );
  test(
    'Query values are encoded, localized errors and trace IDs are preserved',
    () async {
      final api = QogamApi(
        store: fixture.MemoryStore(),
        client: MockClient((r) async {
          expect(r.url.path, '/v1/problems');
          expect(r.url.queryParameters['q'], 'Астана & дорога');
          expect(r.headers.containsKey('Authorization'), false);
          return fixture.reply({
            'code': 'city.unavailable',
            'message': 'Город временно недоступен',
            'trace_id': 'trace-id',
          }, 503);
        }),
      );
      addTearDown(api.dispose);
      await expectLater(
        api.request('GET', '/v1/problems', query: {'q': 'Астана & дорога'}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Город временно недоступен')
              .having((e) => e.requestId, 'trace', 'trace-id'),
        ),
      );
    },
  );
  testWidgets('Server form fits compact Kazakh screen at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final api = QogamApi(store: fixture.MemoryStore());
    addTearDown(api.dispose);
    final store = fixture.MemoryStore();
    final draft = validDraft();
    await tester.pumpWidget(
      MaterialApp(
        theme: qogamTheme(),
        home: CivicForm(
          api: api,
          repository: ServerCivicRepository(
            api,
            ownerId: 'user1',
            draftStore: (_) => store,
          ),
          draft: draft,
          categories: [
            ApiCategory.fromJson({
              'code': 'roads.pothole',
              'name': 'Жолдағы шұңқыр',
              'parent_code': 'roads',
              'icon': 'road',
              'sla_working_days': 15,
            }),
          ],
          cities: [
            ApiCity.fromJson({'code': 'astana', 'name': 'Астана'}),
          ],
          s: const CivicStrings('kk'),
          tilesEnabled: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
    await tester.tap(find.widgetWithText(FilledButton, 'Жалғастыру'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
    await tester.tap(find.widgetWithText(FilledButton, 'Жалғастыру'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Three steps cannot skip point or publication confirmation; draft is saved',
    (tester) async {
      final api = QogamApi(store: fixture.MemoryStore());
      addTearDown(api.dispose);
      final store = fixture.MemoryStore();
      final repo = ServerCivicRepository(
        api,
        ownerId: 'user1',
        draftStore: (_) => store,
      );
      final draft = validDraft()..consent = false;
      const s = CivicStrings('ru');
      await tester.pumpWidget(
        MaterialApp(
          theme: qogamTheme(),
          home: CivicForm(
            api: api,
            repository: repo,
            draft: draft,
            categories: [
              ApiCategory.fromJson({
                'code': 'roads.pothole',
                'name': 'Яма',
                'parent_code': 'roads',
                'icon': 'road',
                'sla_working_days': 15,
              }),
            ],
            cities: [
              ApiCity.fromJson({'code': 'astana', 'name': 'Астана'}),
            ],
            s: s,
            tilesEnabled: false,
          ),
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Продолжить'));
      await tester.tap(find.widgetWithText(FilledButton, 'Продолжить'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, 'Адрес или ориентир'),
        findsOneWidget,
      );
      expect(await repo.loadDraft(), isNotNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Продолжить'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Отправить обращение'),
      );
      await tester.pumpAndSettle();
      expect(find.text(s.t('validation')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
