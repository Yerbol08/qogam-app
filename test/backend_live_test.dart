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
      }
    },
    skip: !const bool.fromEnvironment('QOGAM_LIVE_API_TEST'),
  );
}
