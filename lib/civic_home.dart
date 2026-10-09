import 'api_contract.dart';
import 'service_pages.dart';
import 'service_strings.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'backend.dart';
import 'backend_pages.dart';
import 'backend_strings.dart';
import 'civic_repository.dart';
import 'civic_strings.dart';
import 'civic_detail.dart';
import 'civic_form.dart';
import 'strings.dart';
import 'ui.dart';

Future<bool> civicLogin(
  BuildContext context,
  QogamApi api,
  CivicStrings s,
) async {
  if (api.user != null) return true;
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => LoginPage(
        api: api,
        b: BackendStrings(s.language),
        legalRequired: true,
      ),
    ),
  );
  return api.user != null;
}

class CivicHome extends StatefulWidget {
  final QogamApi api;
  final SharedPreferences preferences;
  final Strings strings;
  final VoidCallback changeLanguage;
  final bool tilesEnabled;
  const CivicHome({
    super.key,
    required this.api,
    required this.preferences,
    required this.strings,
    required this.changeLanguage,
    this.tilesEnabled = true,
  });
  @override
  State<CivicHome> createState() => _CivicHomeState();
}

class _CivicHomeState extends State<CivicHome> {
  late final repo = ServerCivicRepository(widget.api);
  CivicStrings get s => CivicStrings(widget.strings.language);
  List<ApiCategory> categories = [];
  List<ApiCity> cities = [];
  Map<String, String> names = {};
  String city = 'astana';
  String? error, userId;
  bool loading = true;
  int tab = 0;
  @override
  void initState() {
    super.initState();
    widget.api.addListener(changed);
    initialize();
  }

  void changed() {
    if (mounted && userId != widget.api.user?.id) {
      setState(() {
        userId = widget.api.user?.id;
      });
    }
  }

  @override
  void didUpdateWidget(CivicHome old) {
    super.didUpdateWidget(old);
    if (old.strings.language != widget.strings.language) loadCatalog();
  }

  Future<void> initialize() async {
    try {
      await widget.api.restore();
    } catch (e) {
      if (mounted) error = BackendStrings(s.language).error(e);
    }
    await loadCatalog();
  }

  Future<void> loadCatalog() async {
    try {
      final data = await Future.wait<dynamic>([
        widget.api.categories(),
        widget.api.cities(),
        widget.api.request('GET', '/v1/statuses'),
      ]);
      if (!mounted) return;
      final nextCities = data[1] as List<ApiCity>;
      final selected =
          widget.preferences.getString('civic.city') ??
          widget.api.user?.city ??
          city;
      setState(() {
        categories = data[0] as List<ApiCategory>;
        cities = nextCities;
        if (cities.any((c) => c.code == selected)) {
          city = selected;
        } else if (cities.isNotEmpty) {
          city = cities.first.code;
        }
        names = {
          for (final group in [
            'moderation_states',
            'workflow_states',
            'statuses',
          ])
            for (final item in (data[2] as Json)[group] as List)
              item['code'] as String: item['name'] as String,
          for (final item in (data[2] as Json)['event_types'] as List)
            'event:${item['code']}': item['name'] as String,
        };
        loading = false;
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = BackendStrings(s.language).error(e);
        });
      }
    }
  }

  Future<void> openReport() async {
    if (!await civicLogin(context, widget.api, s) || !mounted) return;
    final formRepo = ServerCivicRepository(
      widget.api,
      ownerId: widget.api.user!.id,
    );
    CivicDraft? draft;
    try {
      draft = await formRepo.loadDraft();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(BackendStrings(s.language).error(e))),
        );
      }
      return;
    }
    if (!mounted) return;
    final result = await Navigator.push<Json>(
      context,
      MaterialPageRoute(
        builder: (_) => CivicForm(
          api: widget.api,
          repository: formRepo,
          draft: draft ?? CivicDraft(city: city),
          categories: categories,
          cities: cities,
          s: s,
          tilesEnabled: widget.tilesEnabled,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => tab = 1);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CivicDetail(
            api: widget.api,
            repo: repo,
            id: result['id'],
            own: true,
            names: names,
            s: s,
          ),
        ),
      );
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    widget.api.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('qogam', style: TextStyle(fontWeight: FontWeight.w800)),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          tooltip: ServiceStrings(s.language).t('services'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ServiceCatalog(
                api: widget.api,
                strings: ServiceStrings(s.language),
                city: city,
              ),
            ),
          ),
        ),
        Center(
          child: Text(s.t('server'), style: const TextStyle(color: teal)),
        ),
        TextButton(
          onPressed: widget.changeLanguage,
          child: Text(s.language == 'ru' ? 'Қаз' : 'Рус'),
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ApiErrorBox(error),
              FilledButton(onPressed: loadCatalog, child: Text(s.t('retry'))),
            ],
          )
        : IndexedStack(
            index: tab,
            children: [
              CivicNearby(
                key: ValueKey('${city}_${s.language}'),
                api: widget.api,
                repo: repo,
                city: city,
                categories: categories,
                names: names,
                s: s,
                tilesEnabled: widget.tilesEnabled,
                citySelector: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: city,
                  decoration: InputDecoration(labelText: s.t('city')),
                  items: cities
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.code,
                          child: Text(c.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) async {
                    if (value == null || value == city) return;
                    await widget.preferences.setString('civic.city', value);
                    if (mounted) setState(() => city = value);
                  },
                ),
              ),
              CivicRequests(
                key: ValueKey('requests_${widget.api.user?.id}_${tab == 1}'),
                api: widget.api,
                repo: repo,
                names: names,
                s: s,
                onDraft: openReport,
              ),
              CivicHouseList(api: widget.api, city: city, s: s),
              BackendProfile(
                api: widget.api,
                s: widget.strings,
                changeLanguage: widget.changeLanguage,
                tilesEnabled: widget.tilesEnabled,
                demoFeatures: false,
                restoreSession: false,
              ),
            ],
          ),
    bottomNavigationBar: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (tab < 2)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: FilledButton.icon(
              onPressed: loading ? null : openReport,
              icon: const Icon(Icons.add),
              label: Text(s.t('newReport')),
            ),
          ),
        NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (v) => setState(() => tab = v),
          destinations: [
            for (final item in [
              ('near', Icons.location_on_outlined),
              ('mine', Icons.assignment_outlined),
              ('home', Icons.apartment_outlined),
              ('profile', Icons.person_outline),
            ])
              NavigationDestination(icon: Icon(item.$2), label: s.t(item.$1)),
          ],
        ),
      ],
    ),
  );
}

class CivicCard extends StatelessWidget {
  final Json item;
  final String status;
  final VoidCallback onTap;
  const CivicCard({
    super.key,
    required this.item,
    required this.status,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Panel(
    child: InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item['title'] ?? item['display_number'] ?? '',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            item['address_text'] ?? item['display_number'] ?? '',
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Chip(
                label: Text(status),
                backgroundColor: soft,
                side: BorderSide.none,
              ),
              if (item['supporters_count'] != null)
                Chip(
                  avatar: const Icon(Icons.people_outline, size: 18),
                  label: Text('${item['supporters_count']}'),
                  side: BorderSide.none,
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class CivicNearby extends StatefulWidget {
  final QogamApi api;
  final ServerCivicRepository repo;
  final String city;
  final List<ApiCategory> categories;
  final Map<String, String> names;
  final CivicStrings s;
  final bool tilesEnabled;
  final Widget citySelector;
  const CivicNearby({
    super.key,
    required this.api,
    required this.repo,
    required this.city,
    required this.categories,
    required this.names,
    required this.s,
    required this.citySelector,
    this.tilesEnabled = true,
  });
  @override
  State<CivicNearby> createState() => _CivicNearbyState();
}

class _CivicNearbyState extends State<CivicNearby> {
  String? category, bbox, error;
  String state = 'all', search = '';
  bool mapView = true, loading = true, moreLoading = false;
  CivicPage? page;
  int generation = 0;
  Timer? debounce;
  final searchController = TextEditingController();
  Map<String, String?> get filters => {
    'city_code': widget.city,
    'category_code': category,
    'state': state,
    'q': search.isEmpty ? null : search,
    'bbox': bbox,
  };
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool more = false}) async {
    final stamp = ++generation;
    setState(() {
      if (more) {
        moreLoading = true;
      } else {
        loading = true;
      }
      error = null;
    });
    try {
      final data = await widget.repo.problems({
        ...filters,
        if (more) 'cursor': page?.cursor,
      });
      if (!mounted || stamp != generation) return;
      setState(() {
        page = more
            ? CivicPage.fromJson({
                'items': [...page!.items, ...data.items],
                'next_cursor': data.cursor,
                'has_more': data.hasMore,
              })
            : data;
        loading = false;
        moreLoading = false;
      });
    } catch (e) {
      if (mounted && stamp == generation) {
        setState(() {
          error = BackendStrings(widget.s.language).error(e);
          loading = false;
          moreLoading = false;
        });
      }
    }
  }

  Future<void> open(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CivicDetail(
          api: widget.api,
          repo: widget.repo,
          id: id,
          names: widget.names,
          s: widget.s,
        ),
      ),
    );
    if (mounted) await load();
  }

  @override
  void dispose() {
    debounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      PageHeading(widget.s.t('near')),
      widget.citySelector,
      const SizedBox(height: 12),
      TextField(
        controller: searchController,
        maxLength: 100,
        decoration: InputDecoration(
          labelText: widget.s.t('search'),
          prefixIcon: const Icon(Icons.search),
        ),
        onChanged: (text) {
          debounce?.cancel();
          debounce = Timer(const Duration(milliseconds: 400), () {
            if (mounted) {
              setState(() => search = text.trim());
              load();
            }
          });
        },
      ),
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: category ?? '',
        decoration: InputDecoration(labelText: widget.s.t('categoryField')),
        items: [
          DropdownMenuItem(value: '', child: Text(widget.s.t('allCategories'))),
          for (final c in widget.categories)
            DropdownMenuItem(value: c.code, child: Text(c.name)),
        ],
        onChanged: (v) {
          setState(() => category = v == '' ? null : v);
          load();
        },
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: state,
        items: [
          for (final p in [
            ('all', 'allStates'),
            ('open', 'openState'),
            ('resolved', 'resolvedState'),
          ])
            DropdownMenuItem(value: p.$1, child: Text(widget.s.t(p.$2))),
        ],
        onChanged: (v) {
          setState(() => state = v!);
          load();
        },
      ),
      const SizedBox(height: 12),
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(value: true, label: Text(widget.s.t('map'))),
          ButtonSegment(value: false, label: Text(widget.s.t('list'))),
        ],
        selected: {mapView},
        onSelectionChanged: (v) {
          setState(() => mapView = v.first);
          if (!mapView) load();
        },
      ),
      const SizedBox(height: 12),
      if (mapView)
        SizedBox(
          height: 380,
          child: CivicMap(
            api: widget.api,
            filters: filters,
            s: widget.s,
            tilesEnabled: widget.tilesEnabled,
            onOpen: open,
            onBounds: (v) {
              bbox = v;
            },
          ),
        ),
      if (!mapView) ...[
        if (loading) const Center(child: CircularProgressIndicator()),
        ApiErrorBox(error),
        if (error != null)
          FilledButton(onPressed: load, child: Text(widget.s.t('retry'))),
        if (!loading && page?.items.isEmpty == true)
          EmptyState(
            icon: Icons.search_off,
            title: widget.s.t('empty'),
            body: widget.s.t('noResultsBody'),
          ),
        for (final item in page?.items ?? <Json>[])
          CivicCard(
            item: item,
            status: widget.names[item['status']] ?? item['status'],
            onTap: () => open(item['id']),
          ),
        if (page?.hasMore == true)
          OutlinedButton(
            onPressed: loading || moreLoading ? null : () => load(more: true),
            child: Text(widget.s.t(moreLoading ? 'loading' : 'more')),
          ),
      ],
    ],
  );
}

class CivicMap extends StatefulWidget {
  final QogamApi api;
  final Map<String, String?> filters;
  final CivicStrings s;
  final bool tilesEnabled;
  final ValueChanged<String> onOpen, onBounds;
  const CivicMap({
    super.key,
    required this.api,
    required this.filters,
    required this.s,
    required this.onOpen,
    required this.onBounds,
    this.tilesEnabled = true,
  });
  @override
  State<CivicMap> createState() => _CivicMapState();
}

class _CivicMapState extends State<CivicMap> {
  final controller = MapController();
  Json? data;
  String? error;
  bool loading = false, ready = false;
  Timer? debounce;
  int generation = 0;
  LatLng? center;
  double initialZoom = 15;
  @override
  void initState() {
    super.initState();
    loadCity();
  }

  Future<void> loadCity() async {
    try {
      final detail =
          await widget.api.request(
                'GET',
                '/v1/cities/${widget.filters['city_code']}',
              )
              as Json;
      if (mounted) {
        setState(() {
          center = LatLng(
            (detail['center']['lat'] as num).toDouble(),
            (detail['center']['lng'] as num).toDouble(),
          );
          initialZoom = (detail['default_zoom'] as num).toDouble();
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = BackendStrings(widget.s.language).error(e));
      }
    }
  }

  @override
  void didUpdateWidget(CivicMap old) {
    super.didUpdateWidget(old);
    if (old.filters.toString() != widget.filters.toString() && ready) {
      schedule();
    }
  }

  void schedule() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 400), load);
  }

  Future<void> load() async {
    if (!ready) return;
    final b = controller.camera.visibleBounds;
    final bbox = '${b.west},${b.south},${b.east},${b.north}';
    widget.onBounds(bbox);
    final stamp = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.api.request(
        'GET',
        '/v1/problems/map',
        query: {
          ...widget.filters,
          'bbox': bbox,
          'zoom': controller.camera.zoom.floor().clamp(0, 20).toString(),
        },
      );
      if (mounted && stamp == generation) {
        setState(() {
          data = result as Json;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted && stamp == generation) {
        setState(() {
          error = BackendStrings(widget.s.language).error(e);
          loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => center == null
      ? Center(
          child: error == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ApiErrorBox(error),
                    TextButton(
                      onPressed: loadCity,
                      child: Text(widget.s.t('retry')),
                    ),
                  ],
                ),
        )
      : ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              FlutterMap(
                mapController: controller,
                options: MapOptions(
                  initialCenter: center!,
                  initialZoom: initialZoom,
                  onMapReady: () {
                    ready = true;
                    load();
                  },
                  onPositionChanged: (_, gesture) {
                    if (gesture) schedule();
                  },
                ),
                children: [
                  if (widget.tilesEnabled)
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'kz.qogam.qogam',
                    ),
                  MarkerLayer(
                    markers: [
                      for (final marker in (data?['markers'] as List? ?? []))
                        Marker(
                          point: LatLng(
                            (marker['location']['lat'] as num).toDouble(),
                            (marker['location']['lng'] as num).toDouble(),
                          ),
                          width: 48,
                          height: 48,
                          child: IconButton.filled(
                            onPressed: () => widget.onOpen(marker['id']),
                            tooltip: widget.s.t('details'),
                            icon: const Icon(Icons.location_on),
                          ),
                        ),
                      for (final cluster in (data?['clusters'] as List? ?? []))
                        Marker(
                          point: LatLng(
                            (cluster['center']['lat'] as num).toDouble(),
                            (cluster['center']['lng'] as num).toDouble(),
                          ),
                          width: 60,
                          height: 48,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(48, 48),
                            ),
                            onPressed: () {
                              final box = cluster['bbox'] as List;
                              controller.fitCamera(
                                CameraFit.bounds(
                                  bounds: LatLngBounds(
                                    LatLng(
                                      (box[1] as num).toDouble(),
                                      (box[0] as num).toDouble(),
                                    ),
                                    LatLng(
                                      (box[3] as num).toDouble(),
                                      (box[2] as num).toDouble(),
                                    ),
                                  ),
                                ),
                              );
                              schedule();
                            },
                            child: Text('${cluster['count']}'),
                          ),
                        ),
                    ],
                  ),
                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution(
                        'OpenStreetMap',
                        onTap: () => launchUrl(
                          Uri.parse('https://www.openstreetmap.org/copyright'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (loading)
                const Positioned(
                  top: 12,
                  left: 12,
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (error != null)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 32,
                  child: Material(
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      title: Text(error!),
                      trailing: IconButton(
                        onPressed: load,
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
}

class CivicRequests extends StatefulWidget {
  final QogamApi api;
  final ServerCivicRepository repo;
  final Map<String, String> names;
  final CivicStrings s;
  final VoidCallback onDraft;
  const CivicRequests({
    super.key,
    required this.api,
    required this.repo,
    required this.names,
    required this.s,
    required this.onDraft,
  });
  @override
  State<CivicRequests> createState() => _CivicRequestsState();
}

class _CivicRequestsState extends State<CivicRequests> {
  CivicPage? page;
  bool joined = false, busy = false, hasDraft = false;
  String? error;
  @override
  void initState() {
    super.initState();
    if (widget.api.user != null) load();
  }

  Future<void> load({bool more = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = joined
          ? await widget.repo.joined(cursor: more ? page?.cursor : null)
          : await widget.repo.mine(cursor: more ? page?.cursor : null);
      final draft = await widget.repo.loadDraft();
      if (mounted) {
        setState(() {
          hasDraft = draft != null;
          page = more
              ? CivicPage.fromJson({
                  'items': [...page!.items, ...result.items],
                  'next_cursor': result.cursor,
                  'has_more': result.hasMore,
                })
              : result;
        });
      }
    } catch (e) {
      if (mounted) error = BackendStrings(widget.s.language).error(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      PageHeading(widget.s.t('mine')),
      if (widget.api.user == null)
        FilledButton(
          onPressed: () async {
            if (await civicLogin(context, widget.api, widget.s) && mounted) {
              load();
            }
          },
          child: Text(widget.s.t('loginRequired')),
        )
      else ...[
        if (hasDraft)
          Panel(
            child: ListTile(
              title: Text(widget.s.t('resume')),
              trailing: const Icon(Icons.edit_outlined),
              onTap: widget.onDraft,
            ),
          ),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(widget.s.t('own'))),
            ButtonSegment(value: true, label: Text(widget.s.t('joined'))),
          ],
          selected: {joined},
          onSelectionChanged: busy
              ? null
              : (v) {
                  setState(() {
                    joined = v.first;
                    page = null;
                  });
                  load();
                },
        ),
        const SizedBox(height: 12),
        if (busy) const Center(child: CircularProgressIndicator()),
        ApiErrorBox(error),
        if (error != null)
          FilledButton(onPressed: load, child: Text(widget.s.t('retry'))),
        if (!busy && page?.items.isEmpty == true)
          Panel(child: Text(widget.s.t('empty'))),
        for (final item in page?.items ?? <Json>[])
          CivicCard(
            item: item,
            status: widget.names[item['status']] ?? item['status'],
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CivicDetail(
                    api: widget.api,
                    repo: widget.repo,
                    id: item['id'],
                    own: !joined,
                    names: widget.names,
                    s: widget.s,
                  ),
                ),
              );
              if (mounted) load();
            },
          ),
        if (page?.hasMore == true)
          OutlinedButton(
            onPressed: busy ? null : () => load(more: true),
            child: Text(widget.s.t('more')),
          ),
      ],
    ],
  );
}

class CivicHouseList extends StatefulWidget {
  final QogamApi api;
  final String city;
  final CivicStrings s;
  const CivicHouseList({
    super.key,
    required this.api,
    required this.city,
    required this.s,
  });
  @override
  State<CivicHouseList> createState() => _CivicHouseListState();
}

class _CivicHouseListState extends State<CivicHouseList> {
  List<Json> houses = [];
  String? error;
  bool busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(CivicHouseList old) {
    super.didUpdateWidget(old);
    if (old.city != widget.city) load();
  }

  Future<void> load() async {
    try {
      final data =
          await widget.api.request(
                'GET',
                '/v1/houses',
                query: {'city_code': widget.city},
                authenticated: widget.api.user != null,
              )
              as Json;
      if (mounted) {
        setState(() {
          houses = (data['items'] as List).cast<Json>();
          busy = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = BackendStrings(widget.s.language).error(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      PageHeading(widget.s.t('home')),
      if (busy) const Center(child: CircularProgressIndicator()),
      ApiErrorBox(error),
      if (error != null)
        FilledButton(onPressed: load, child: Text(widget.s.t('retry'))),
      if (!busy && houses.isEmpty && error == null)
        Panel(child: Text(widget.s.t('empty'))),
      for (final house in houses)
        Panel(
          child: ListTile(
            title: Text(house['address_text']),
            subtitle: Text(house['organization']?['name'] ?? ''),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              if (!await civicLogin(context, widget.api, widget.s) ||
                  !context.mounted) {
                return;
              }
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ServiceEntityPage(
                    api: widget.api,
                    strings: ServiceStrings(widget.s.language),
                    source: ApiContract.operation('GET', '/v1/houses'),
                    item: house,
                  ),
                ),
              );
            },
          ),
        ),
    ],
  );
}
