import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qogam/backend.dart';
import 'package:qogam/backend_pages.dart';
import 'package:qogam/backend_strings.dart';
import 'package:qogam/ui.dart';
import 'package:qogam/strings.dart';

class MemoryStore implements SessionStore {
  String? value;
  int writes = 0;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String data) async {
    value = data;
    writes++;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

final userJson = <String, dynamic>{
  'id': 'user1',
  'phone': '+77011234567',
  'display_name': 'Ербол',
  'locale': 'ru',
  'role': 'resident',
  'city_code': 'astana',
  'created_at': '2026-10-06T00:00:00Z',
};
Json tokens({
  String access = 'access1',
  String refresh = 'refresh1',
  int expires = 3600,
}) => {
  'access_token': access,
  'refresh_token': refresh,
  'expires_in': expires,
  'token_type': 'bearer',
  'user': userJson,
};
final placeJson = <String, dynamic>{
  'id': 'place1',
  'label': 'home',
  'location': {'lat': 51.13, 'lng': 71.43},
  'radius_m': 300,
  'created_at': '2026-10-06T00:00:00Z',
};
http.Response reply(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Future<void> login(QogamApi api) =>
    api.verifyOtp('+77011234567', '123456', '2026-10-01', {'processing'});

void main() {
  test(
    'API 0.2 consent, device removal, place patch and profile clearing',
    () async {
      final consent = {
        'purpose': 'push',
        'required': false,
        'granted': true,
        'version': 'v2',
        'granted_at': '2026-10-06T00:00:00Z',
      };
      final seen = <String>[];
      final api = QogamApi(
        store: MemoryStore(),
        client: MockClient((r) async {
          final route = '${r.method} ${r.url.path}';
          seen.add(route);
          if (r.url.path.endsWith('/otp/verify')) return reply(tokens());
          expect(r.headers['Authorization'], 'Bearer access1');
          if (route == 'GET /v1/me/consents') return reply([consent]);
          if (route == 'PUT /v1/me/consents/push') {
            expect(jsonDecode(r.body), {'granted': true, 'version': 'v2'});
            return reply([consent]);
          }
          if (route == 'DELETE /v1/me/devices') {
            expect(jsonDecode(r.body), {'push_token': 'real-token'});
            expect(r.url.query, isEmpty);
            return http.Response('', 204);
          }
          if (route == 'PATCH /v1/me/places/place1') {
            expect(jsonDecode(r.body), {
              'name': null,
              'notifications_enabled': false,
            });
            return reply({
              ...placeJson,
              'name': null,
              'address_text': 'Address',
              'city_code': 'astana',
              'notifications_enabled': false,
            });
          }
          expect(route, 'PATCH /v1/me');
          expect(jsonDecode(r.body), {'display_name': null, 'city_code': null});
          return reply({
            ...userJson,
            'display_name': null,
            'city_code': null,
            'consent_version': 'v2',
          });
        }),
      );
      addTearDown(api.dispose);
      await login(api);
      expect((await api.consents()).single.granted, true);
      expect(
        (await api.putConsent(
          'push',
          granted: true,
          version: 'v2',
        )).single.version,
        'v2',
      );
      await api.deleteDevice('real-token');
      final place = await api.patchPlace('place1', {
        'name': null,
        'notifications_enabled': false,
      });
      expect(place.notificationsEnabled, false);
      expect(place.address, 'Address');
      expect(
        (await api.patchMe(clearName: true, clearCity: true)).consentVersion,
        'v2',
      );
      expect(seen.length, 6);
      await expectLater(
        api.putConsent('processing', granted: false, version: 'v2'),
        throwsA(isA<ApiException>()),
      );
    },
  );
  test('RFC 7807 errors preserve code, fields, retry and request ID', () async {
    final api = QogamApi(
      store: MemoryStore(),
      client: MockClient(
        (r) async => reply({
          'title': 'Validation',
          'status': 422,
          'code': 'validation.failed',
          'request_id': 'trace-1',
          'retry_after': 12,
          'field_errors': [
            {'field': 'location.lat', 'code': 'invalid', 'message': 'Invalid'},
          ],
        }, 422),
      ),
    );
    addTearDown(api.dispose);
    await expectLater(
      api.meta(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'validation.failed')
            .having((e) => e.fields, 'fields', ['location.lat'])
            .having((e) => e.requestId, 'request ID', 'trace-1')
            .having((e) => e.retryAfter, 'retry', 12),
      ),
    );
  });

  test(
    'Failed logout or deletion preserves session for explicit retry',
    () async {
      final store = MemoryStore();
      final api = QogamApi(
        store: store,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/verify')) return reply(tokens());
          throw http.ClientException('offline');
        }),
      );
      addTearDown(api.dispose);
      await login(api);
      await expectLater(api.logout(), throwsA(isA<ApiException>()));
      expect(api.user?.id, 'user1');
      expect(store.value, isNotNull);
      await expectLater(api.deleteMe(), throwsA(isA<ApiException>()));
      expect(api.user?.id, 'user1');
      expect(store.value, isNotNull);
    },
  );

  testWidgets(
    'Account deletion requires confirmation; cancel sends no DELETE',
    (tester) async {
      int deleted = 0;
      final store = MemoryStore();
      final api = QogamApi(
        store: store,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/verify')) return reply(tokens());
          if (r.method == 'DELETE') {
            deleted++;
            return http.Response('', 204);
          }
          return reply(userJson);
        }),
      );
      addTearDown(api.dispose);
      await login(api);
      await tester.pumpWidget(
        MaterialApp(
          theme: qogamTheme(),
          home: Scaffold(
            body: BackendProfile(
              api: api,
              s: const Strings('ru'),
              changeLanguage: () {},
              tilesEnabled: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Удалить аккаунт'), 400);
      await tester.tap(find.text('Удалить аккаунт'));
      await tester.pumpAndSettle();
      expect(deleted, 0);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(deleted, 0);
      await tester.tap(find.text('Удалить аккаунт'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await tester.pumpAndSettle();
      expect(deleted, 1);
      expect(store.value, null);
      expect(api.user, null);
    },
  );
  testWidgets('Backend screens fit narrow Kazakh layout at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final api = QogamApi(
      store: MemoryStore(),
      client: MockClient((r) async {
        if (r.url.path.endsWith('/meta')) {
          return reply({'consent_version': 'v1', 'environment': 'test'});
        }
        if (r.url.path.endsWith('/cities')) {
          return reply([
            {'code': 'astana', 'name': 'Астана'},
          ]);
        }
        if (r.url.path.endsWith('/categories')) {
          return reply([
            {
              'code': 'roads',
              'parent_code': null,
              'name': 'Жолдар',
              'icon': 'road',
              'sla_working_days': 15,
            },
          ]);
        }
        if (r.url.path.endsWith('/verify')) return reply(tokens());
        if (r.url.path.endsWith('/consents')) {
          return reply([
            {
              'purpose': 'processing',
              'required': true,
              'granted': true,
              'version': 'v0',
              'granted_at': null,
            },
            {
              'purpose': 'push',
              'required': false,
              'granted': false,
              'version': null,
              'granted_at': null,
            },
          ]);
        }
        if (r.url.path.endsWith('/places')) return reply([placeJson]);
        if (r.url.path.endsWith('/export')) {
          return reply({
            'user': userJson,
            'consents': [],
            'places': [],
            'devices': [],
          });
        }
        return reply(userJson);
      }),
    );
    addTearDown(api.dispose);
    await login(api);
    const b = BackendStrings('kk');
    final screens = <Widget>[
      LoginPage(api: api, b: b),
      EditProfilePage(api: api, user: api.user!, b: b, onLocale: (_) {}),
      CatalogPage(api: api, b: b),
      PlacesPage(api: api, b: b, tilesEnabled: false),
      AddPlacePage(api: api, b: b, tilesEnabled: false),
      DevicePage(api: api, b: b),
      ConsentsPage(api: api, b: b),
      AddPlacePage(
        api: api,
        b: b,
        tilesEnabled: false,
        place: ApiPlace.fromJson(placeJson),
      ),
      ExportPage(api: api, b: b),
      Scaffold(
        body: BackendProfile(
          api: api,
          s: const Strings('kk'),
          changeLanguage: () {},
          tilesEnabled: false,
        ),
      ),
    ];
    for (final page in screens) {
      await tester.pumpWidget(MaterialApp(theme: qogamTheme(), home: page));
      await tester.pumpAndSettle();
      expect(tester.takeException(), null, reason: page.runtimeType.toString());
      final list = find.byType(ListView).first;
      await tester.drag(list, const Offset(0, -1600));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        null,
        reason: '${page.runtimeType} bottom',
      );
      await tester.pumpWidget(const SizedBox());
    }
  });
  test(
    'All 15 OpenAPI operations use exact paths, payloads, headers and 204 responses',
    () async {
      final calls = <String>[];
      final store = MemoryStore();
      final api = QogamApi(
        store: store,
        language: 'kk',
        client: MockClient((r) async {
          final route = '${r.method} ${r.url.path}';
          calls.add(route);
          expect(r.url.origin, 'http://10.8.0.53:8000');
          expect(r.headers['Accept-Language'], 'kk');
          if (r.url.path == '/v1/me' || r.url.path.startsWith('/v1/me/')) {
            expect(r.headers['Authorization'], startsWith('Bearer access'));
          }
          final data = r.body.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(r.body) as Json;
          switch (route) {
            case 'POST /v1/auth/otp/request':
              expect(data, {'phone': '+77011234567'});
              return http.Response('', 204);
            case 'POST /v1/auth/otp/verify':
              expect(data, {
                'phone': '+77011234567',
                'code': '123456',
                'consent_version': '2026-10-01',
                'consents': ['processing'],
              });
              return reply(tokens());
            case 'POST /v1/auth/refresh':
              expect(data, {'refresh_token': 'refresh1'});
              return reply(tokens(access: 'access2', refresh: 'refresh2'));
            case 'POST /v1/auth/logout':
              expect(data, {'refresh_token': 'refresh2'});
              return http.Response('', 204);
            case 'GET /v1/me':
              return reply(userJson);
            case 'PATCH /v1/me':
              expect(data, {'display_name': 'Житель', 'locale': 'kk'});
              return reply({...userJson, ...data});
            case 'DELETE /v1/me':
              return http.Response('', 204);
            case 'GET /v1/me/export':
              return reply({
                'user': userJson,
                'consents': [],
                'places': [placeJson],
                'devices': ['android'],
              });
            case 'PUT /v1/me/devices':
              expect(data, {'platform': 'android', 'push_token': 'test-token'});
              return http.Response('', 204);
            case 'GET /v1/me/places':
              return reply([placeJson]);
            case 'POST /v1/me/places':
              expect(data, {
                'label': 'home',
                'location': {'lat': 51.13, 'lng': 71.43},
                'radius_m': 300,
                'notifications_enabled': true,
              });
              return reply(placeJson, 201);
            case 'DELETE /v1/me/places/place1':
              return http.Response('', 204);
            case 'GET /v1/meta':
              return reply({
                'consent_version': '2026-10-01',
                'environment': 'local',
              });
            case 'GET /v1/categories':
              return reply([
                {
                  'code': 'roads.pothole',
                  'parent_code': 'roads',
                  'name': 'Жолдағы шұңқыр',
                  'icon': 'pothole',
                  'sla_working_days': 15,
                },
              ]);
            case 'GET /v1/cities':
              return reply([
                {'code': 'astana', 'name': 'Астана'},
              ]);
            default:
              fail(route);
          }
        }),
      );
      addTearDown(api.dispose);
      expect((await api.meta()).consentVersion, '2026-10-01');
      expect((await api.categories()).single.name, 'Жолдағы шұңқыр');
      expect((await api.cities()).single.code, 'astana');
      await api.requestOtp('+77011234567');
      await login(api);
      expect((await api.getMe()).name, 'Ербол');
      await api.patchMe(name: ' Житель ', locale: 'kk');
      expect(api.user!.locale, 'kk');
      expect((await api.places()).single.longitude, 71.43);
      await api.createPlace(label: 'home', latitude: 51.13, longitude: 71.43);
      await api.deletePlace('place1');
      expect((await api.exportMe())['devices'], ['android']);
      await api.putDevice(platform: 'android', token: 'test-token');
      await api.refreshSession();
      await api.logout();
      expect(store.value, null);
      await login(api);
      await api.deleteMe();
      expect(api.session, null);
      expect(store.value, null);
      expect(calls.toSet().length, 15);
    },
  );

  test(
    'Restores session, serializes concurrent requests and rotates expired token once',
    () async {
      final now = DateTime.utc(2026, 10, 6);
      final store = MemoryStore()
        ..value = ApiSession.fromTokens(
          tokens(expires: 1),
          now.subtract(const Duration(minutes: 1)),
        ).encode();
      int refreshes = 0;
      final api = QogamApi(
        store: store,
        now: () => now,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/refresh')) {
            refreshes++;
            await Future<void>.delayed(const Duration(milliseconds: 5));
            return reply(tokens(access: 'new-access', refresh: 'new-refresh'));
          }
          expect(r.headers['Authorization'], 'Bearer new-access');
          return r.url.path.endsWith('/places')
              ? reply([placeJson])
              : reply(userJson);
        }),
      );
      addTearDown(api.dispose);
      await api.restore();
      expect(api.user!.id, 'user1');
      await Future.wait<Object>([api.getMe(), api.places(), api.getMe()]);
      expect(refreshes, 1);
      expect(api.session!.refresh, 'new-refresh');
      expect(jsonDecode(store.value!)['refresh_token'], 'new-refresh');
    },
  );

  test(
    '401 refreshes and retries once; rejected retry clears session',
    () async {
      final store = MemoryStore();
      int protected = 0, refreshes = 0;
      final api = QogamApi(
        store: store,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/verify')) return reply(tokens());
          if (r.url.path.endsWith('/refresh')) {
            refreshes++;
            return reply(tokens(access: 'new', refresh: 'rotated'));
          }
          protected++;
          return reply({'detail': 'Unauthorized'}, 401);
        }),
      );
      addTearDown(api.dispose);
      await login(api);
      await expectLater(
        api.getMe(),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );
      expect(protected, 2);
      expect(refreshes, 1);
      expect(store.value, null);
      expect(api.session, null);
    },
  );

  test(
    'Uncertain refresh timeout clears token and never retries rotation',
    () async {
      final store = MemoryStore();
      int refreshes = 0;
      final api = QogamApi(
        store: store,
        timeout: const Duration(milliseconds: 5),
        client: MockClient((r) async {
          if (r.url.path.endsWith('/verify')) return reply(tokens());
          refreshes++;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return reply(tokens());
        }),
      );
      addTearDown(api.dispose);
      await login(api);
      await expectLater(
        api.refreshSession(),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', 'timeout')),
      );
      expect(store.value, null);
      await expectLater(api.getMe(), throwsA(isA<ApiException>()));
      expect(refreshes, 1);
    },
  );

  test(
    'Validation, 422 field errors, 429 retry-after, network errors and corrupt storage',
    () async {
      final store = MemoryStore()..value = '{broken';
      var mode = '422';
      int requests = 0;
      final api = QogamApi(
        store: store,
        client: MockClient((r) async {
          requests++;
          if (mode == 'network') throw http.ClientException('offline');
          if (mode == '429') {
            return http.Response('{}', 429, headers: {'retry-after': '90'});
          }
          return reply({
            'detail': [
              {
                'loc': ['body', 'phone'],
                'msg': 'invalid',
                'type': 'value_error',
              },
            ],
          }, 422);
        }),
      );
      addTearDown(api.dispose);
      await api.restore();
      expect(store.value, null);
      await expectLater(api.requestOtp('123'), throwsA(isA<ApiException>()));
      await expectLater(
        api.verifyOtp('+77011234567', '123456', 'v1', {}),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        api.createPlace(label: 'home', latitude: double.nan, longitude: 71),
        throwsA(isA<ApiException>()),
      );
      await expectLater(api.patchMe(name: ' '), throwsA(isA<ApiException>()));
      await expectLater(
        api.putDevice(platform: 'android', token: 'short'),
        throwsA(isA<ApiException>()),
      );
      expect(requests, 0);
      await expectLater(
        api.requestOtp('+77011234567'),
        throwsA(
          isA<ApiException>().having((e) => e.fields, 'fields', ['phone']),
        ),
      );
      mode = '429';
      await expectLater(
        api.meta(),
        throwsA(isA<ApiException>().having((e) => e.retryAfter, 'retry', 90)),
      );
      mode = 'network';
      await expectLater(
        api.meta(),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', 'network')),
      );
      expect(BackendStrings.ru.keys.toSet(), BackendStrings.kk.keys.toSet());
    },
  );

  testWidgets(
    'OTP screen requires explicit consent and blocks duplicate submissions',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gate = Completer<http.Response>();
      int verified = 0;
      final api = QogamApi(
        store: MemoryStore(),
        client: MockClient((r) async {
          if (r.url.path.endsWith('/meta')) {
            return reply({'consent_version': 'v1', 'environment': 'test'});
          }
          if (r.url.path.endsWith('/request')) return http.Response('', 204);
          if (r.url.path.endsWith('/verify')) {
            verified++;
            return gate.future;
          }
          fail(r.url.path);
        }),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: qogamTheme(),
          home: LoginPage(api: api, b: const BackendStrings('ru')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '+77011234567');
      await tester.ensureVisible(find.text('Получить SMS-код'));
      await tester.tap(find.text('Получить SMS-код'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '123456');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Войти'));
      await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
      await tester.pumpAndSettle();
      expect(verified, 0);
      expect(
        find.text('Подтвердите согласие на обработку данных.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byType(CheckboxListTile).first);
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Войти'));
      await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
      await tester.pump();
      expect(verified, 1);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
        null,
      );
      // Dispose the screen before completing to verify late responses are safe.
      await tester.pumpWidget(const SizedBox());
      gate.complete(reply(tokens()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
    },
  );
}
