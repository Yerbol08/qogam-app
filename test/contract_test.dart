import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qogam/api_contract.dart';
import 'package:qogam/backend.dart';
import 'package:qogam/service_forms.dart';
import 'backend_test.dart' show MemoryStore, tokens, userJson, reply;

const testId = '12345678-1234-4234-8234-123456789012';
dynamic sample(Json schema) {
  final s = ApiContract.resolve(schema);
  if (s.containsKey('const')) return s['const'];
  if (s['enum'] is List) return (s['enum'] as List).first;
  if (s.containsKey('default')) return s['default'];
  if (s['anyOf'] is List || s['oneOf'] is List) {
    return sample(((s['anyOf'] ?? s['oneOf']) as List).first as Json);
  }
  switch (s['type']) {
    case 'object':
      return {
        for (final key in s['required'] as List? ?? [])
          key as String: sample(s['properties'][key] as Json),
      };
    case 'array':
      return List.generate(
        s['minItems'] ?? 0,
        (_) => sample(s['items'] as Json),
      );
    case 'integer':
      return (s['minimum'] ?? 1).toInt();
    case 'number':
      return (s['minimum'] ?? 1).toDouble();
    case 'boolean':
      return true;
    case 'null':
      return null;
    default:
      if (s['format'] == 'uuid') return testId;
      if (s['format'] == 'date-time') return '2026-10-10T12:00:00+05:00';
      if (s['pattern'] == r'^\d{6}$') return '123456';
      if (s['pattern'] != null) return 'sample';
      return 'sample_value';
  }
}

void main() {
  test(
    'Generated inventory exactly matches all OpenAPI methods, params and DTOs',
    () {
      final schema =
          jsonDecode(File('docs/openapi.json').readAsStringSync()) as Json;
      final expected = <String>{};
      for (final e in (schema['paths'] as Json).entries) {
        for (final m in (e.value as Json).entries) {
          if (!['get', 'post', 'patch', 'put', 'delete'].contains(m.key)) {
            continue;
          }
          expected.add('${m.key.toUpperCase()} ${e.key}');
          final operation = ApiContract.operation(m.key.toUpperCase(), e.key);
          expect(operation.parameters, m.value['parameters'] ?? []);
          expect(
            operation.authenticated,
            (m.value['security'] as List? ?? []).isNotEmpty,
          );
          final content = m.value['requestBody']?['content'] as Json? ?? {};
          expect(
            operation.bodySchema,
            content.isEmpty ? null : content.values.first['schema'],
          );
        }
      }
      expect(
        ApiContract.operations.map((o) => '${o.method} ${o.path}').toSet(),
        expected,
      );
      expect(expected.length, 119);
      expect(ApiContract.schemas, schema['components']['schemas']);
    },
  );
  for (final operation in ApiContract.operations) {
    test('Contract transport ${operation.method} ${operation.path}', () async {
      final paths = <String, dynamic>{}, query = <String, dynamic>{};
      final headers = <String, String>{};
      for (final p in operation.parameters) {
        if (p['name'] == 'accept-language') continue;
        final value = sample(p['schema'] as Json);
        switch (p['in']) {
          case 'path':
            paths[p['name']] = value;
          case 'query':
            query[p['name']] = value;
          case 'header':
            headers[p['name']] = '$value';
        }
      }
      var route = operation.path;
      for (final e in paths.entries) {
        route = route.replaceAll(
          '{${e.key}}',
          Uri.encodeComponent('${e.value}'),
        );
      }
      Json? payload = operation.bodySchema == null || operation.multipart
          ? null
          : sample(operation.bodySchema!) as Json;
      if (operation.path == '/v1/auth/otp/request' ||
          operation.path == '/v1/auth/otp/verify') {
        payload!['phone'] = '+77011234567';
      }
      var requests = 0;
      final store = MemoryStore();
      await store.write(
        ApiSession.fromTokens(tokens(), DateTime.now()).encode(),
      );
      final api = QogamApi(
        store: store,
        language: 'kk',
        client: MockClient((request) async {
          requests++;
          expect(request.method, operation.method);
          expect(request.url.path, Uri.parse(route).path);
          expect(request.url.queryParameters, {
            for (final e in query.entries) e.key: '${e.value}',
          });
          expect(request.followRedirects, false);
          expect(request.headers['Accept-Language'], 'kk');
          if (operation.authenticated) {
            expect(request.headers['Authorization'], 'Bearer access1');
          }
          for (final e in headers.entries) {
            expect(request.headers[e.key], e.value);
          }
          if (operation.multipart) {
            expect(
              request.headers['content-type'],
              contains('multipart/form-data'),
            );
            expect(
              latin1.decode(request.bodyBytes),
              contains('client_media_id'),
            );
            expect(latin1.decode(request.bodyBytes), contains(testId));
            expect(latin1.decode(request.bodyBytes), contains('image/jpeg'));
            expect(
              latin1.decode(request.bodyBytes),
              contains('filename="photo.jpg"'),
            );
          } else if (payload != null) {
            expect(jsonDecode(request.body), payload);
          } else {
            expect(request.body, isEmpty);
          }
          if ([
            '/v1/auth/otp/verify',
            '/v1/auth/refresh',
            '/v1/auth/mfa/confirm',
          ].contains(operation.path)) {
            return reply({...tokens(), 'mfa': true});
          }
          if (operation.path == '/v1/me' &&
              ['GET', 'PATCH'].contains(operation.method)) {
            return reply(userJson);
          }
          if (operation.statuses.contains(204)) return http.Response('', 204);
          return reply(
            operation.responseSchema == null
                ? {}
                : sample(operation.responseSchema!),
            operation.statuses.first,
          );
        }),
      );
      addTearDown(api.dispose);
      await api.restore();
      await ContractApi(api).call(
        operation,
        path: paths,
        query: query,
        body: payload,
        headers: headers,
        upload: operation.multipart
            ? const ApiUpload(
                bytes: [255, 216, 255, 217],
                filename: 'photo.jpg',
                clientMediaId: testId,
              )
            : null,
      );
      expect(requests, 1);
      if (operation.path == '/v1/auth/mfa/confirm') expect(api.mfa, true);
      if (operation.path == '/v1/me' && operation.method == 'DELETE') {
        expect(api.user, null);
      }
    });
  }
  test(
    'PATCH distinguishes omission, null and values; union preserves revision',
    () {
      final field = ContractField('profile', {
        r'$ref': '#/components/schemas/UserPatch',
      }, required: true);
      expect(field.value(), {});
      field.children['display_name']!
        ..included = true
        ..cleared = true;
      expect(field.value(), {'display_name': null});
      final action = ContractField(
        'action',
        ApiContract.operation(
          'POST',
          '/v1/staff/reports/{report_id}/actions',
        ).bodySchema!,
        required: true,
        initial: {
          'action': 'reject',
          'expected_revision': 7,
          'reason_code': 'other',
        },
      );
      expect(action.value(), {
        'action': 'reject',
        'expected_revision': 7,
        'reason_code': 'other',
      });
      expect(ApiContract.validate(action.schema, action.value()), isEmpty);
    },
  );
  test(
    'Invalid parameters, body and discriminated action never reach transport',
    () async {
      var sent = 0;
      final api = QogamApi(
        store: MemoryStore(),
        client: MockClient((r) async {
          sent++;
          return reply({});
        }),
      );
      addTearDown(api.dispose);
      final client = ContractApi(api);
      await expectLater(
        client.call(
          ApiContract.operation('GET', '/v1/geo/reverse'),
          query: {'lat': 100, 'lng': 0},
        ),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        client.call(
          ApiContract.operation('GET', '/v1/houses/{house_id}'),
          path: {'house_id': '../me'},
        ),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        client.call(
          ApiContract.operation(
            'POST',
            '/v1/staff/reports/{report_id}/actions',
          ),
          path: {'report_id': testId},
          body: {'action': 'delete_everything', 'expected_revision': 1},
        ),
        throwsA(isA<ApiException>()),
      );
      expect(sent, 0);
    },
  );
}
