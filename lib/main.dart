import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'domain.dart';
import 'strings.dart';
import 'nearby.dart';
import 'ui.dart';
import 'pages.dart';
import 'detail.dart';
import 'report_form.dart';
import 'backend.dart';
import 'backend_pages.dart';
import 'backend_strings.dart';
import 'civic_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final p = await SharedPreferences.getInstance();
  final api = QogamApi(
    store: SecureSessionStore(QogamApi.defaultBaseUrl),
    language: p.getString('language') ?? 'ru',
  );
  runApp(
    QogamApp(
      preferences: p,
      repository: DemoRepository(p),
      api: const bool.fromEnvironment('QOGAM_DEMO') ? null : api,
    ),
  );
}

class QogamApp extends StatefulWidget {
  final SharedPreferences preferences;
  final QogamRepository repository;
  final bool mapTilesEnabled;
  final QogamApi? api;
  const QogamApp({
    super.key,
    required this.preferences,
    required this.repository,
    this.mapTilesEnabled = true,
    this.api,
  });
  @override
  State<QogamApp> createState() => _QogamAppState();
}

class _QogamAppState extends State<QogamApp> {
  late String language = widget.preferences.getString('language') ?? 'ru';
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Qogam',
    debugShowCheckedModeBanner: false,
    locale: Locale(language),
    supportedLocales: const [Locale('ru'), Locale('kk')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: qogamTheme(),
    home: widget.api != null
        ? CivicHome(
            api: widget.api!,
            preferences: widget.preferences,
            strings: Strings(language),
            changeLanguage: () async {
              final next = language == 'ru' ? 'kk' : 'ru';
              await widget.preferences.setString('language', next);
              widget.api!.language = next;
              if (mounted) setState(() => language = next);
            },
            tilesEnabled: widget.mapTilesEnabled,
          )
        : Home(
            repository: widget.repository,
            api: widget.api,
            tilesEnabled: widget.mapTilesEnabled,
            s: Strings(language),
            changeLanguage: () async {
              final next = language == 'ru' ? 'kk' : 'ru';
              await widget.preferences.setString('language', next);
              widget.api?.language = next;
              setState(() => language = next);
            },
          ),
  );
}

class Home extends StatefulWidget {
  final QogamRepository repository;
  final Strings s;
  final VoidCallback changeLanguage;
  final bool tilesEnabled;
  final QogamApi? api;
  const Home({
    super.key,
    required this.repository,
    required this.s,
    required this.changeLanguage,
    this.tilesEnabled = true,
    this.api,
  });
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  List<Problem> public = [], own = [];
  Set<String> joined = {};
  Draft? draft;
  bool loading = true, failed = false;
  Strings get s => widget.s;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final p = await widget.repository.published();
      final o = await widget.repository.mine();
      final j = await widget.repository.joined();
      final d = await widget.repository.loadDraft();
      if (mounted) {
        setState(() {
          public = p;
          own = o;
          joined = j;
          draft = d;
          loading = false;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    }
  }

  Future<void> form() async {
    final result = await Navigator.push<Problem>(
      context,
      MaterialPageRoute(
        builder: (_) => ReportForm(
          repository: widget.repository,
          initial: draft ?? Draft(),
          s: s,
          changeLanguage: widget.changeLanguage,
          tilesEnabled: widget.tilesEnabled,
        ),
      ),
    );
    await refresh();
    if (!mounted || result == null) {
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SuccessView(problem: result, s: s),
      ),
    );
    if (mounted) {
      setState(() => tab = 1);
    }
  }

  Future<void> openProblem(Problem p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Detail(problem: p, repository: widget.repository, s: s),
      ),
    );
    await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final keys = ['near', 'mine', 'home', 'profile'];
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.hub_rounded, color: teal, size: 28),
            SizedBox(width: 9),
            Flexible(
              child: Text(
                'qogam',
                maxLines: 1,
                overflow: TextOverflow.fade,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 25,
                  letterSpacing: -1,
                ),
              ),
            ),
          ],
        ),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xffe0f2eb),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              tab == 3 && widget.api != null
                  ? BackendStrings(s.language).t('live')
                  : s.t('demo'),
              style: const TextStyle(
                color: teal,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: widget.changeLanguage,
            child: Text(s.language == 'ru' ? 'Қаз' : 'Рус'),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : failed
          ? ListView(
              padding: const EdgeInsets.all(20),
              children: [
                EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: s.t('loadError'),
                  body: s.t('loadErrorBody'),
                ),
                FilledButton(onPressed: refresh, child: Text(s.t('retry'))),
              ],
            )
          : IndexedStack(
              index: tab,
              children: [
                Nearby(
                  problems: public,
                  joined: joined,
                  s: s,
                  onOpen: openProblem,
                  tilesEnabled: widget.tilesEnabled,
                ),
                RequestsView(
                  own: own,
                  public: public,
                  joined: joined,
                  draft: draft,
                  s: s,
                  onDraft: form,
                  onOpen: openProblem,
                ),
                HouseView(s: s),
                if (widget.api != null)
                  BackendProfile(
                    api: widget.api!,
                    s: s,
                    changeLanguage: widget.changeLanguage,
                    tilesEnabled: widget.tilesEnabled,
                  )
                else
                  ProfileView(s: s, changeLanguage: widget.changeLanguage),
              ],
            ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xffe7eeea))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tab < 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: FilledButton(
                  onPressed: form,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_circle_outline_rounded, size: 20),
                      const SizedBox(width: 8),
                      Flexible(child: Text(s.t('report'))),
                    ],
                  ),
                ),
              ),
            NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: List.generate(
                4,
                (i) => NavigationDestination(
                  icon: Icon(
                    [
                      Icons.location_on_outlined,
                      Icons.assignment_outlined,
                      Icons.apartment_outlined,
                      Icons.person_outline,
                    ][i],
                  ),
                  label: s.t(keys[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
