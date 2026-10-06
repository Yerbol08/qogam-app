import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qogam/domain.dart';
import 'package:qogam/strings.dart';
import 'package:qogam/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:qogam/nearby.dart';

Draft valid() => Draft(
  category: Category.roads,
  description: '0123456789',
  address: 'Астана, Достык 13',
  latitude: 51.13,
  longitude: 71.43,
  confirmed: true,
  consent: true,
);
void main() {
  testWidgets('Map and list share filters; marker opens published problem', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Nearby(
            problems: DemoRepository.seeds,
            joined: const {},
            s: const Strings('ru'),
            tilesEnabled: false,
            onOpen: (p) => opened.add(p.id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
      hasLength(3),
    );
    await tester.ensureVisible(find.text('Дороги'));
    await tester.tap(find.text('Дороги'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
      hasLength(1),
    );
    final markerIcon = find.descendant(
      of: find.byType(MarkerLayer),
      matching: find.byIcon(Icons.construction_rounded),
    );
    await tester.ensureVisible(markerIcon);
    await tester.tap(markerIcon);
    await tester.pumpAndSettle();
    expect(opened, ['DEMO-101']);
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Список'));
    await tester.pumpAndSettle();
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.byType(ProblemTile), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'несуществующая проблема');
    await tester.pumpAndSettle();
    expect(find.text('Пока ничего нет'), findsOneWidget);
  });
  testWidgets('Mobile layout with Kazakh and 200 percent text', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    SharedPreferences.setMockInitialValues({'language': 'kk'});
    final p = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      QogamApp(
        mapTilesEnabled: false,
        preferences: p,
        repository: DemoRepository(p),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final icon in [
      Icons.assignment_outlined,
      Icons.apartment_outlined,
      Icons.person_outline,
    ]) {
      await tester.tap(find.byIcon(icon).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('Three-step submission, draft and language preservation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    final repository = DemoRepository(p);
    await tester.pumpWidget(
      QogamApp(mapTilesEnabled: false, preferences: p, repository: repository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сообщить о проблеме'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Дороги'));
    await tester.enterText(
      find.byType(TextField).first,
      'Большая яма у перехода',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Қаз'));
    await tester.pumpAndSettle();
    expect(find.text('Большая яма у перехода'), findsOneWidget);
    await tester.tap(find.text('Рус'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Продолжить'));
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Астана, Достык 13');
    await tester.tapAt(
      tester.getCenter(find.byIcon(Icons.grid_4x4)) + const Offset(40, 20),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Продолжить'));
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Отправить'));
    await tester.tap(find.text('Отправить'));
    await tester.pumpAndSettle();
    expect(await repository.mine(), isEmpty);
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Отправить'));
    await tester.tap(find.text('Отправить'));
    await tester.pumpAndSettle();
    expect(find.text('Обращение принято'), findsNWidgets(2));
    await tester.tap(find.text('Перейти в мои заявки'));
    await tester.pumpAndSettle();
    expect(find.text('На модерации'), findsOneWidget);
    expect(await repository.mine(), hasLength(1));
    expect(tester.takeException(), isNull);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Validation boundaries, trim, category, point and separate consent', () {
    final d = valid();
    expect(d.validate(), isEmpty);
    d.description = '  0123456789  ';
    expect(d.validate(), isEmpty);
    d.description = '123456789';
    expect(d.validate(), contains('descriptionError'));
    d.description = 'я' * 2000;
    expect(d.validate(), isEmpty);
    d.description = 'я' * 2001;
    expect(d.validate(), contains('descriptionError'));
    d.description = ' ' * 15;
    expect(d.validate(), contains('descriptionError'));
    d.description = '0123456789';
    d.category = null;
    expect(d.validate(), contains('categoryError'));
    d.category = Category.roads;
    d.confirmed = false;
    expect(d.validate(), contains('locationError'));
    d.confirmed = true;
    d.latitude = null;
    expect(d.validate(), contains('locationError'));
    d.latitude = 91;
    expect(d.validate(), contains('locationError'));
    d.latitude = 51.13;
    d.consent = false;
    expect(d.validate(), contains('consentError'));
    expect(d.validate(step: 1), isEmpty);
  });
  test('Repeated and concurrent join persists once', () async {
    final p = await SharedPreferences.getInstance();
    final r = DemoRepository(p);
    await Future.wait([r.join('DEMO-101'), r.join('DEMO-101')]);
    await r.join('DEMO-101');
    expect(await DemoRepository(p).joined(), {'DEMO-101'});
    expect(
      (await r.published()).first.supporters + (await r.joined()).length,
      19,
    );
  });
  test('Draft restores all fields with stable request id', () async {
    final p = await SharedPreferences.getInstance();
    final d = valid();
    await DemoRepository(p).saveDraft(d);
    final restored = await DemoRepository(
      await SharedPreferences.getInstance(),
    ).loadDraft();
    expect(restored!.toJson(), d.toJson());
    expect(restored.validate(), isEmpty);
  });
  test('Submission idempotency and moderation privacy', () async {
    final r = DemoRepository(await SharedPreferences.getInstance());
    final d = valid();
    final results = await Future.wait([r.submit(d), r.submit(d)]);
    expect(results[0].id, results[1].id);
    expect(await r.mine(), hasLength(1));
    expect((await r.published()).any((p) => p.id == results[0].id), isFalse);
    expect(results.first.status, 'pending');
  });
  test('Localization keys match', () {
    expect(Strings.kk.keys.toSet(), Strings.ru.keys.toSet());
  });
  testWidgets('Navigation and language switch', (tester) async {
    final p = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      QogamApp(
        mapTilesEnabled: false,
        preferences: p,
        repository: DemoRepository(p),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('qogam'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.person_outline).last);
    await tester.pumpAndSettle();
    expect(find.text('Демо-житель'), findsOneWidget);
    await tester.tap(find.text('Қаз'));
    await tester.pumpAndSettle();
    expect(find.text('Демо-тұрғын'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
