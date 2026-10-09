import 'package:qogam/api_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qogam/backend.dart';

class NoSessionStore implements SessionStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async =>
      throw StateError('Read-only smoke test');
  @override
  Future<void> clear() async {}
}

void main() {
  test(
    'Live read-only meta/categories/cities for ru and kk',
    () async {
      final api = QogamApi(store: NoSessionStore());
      addTearDown(api.dispose);
      expect((await api.meta()).consentVersion, isNotEmpty);
      for (final locale in ['ru', 'kk']) {
        api.language = locale;
        expect(await api.categories(), isNotEmpty);
        expect(await api.cities(), isNotEmpty);
        final statuses = await api.request('GET', '/v1/statuses') as Json;
        expect(statuses['statuses'], isNotEmpty);
        final city = await api.request('GET', '/v1/cities/astana') as Json;
        expect(city.containsKey('boundary'), true);
        final page =
            await api.request(
                  'GET',
                  '/v1/problems',
                  query: {'city_code': 'astana', 'limit': '2'},
                )
                as Json;
        expect(page.containsKey('has_more'), true);
        final map =
            await api.request(
                  'GET',
                  '/v1/problems/map',
                  query: {
                    'bbox': '71.3,51.0,71.6,51.3',
                    'zoom': '15',
                    'city_code': 'astana',
                  },
                )
                as Json;
        expect(['clusters', 'markers'].contains(map['mode']), true);
        final legal =
            await api.request(
                  'GET',
                  '/v1/legal/documents',
                  query: {'language': locale},
                )
                as List;
        expect(legal, isNotEmpty);
        final contract = ContractApi(api);
        for (final entry in [
          (
            ApiContract.operation('GET', '/v1/alerts'),
            <String, dynamic>{'city_code': 'astana'},
          ),
          (
            ApiContract.operation('GET', '/v1/problems/similar'),
            <String, dynamic>{
              'category_code': 'roads.pothole',
              'lat': 51.13,
              'lng': 71.43,
            },
          ),
        ]) {
          final result = await contract.call(entry.$1, query: entry.$2);
          expect(
            ApiContract.validate(entry.$1.responseSchema!, result),
            isEmpty,
            reason: entry.$1.path,
          );
        }
        // The server exposes the safe house list anonymously, although OpenAPI marks it secured.
        final houses = await api.request(
          'GET',
          '/v1/houses',
          query: {'city_code': 'astana', 'limit': '2'},
        );
        expect(
          ApiContract.validate(
            ApiContract.operation('GET', '/v1/houses').responseSchema!,
            houses,
          ),
          isEmpty,
        );
        try {
          final op = ApiContract.operation('GET', '/v1/geo/reverse');
          final result = await contract.call(
            op,
            query: {'lat': 51.13, 'lng': 71.43, 'city_code': 'astana'},
          );
          expect(ApiContract.validate(op.responseSchema!, result), isEmpty);
        } on ApiException catch (e) {
          // No match is a valid geocoder outcome; unexpected failures must fail this test.
          expect(e.status, 404);
        }

        if ((page['items'] as List).isNotEmpty) {
          final id = page['items'][0]['id'];
          final card = await api.request('GET', '/v1/problems/$id') as Json;
          expect(card.containsKey('description'), true);
          final history =
              await api.request('GET', '/v1/problems/$id/history') as Json;
          expect(history.containsKey('items'), true);
        }
      }
    },
    skip: !const bool.fromEnvironment('QOGAM_LIVE_API_TEST'),
  );
}
