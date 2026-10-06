import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'domain.dart';
import 'strings.dart';
import 'nearby.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final p = await SharedPreferences.getInstance();
  runApp(QogamApp(preferences: p, repository: DemoRepository(p)));
}

const teal = Color(0xff087f75);

class QogamApp extends StatefulWidget {
  final SharedPreferences preferences;
  final QogamRepository repository;
  final bool mapTilesEnabled;
  const QogamApp({
    super.key,
    required this.preferences,
    required this.repository,
    this.mapTilesEnabled = true,
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
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: teal,
        primary: teal,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xfff5f8f7),
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: const Color(0xff172c29),
        displayColor: const Color(0xff172c29),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfff5f8f7),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xffe0f2eb),
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? teal
                : const Color(0xff5c706a),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: teal,
        side: const BorderSide(color: Color(0xffdce6e1)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        labelStyle: const TextStyle(fontSize: 12),
        secondaryLabelStyle: const TextStyle(color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xffdce6e1)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xffdce6e1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xffdce6e1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: teal, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    ),
    home: Home(
      repository: widget.repository,
      tilesEnabled: widget.mapTilesEnabled,
      s: Strings(language),
      changeLanguage: () async {
        final next = language == 'ru' ? 'kk' : 'ru';
        await widget.preferences.setString('language', next);
        setState(() => language = next);
      },
    ),
  );
}

class Panel extends StatelessWidget {
  final Widget child;
  const Panel({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

class StatusBadge extends StatelessWidget {
  final String status;
  final Strings s;
  const StatusBadge(this.status, this.s, {super.key});
  @override
  Widget build(BuildContext context) {
    final colors = switch (status) {
      'progress' => [const Color(0xffe8f2ff), const Color(0xff1263ab)],
      'resolved' => [const Color(0xffe1f3e9), const Color(0xff167653)],
      _ => [const Color(0xfffff0d2), const Color(0xff875a13)],
    };
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors[0],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        s.t(status),
        style: TextStyle(color: colors[1], fontSize: 12),
      ),
    );
  }
}

class Home extends StatefulWidget {
  final QogamRepository repository;
  final Strings s;
  final VoidCallback changeLanguage;
  final bool tilesEnabled;
  const Home({
    super.key,
    required this.repository,
    required this.s,
    required this.changeLanguage,
    this.tilesEnabled = true,
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
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(s.t('success'))),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Icon(Icons.check_circle_outline, color: teal, size: 80),
              const SizedBox(height: 24),
              Text(
                s.t('success'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text(s.t('successNote')),
              const SizedBox(height: 20),
              Panel(child: Text(result.id)),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(s.t('toMine')),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) {
      setState(() => tab = 1);
    }
  }

  Widget heading(String key) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(
      s.t(key),
      style: Theme.of(
        context,
      ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
    ),
  );
  Future<void> openProblem(Problem p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Detail(problem: p, repository: widget.repository, s: s),
      ),
    );
    await refresh();
  }

  Widget tile(Problem p) => ProblemTile(
    problem: p,
    s: s,
    joined: joined.contains(p.id),
    onTap: () => openProblem(p),
  );
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
              s.t('demo'),
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
          ? Center(
              child: TextButton(onPressed: refresh, child: Text(s.t('retry'))),
            )
          : tab == 0
          ? Nearby(
              problems: public,
              joined: joined,
              s: s,
              onOpen: openProblem,
              tilesEnabled: widget.tilesEnabled,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              children: [
                Text(
                  s.t('note'),
                  style: const TextStyle(
                    color: Color(0xff5c706a),
                    fontSize: 12,
                  ),
                ),
                ...switch (tab) {
                  1 => [
                    heading('mine'),
                    if (draft != null &&
                        (draft!.category != null ||
                            draft!.description.isNotEmpty))
                      Panel(
                        child: ListTile(
                          title: Text(s.t('draft')),
                          subtitle: Text(
                            draft!.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: form,
                        ),
                      ),
                    heading('own'),
                    if (own.isEmpty) Text(s.t('empty')),
                    ...own.map(tile),
                    heading('joinedList'),
                    if (joined.isEmpty) Text(s.t('empty')),
                    ...public.where((p) => joined.contains(p.id)).map(tile),
                  ],
                  2 => [
                    heading('yourHome'),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: teal,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.apartment,
                            color: Colors.white,
                            size: 40,
                          ),
                          Text(
                            s.t('homeAddress'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                            ),
                          ),
                          Text(
                            s.t('homeNote'),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    heading('news'),
                    Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.t('lift'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(s.t('liftNote')),
                        ],
                      ),
                    ),
                    Text(s.t('homeLater')),
                  ],
                  _ => [
                    heading('profile'),
                    Panel(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_outline),
                        ),
                        title: Text(s.t('user')),
                        subtitle: Text(s.t('demo')),
                      ),
                    ),
                    Panel(
                      child: ListTile(
                        title: Text(s.t('language')),
                        trailing: Text(
                          s.language == 'ru' ? 'Русский' : 'Қазақша',
                        ),
                        onTap: widget.changeLanguage,
                      ),
                    ),
                    Text(s.t('profileLater')),
                  ],
                },
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

class Detail extends StatefulWidget {
  final Problem problem;
  final ProblemRepository repository;
  final Strings s;
  const Detail({
    super.key,
    required this.problem,
    required this.repository,
    required this.s,
  });
  @override
  State<Detail> createState() => _DetailState();
}

class _DetailState extends State<Detail> {
  bool joined = false, busy = true;
  @override
  void initState() {
    super.initState();
    widget.repository.joined().then((ids) {
      if (mounted) {
        setState(() {
          joined = ids.contains(widget.problem.id);
          busy = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.problem;
    final s = widget.s;
    return Scaffold(
      appBar: AppBar(title: Text(p.id)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(s.t('note')),
          const SizedBox(height: 20),
          Text(p.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Text(p.address),
          Text(s.t(p.category.name)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(p.status, s),
          ),
          const SizedBox(height: 16),
          Text('${p.supporters + (joined ? 1 : 0)} ${s.t('residents')}'),
          if (p.published)
            FilledButton(
              onPressed: busy || joined
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        await widget.repository.join(p.id);
                        if (mounted) {
                          setState(() => joined = true);
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(s.t('error'))));
                        }
                      } finally {
                        if (mounted) {
                          setState(() => busy = false);
                        }
                      }
                    },
              child: Text(s.t(joined ? 'joined' : 'join')),
            ),
          const SizedBox(height: 24),
          Text(s.t('history'), style: Theme.of(context).textTheme.titleLarge),
          ...p.history.map(
            (event) => ListTile(
              leading: const Icon(Icons.check_circle_outline, color: teal),
              title: Text(s.t(event)),
              subtitle: Text(
                '${DateFormat.yMMMd(s.language).format(p.createdAt.toLocal())} · ${s.t('demo')}',
              ),
            ),
          ),
          Text(s.t('source')),
        ],
      ),
    );
  }
}

class ReportForm extends StatefulWidget {
  final Draft initial;
  final QogamRepository repository;
  final Strings s;
  final VoidCallback? changeLanguage;
  const ReportForm({
    super.key,
    required this.initial,
    required this.repository,
    required this.s,
    this.changeLanguage,
  });
  @override
  State<ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends State<ReportForm> {
  late Draft d = Draft.fromJson(widget.initial.toJson());
  late final description = TextEditingController(text: d.description),
      address = TextEditingController(text: d.address);
  int step = 0;
  bool busy = false;
  List<String> errors = [];
  Future<void> writes = Future.value();
  late Strings s = widget.s;
  void save() {
    final snapshot = Draft.fromJson(d.toJson());
    writes = writes
        .catchError((Object _) {})
        .then((_) => widget.repository.saveDraft(snapshot));
    writes.catchError((Object _) {
      if (mounted) {
        setState(() => errors = ['error']);
      }
    });
  }

  @override
  void dispose() {
    description.dispose();
    address.dispose();
    super.dispose();
  }

  Future<void> next() async {
    setState(() => errors = d.validate(step: step));
    if (errors.isNotEmpty || busy) {
      return;
    }
    if (step < 2) {
      setState(() => step++);
      return;
    }
    setState(() => busy = true);
    try {
      await writes;
      final result = await widget.repository.submit(d);
      await widget.repository.saveDraft(Draft());
      if (mounted) {
        Navigator.pop(context, result);
      }
    } catch (_) {
      if (mounted) {
        setState(() => errors = ['error']);
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(s.t('new')),
        actions: [
          TextButton(
            onPressed: busy
                ? null
                : () {
                    widget.changeLanguage?.call();
                    setState(
                      () => s = Strings(s.language == 'ru' ? 'kk' : 'ru'),
                    );
                  },
            child: Text(s.language == 'ru' ? 'Қаз' : 'Рус'),
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: busy
              ? null
              : () async {
                  if (step > 0) {
                    setState(() => step--);
                  } else {
                    await writes.catchError((Object _) {});
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  }
                },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('${s.t('demo')} · ${step + 1}/3'),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: (step + 1) / 3),
          const SizedBox(height: 24),
          Text(
            s.t(['description', 'place', 'review'][step]),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          if (step == 0) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: Category.values
                  .map(
                    (c) => ChoiceChip(
                      label: Text(s.t(c.name)),
                      selected: d.category == c,
                      onSelected: (_) {
                        setState(() => d.category = c);
                        save();
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: description,
              minLines: 5,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: s.t('description'),
                errorText: errors.contains('descriptionError')
                    ? s.t('descriptionError')
                    : null,
              ),
              onChanged: (v) {
                d.description = v;
                save();
              },
            ),
            const SizedBox(height: 12),
            Text(s.t('privacy')),
          ],
          if (step == 1) ...[
            TextField(
              controller: address,
              decoration: InputDecoration(labelText: s.t('address')),
              onChanged: (v) {
                setState(() {
                  d.address = v;
                  d.confirmed = false;
                });
                save();
              },
            ),
            const SizedBox(height: 16),
            Text(s.t('point')),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                onTapDown: (e) {
                  setState(() {
                    d.latitude = 51.12 + (1 - e.localPosition.dy / 180) * .04;
                    d.longitude =
                        71.40 + e.localPosition.dx / constraints.maxWidth * .06;
                    d.confirmed = false;
                  });
                  save();
                },
                child: Container(
                  height: 180,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xffe0f2eb),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Stack(
                    children: [
                      const Center(
                        child: Icon(
                          Icons.grid_4x4,
                          color: Colors.white,
                          size: 160,
                        ),
                      ),
                      Align(
                        alignment: d.latitude == null
                            ? Alignment.center
                            : Alignment(
                                ((d.longitude! - 71.40) / .06 * 2 - 1).clamp(
                                  -1.0,
                                  1.0,
                                ),
                                ((1 - (d.latitude! - 51.12) / .04) * 2 - 1)
                                    .clamp(-1.0, 1.0),
                              ),
                        child: const Icon(
                          Icons.location_pin,
                          color: teal,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (d.latitude != null)
              Text(
                '${d.latitude!.toStringAsFixed(5)}, ${d.longitude!.toStringAsFixed(5)}',
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('confirm')),
              value: d.confirmed,
              onChanged: d.latitude == null
                  ? null
                  : (v) {
                      setState(() => d.confirmed = v ?? false);
                      save();
                    },
            ),
          ],
          if (step == 2) ...[
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.t(d.category?.name ?? 'categoryError')),
                  const SizedBox(height: 12),
                  Text(d.description),
                  const Divider(),
                  Text(d.address),
                  Text(
                    '${d.latitude?.toStringAsFixed(5)}, ${d.longitude?.toStringAsFixed(5)}',
                  ),
                ],
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('consent')),
              value: d.consent,
              onChanged: busy
                  ? null
                  : (v) {
                      setState(() => d.consent = v ?? false);
                      save();
                    },
            ),
          ],
          ...errors.map(
            (e) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                s.t(e),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: busy ? null : next,
            child: busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(s.t(step == 2 ? 'send' : 'next')),
          ),
          const SizedBox(height: 16),
          Text(s.t('saved'), textAlign: TextAlign.center),
          const SizedBox(height: 32),
        ],
      ),
    ),
  );
}
