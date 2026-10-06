import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qogam/domain.dart';
import 'package:qogam/strings.dart';
import 'package:qogam/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:qogam/nearby.dart';
import 'package:qogam/report_form.dart';
import 'package:qogam/detail.dart';
import 'package:qogam/ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('NotoSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans.ttf'));
    await font.load();
  });
  testWidgets('Compact form and detail with 200 percent text and keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final repo = DemoRepository(await SharedPreferences.getInstance());
    Widget app(Widget child) => MaterialApp(
      theme: qogamTheme(),
      locale: const Locale('kk'),
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    );
    await tester.pumpWidget(
      app(
        ReportForm(
          initial: valid(),
          repository: repo,
          s: const Strings('kk'),
          tilesEnabled: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(TextField),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byType(TextField),
      'Көше жарығы жұмыс істемейді',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Жалғастыру'), findsOneWidget);
    tester.view.resetViewInsets();
    await tester.pumpWidget(
      app(
        Detail(
          problem: DemoRepository.seeds.first,
          repository: repo,
          s: const Strings('kk'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Менде де бар'), findsOneWidget);
  });
  testWidgets('Nearby filter survives tab changes', (tester) async {
    final p = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      QogamApp(
        preferences: p,
        repository: DemoRepository(p),
        mapTilesEnabled: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Дороги'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person_outline).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.location_on_outlined).last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
      hasLength(1),
    );
  });
  testWidgets('Detail renders full description and keeps join action visible', (
    tester,
  ) async {
    final repo = DemoRepository(await SharedPreferences.getInstance());
    final problem = DemoRepository.seeds.first;
    await tester.pumpWidget(
      MaterialApp(
        theme: qogamTheme(),
        home: Detail(
          problem: problem,
          repository: repo,
          s: const Strings('ru'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(problem.description), findsOneWidget);
    await tester.tap(find.text('У меня тоже'));
    await tester.pumpAndSettle();
    expect(find.text('Вы присоединились'), findsOneWidget);
    expect(await repo.joined(), {problem.id});
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });
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
    await tester.scrollUntilVisible(
      find.byType(TextField),
      200,
      scrollable: find.byType(Scrollable).first,
    );
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
    await tester.ensureVisible(find.byKey(const Key('location-map')));
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getTopLeft(find.byKey(const Key('location-map'))) +
          const Offset(100, 100),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect((await repository.loadDraft())!.latitude, isNotNull);
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .maxScrollExtent,
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
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .maxScrollExtent,
        );
    await tester.pumpAndSettle();
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
