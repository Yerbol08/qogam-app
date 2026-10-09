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
