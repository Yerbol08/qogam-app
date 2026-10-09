import 'package:intl/date_symbol_data_local.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:qogam/media_attachments.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qogam/api_contract.dart';
import 'package:qogam/backend.dart';
import 'package:qogam/civic_repository.dart';
import 'package:qogam/service_forms.dart';
import 'package:qogam/service_pages.dart';
import 'package:qogam/service_strings.dart';
import 'package:qogam/ui.dart';
import 'backend_test.dart' as fixture;
import 'contract_test.dart' show sample, testId;

Future<QogamApi> authenticated(
  http.Client client, {
  String role = 'citizen',
  bool mfa = false,
}) async {
  final store = fixture.MemoryStore();
  await store.write(
    ApiSession.fromTokens({
      ...fixture.tokens(),
      'mfa': mfa,
      'user': {...fixture.userJson, 'role': role},
    }, DateTime.now()).encode(),
  );
  final api = QogamApi(store: store, client: client);
  await api.restore();
  return api;
}

Widget shell(Widget child) => MaterialApp(theme: qogamTheme(), home: child);
void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await initializeDateFormatting('kk');
  });
  test(
    'Staff controls require a staff role and MFA; citizens never see admin',
    () async {
      for (final role in [
        'citizen',
        'moderator',
        'org_staff',
        'org_admin',
        'platform_admin',
      ]) {
        for (final mfa in [false, true]) {
          final api = await authenticated(
            MockClient((r) async => fixture.reply({})),
            role: role,
            mfa: mfa,
          );
          expect(
            serviceVisible(
              ApiContract.operation('GET', '/v1/staff/reports'),
              api,
            ),
            mfa && ['moderator', 'platform_admin'].contains(role),
          );
          expect(
            serviceVisible(
              ApiContract.operation('GET', '/v1/admin/staff'),
              api,
            ),
            mfa && role == 'platform_admin',
          );
          expect(
            serviceVisible(
              ApiContract.operation('POST', '/v1/admin/user-restrictions'),
              api,
            ),
            mfa && ['platform_admin', 'moderator'].contains(role),
          );
          api.dispose();
        }
      }
    },
  );
  test(
    'MFA rotates the session; multipart 401 retries with identical photo and client key',
    () async {
      final bodies = <List<int>>[];
      var uploads = 0;
      final api = await authenticated(
        MockClient((r) async {
          if (r.url.path == '/v1/auth/mfa/confirm') {
            return fixture.reply({
              ...fixture.tokens(access: 'mfa-access', refresh: 'mfa-refresh'),
              'mfa': true,
            });
          }
          if (r.url.path == '/v1/auth/refresh') {
            expect(jsonDecode(r.body), {'refresh_token': 'mfa-refresh'});
            return fixture.reply({
              ...fixture.tokens(access: 'rotated'),
              'mfa': true,
            });
          }
          bodies.add(r.bodyBytes);
          final multipart = latin1.decode(r.bodyBytes);
          expect(multipart, contains('stable-photo-key'));
          expect(multipart, contains('image/png'));
          expect(multipart, contains(String.fromCharCodes([1, 2, 3, 4])));
          uploads++;
          if (uploads == 1) {
            expect(r.headers['Authorization'], 'Bearer mfa-access');
            return fixture.reply({'code': 'auth.expired', 'status': 401}, 401);
          }
          expect(r.headers['Authorization'], 'Bearer rotated');
          return fixture.reply({'media_id': testId, 'status': 'ready'}, 201);
        }),
        role: 'moderator',
      );
      addTearDown(api.dispose);
      final client = ContractApi(api);
      await client.call(
        ApiContract.operation('POST', '/v1/auth/mfa/confirm'),
        body: {'totp': '123456'},
      );
      expect(api.mfa, true);
      await client.call(
        ApiContract.operation('POST', '/v1/media'),
        upload: const ApiUpload(
          bytes: [1, 2, 3, 4],
          filename: 'photo.png',
          clientMediaId: 'stable-photo-key',
        ),
      );
      expect(uploads, 2);
      expect(bodies.every((b) => b.contains(4)), true);
    },
  );
  test(
    'Photos survive civic draft restoration and remain in the frozen submission payload',
    () {
      final draft = CivicDraft(
        category: 'roads.pothole',
        description: 'Description of the problem',
        mediaIds: [testId],
      );
      final restored = CivicDraft.fromJson(
        jsonDecode(jsonEncode(draft.stored())) as Json,
      );
      expect(restored.mediaIds, [testId]);
      expect(restored.payload()['media_ids'], [testId]);
    },
  );
  test(
    'OTP obeys server retry delay and sends stable installation ID',
    () async {
      final api = QogamApi(
        store: fixture.MemoryStore(),
        deviceId: 'installation',
        client: MockClient((r) async {
          expect(r.headers['X-Device-Id'], 'installation');
          return fixture.reply({
            'expires_at': '2026-10-10T12:00:00Z',
            'retry_after': 123,
          });
        }),
      );
      addTearDown(api.dispose);
      expect(await api.requestOtp('+77011234567'), 123);
    },
  );
  testWidgets(
    'Consecutive photo uploads retain both IDs without waiting for parent frames',
    (tester) async {
      var sequence = 0;
      final ids = <List<String>>[];
      final busy = <bool>[];
      final api = await authenticated(
        MockClient(
          (r) async => fixture.reply({
            'media_id': '${++sequence}2345678-1234-4234-8234-123456789012',
            'status': 'ready',
            'attached': false,
          }, 201),
        ),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        shell(
          Scaffold(
            body: MediaAttachments(
              api: api,
              strings: const ServiceStrings('ru'),
              ids: const [],
              onChanged: (value) => ids.add([...value]),
              onBusyChanged: busy.add,
              pickPhotos: (_) async => [
                XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'one.jpg'),
                XFile.fromData(Uint8List.fromList([4, 5, 6]), name: 'two.jpg'),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Добавить фото'));
      await tester.pumpAndSettle();
      expect(ids.last.length, 2);
      expect(ids.last.first, testId);
      expect(busy, [true, false]);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'Notification pagination retains entries and read action sends correct ID',
    (tester) async {
      var read = 0;
      final first =
          sample({r'$ref': '#/components/schemas/NotificationOut'}) as Json;
      first['title'] = 'First notification';
      final second = {
        ...first,
        'id': '22345678-1234-4234-8234-123456789012',
        'title': 'Second notification',
      };
      final api = await authenticated(
        MockClient((r) async {
          if (r.method == 'PUT') {
            expect(r.url.path, '/v1/me/notifications/$testId/read');
            read++;
            return http.Response('', 204);
          }
          if (r.url.queryParameters['cursor'] == 'next') {
            return fixture.reply({
              'items': [second],
              'has_more': false,
              'next_cursor': null,
            });
          }
          return fixture.reply({
            'items': [first],
            'has_more': true,
            'next_cursor': 'next',
          });
        }),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        shell(
          ServicePage(
            api: api,
            strings: const ServiceStrings('ru'),
            operation: ApiContract.operation('GET', '/v1/me/notifications'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Загрузить ещё'));
      await tester.pumpAndSettle();
      expect(find.text('First notification'), findsOneWidget);
      expect(find.text('Second notification'), findsOneWidget);
      await tester.tap(find.text('First notification'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Отметить прочитанным'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Отметить прочитанным'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(read, 1);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'Protected cached data disappears when refresh rejects the session',
    (tester) async {
      var count = 0;
      final notification =
          sample({r'$ref': '#/components/schemas/NotificationOut'}) as Json;
      notification['title'] = 'Private notification';
      final api = await authenticated(
        MockClient((r) async {
          if (r.url.path == '/v1/me/notifications' && ++count == 1) {
            return fixture.reply({
              'items': [notification],
              'next_cursor': null,
              'has_more': false,
            });
          }
          return fixture.reply({
            'code': 'auth.session_revoked',
            'status': 401,
          }, 401);
        }),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        shell(
          ServicePage(
            api: api,
            strings: const ServiceStrings('ru'),
            operation: ApiContract.operation('GET', '/v1/me/notifications'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private notification'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      expect(api.user, null);
      expect(find.text('Private notification'), findsNothing);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'House request retry restores exact encrypted payload after page recreation',
    (tester) async {
      final pending = fixture.MemoryStore();
      final sent = <Json>[];
      var attempt = 0;
      final api = await authenticated(
        MockClient((r) async {
          if (r.method == 'POST') {
            sent.add(jsonDecode(r.body) as Json);
            attempt++;
            if (attempt == 1) throw http.ClientException('connection lost');
            return fixture.reply(
              sample({r'$ref': '#/components/schemas/HouseRequestOut'}),
              201,
            );
          }
          return fixture.reply([]);
        }),
      );
      addTearDown(api.dispose);
      Widget page() => shell(
        ServiceFormPage(
          api: api,
          strings: const ServiceStrings('ru'),
          operation: ApiContract.operation(
            'POST',
            '/v1/houses/{house_id}/requests',
          ),
          path: {'house_id': testId},
          initial: {
            'category_code': 'roads.pothole',
            'description': 'Private house problem description',
          },
          pendingStore: pending,
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Сохранить'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(sent.length, 1);
      expect(pending.value, isNotNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Повторить'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(sent, [sent.first, sent.first]);
      expect(pending.value, null);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'House list opens contacts, membership request and private request actions',
    (tester) async {
      final house =
          sample({r'$ref': '#/components/schemas/HouseDetail'}) as Json;
      house['address_text'] = 'Test house';
      final api = await authenticated(
        MockClient((r) async => fixture.reply(house)),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        shell(
          ServiceEntityPage(
            api: api,
            strings: const ServiceStrings('ru'),
            source: ApiContract.operation('GET', '/v1/houses'),
            item: house,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Подтвердить проживание'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Подтвердить проживание'), findsOneWidget);
      await tester.tap(find.text('Подтвердить проживание'));
      await tester.pumpAndSettle();
      expect(find.text('Квартира (приватно)'), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'Every body schema and staff action variant fits narrow Kazakh at 200 percent',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final api = await authenticated(
        MockClient((r) async => fixture.reply([])),
        role: 'platform_admin',
        mfa: true,
      );
      addTearDown(api.dispose);
      for (final operation in ApiContract.operations.where(
        (o) => o.bodySchema != null && !o.multipart,
      )) {
        final resolved = ApiContract.resolve(operation.bodySchema!);
        final variants = resolved['oneOf'] as List? ?? [operation.bodySchema!];
        for (final variant in variants) {
          final field = ContractField(
            'details',
            variant as Json,
            required: true,
            initial: sample(variant),
          );
          await tester.pumpWidget(
            shell(
              Scaffold(
                body: ListView(
                  children: [
                    ContractFieldEditor(
                      field: field,
                      strings: const ServiceStrings('kk'),
                      api: api,
                      changed: () {},
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            null,
            reason: '${operation.method} ${operation.path} $variant',
          );
          await tester.pumpWidget(const SizedBox());
        }
      }
    },
  );
}
