import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'domain.dart';
import 'strings.dart';

const _teal = Color(0xff087f75);
const _ink = Color(0xff172c29);
const _muted = Color(0xff5c706a);

IconData categoryIcon(Category category) => switch (category) {
  Category.roads => Icons.construction_rounded,
  Category.lighting => Icons.lightbulb_outline_rounded,
  Category.waste => Icons.delete_outline_rounded,
  Category.water => Icons.water_drop_outlined,
  Category.yards => Icons.park_outlined,
  Category.other => Icons.more_horiz_rounded,
};

class Nearby extends StatefulWidget {
  final List<Problem> problems;
  final Set<String> joined;
  final Strings s;
  final ValueChanged<Problem> onOpen;
  final bool tilesEnabled;
  const Nearby({
    super.key,
    required this.problems,
    required this.joined,
    required this.s,
    required this.onOpen,
    this.tilesEnabled = true,
  });
  @override
  State<Nearby> createState() => _NearbyState();
}

class _NearbyState extends State<Nearby> {
  Category? category;
  String query = '';
  bool map = true;
  Strings get s => widget.s;
  List<Problem> get filtered => widget.problems
      .where(
        (p) =>
            (category == null || p.category == category) &&
            '${p.title} ${p.address}'.toLowerCase().contains(
              query.trim().toLowerCase(),
            ),
      )
      .toList();
  @override
  Widget build(BuildContext context) {
    final items = filtered;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xffe0f2eb),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.location_on_outlined,
                size: 18,
                color: _teal,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              s.t('city'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('·', style: TextStyle(color: _muted)),
            ),
            Expanded(
              child: Text(
                s.t('district'),
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          s.t('nearTitle'),
          style: const TextStyle(
            fontSize: 30,
            height: 1.12,
            letterSpacing: -1.2,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          s.t('nearSubtitle'),
          style: const TextStyle(color: _muted, fontSize: 14),
        ),
        const SizedBox(height: 12),
        TextField(
          onChanged: (value) => setState(() => query = value),
          decoration: InputDecoration(
            hintText: s.t('search'),
            hintStyle: const TextStyle(fontSize: 14, color: _muted),
            prefixIcon: const Icon(Icons.search_rounded, color: _muted),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 14,
              horizontal: 16,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xffe8eeeb),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              for (final mode in [true, false])
                Expanded(
                  child: Material(
                    color: mode == map ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => map = mode),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 8,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              mode
                                  ? Icons.map_outlined
                                  : Icons.view_list_outlined,
                              size: 18,
                              color: mode == map ? _teal : _muted,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                s.t(mode ? 'map' : 'list'),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: mode == map ? _teal : _muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final c in [null, ...Category.values])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    showCheckmark: false,
                    avatar: c == null
                        ? null
                        : Icon(
                            categoryIcon(c),
                            size: 16,
                            color: category == c ? Colors.white : _muted,
                          ),
                    label: Text(s.t(c?.name ?? 'all')),
                    selected: category == c,
                    onSelected: (_) => setState(() => category = c),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (map) ...[
          ProblemMap(
            problems: items,
            s: s,
            tilesEnabled: widget.tilesEnabled,
            onOpen: widget.onOpen,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 14, color: _muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  s.t('demoMap'),
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                s.t('around'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.4,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xffe0f2eb),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${items.length}',
                style: const TextStyle(
                  color: _teal,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text(s.t('empty'))),
          ),
        ...items.map(
          (p) => ProblemTile(
            problem: p,
            s: s,
            joined: widget.joined.contains(p.id),
            onTap: () => widget.onOpen(p),
          ),
        ),
      ],
    );
  }
}

class ProblemTile extends StatelessWidget {
  final Problem problem;
  final Strings s;
  final bool joined;
  final VoidCallback onTap;
  const ProblemTile({
    super.key,
    required this.problem,
    required this.s,
    required this.onTap,
    this.joined = false,
  });
  @override
  Widget build(BuildContext context) {
    final p = problem;
    final statusColor = p.status == 'resolved'
        ? const Color(0xff167653)
        : p.status == 'progress'
        ? const Color(0xff1263ab)
        : const Color(0xff875a13);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xffe3ebe6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xffedf5f1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        categoryIcon(p.category),
                        color: _teal,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            p.address,
                            style: const TextStyle(fontSize: 12, color: _muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: _muted,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        s.t(p.status),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.people_outline_rounded,
                          color: _muted,
                          size: 16,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${p.supporters + (joined ? 1 : 0)} ${s.t('residents')}',
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProblemMap extends StatefulWidget {
  final List<Problem> problems;
  final Strings s;
  final ValueChanged<Problem> onOpen;
  final bool tilesEnabled;
  const ProblemMap({
    super.key,
    required this.problems,
    required this.s,
    required this.onOpen,
    this.tilesEnabled = true,
  });
  @override
  State<ProblemMap> createState() => _ProblemMapState();
}

class _ProblemMapState extends State<ProblemMap> {
  static const center = LatLng(51.128, 71.428);
  final controller = MapController();
  bool failed = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void tileError() {
    if (!failed && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => failed = true);
        }
      });
    }
  }

  Widget control(IconData icon, String label, VoidCallback onTap) => SizedBox(
    width: 44,
    height: 44,
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(13),
      elevation: 2,
      shadowColor: Colors.black12,
      child: IconButton(
        tooltip: label,
        icon: Icon(icon, size: 21, color: _ink),
        onPressed: onTap,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: SizedBox(
      height: 290,
      child: Stack(
        children: [
          FlutterMap(
            mapController: controller,
            options: const MapOptions(
              initialCenter: center,
              initialZoom: 14,
              minZoom: 10,
              maxZoom: 18,
              backgroundColor: Color(0xffe5eee7),
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              if (widget.tilesEnabled)
                TileLayer(
                  urlTemplate: const String.fromEnvironment(
                    'MAP_TILE_URL',
                    defaultValue:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  ),
                  userAgentPackageName: 'kz.qogam.qogam',
                  errorTileCallback: (_, _, _) => tileError(),
                ),
              MarkerLayer(
                markers: [
                  for (final p in widget.problems)
                    if (p.latitude != null && p.longitude != null)
                      Marker(
                        point: LatLng(p.latitude!, p.longitude!),
                        width: 48,
                        height: 48,
                        child: Semantics(
                          label: '${widget.s.t('openProblem')}: ${p.title}',
                          button: true,
                          child: Material(
                            color: p.status == 'resolved'
                                ? const Color(0xff317b57)
                                : p.category == Category.lighting
                                ? const Color(0xffbd7729)
                                : _teal,
                            elevation: 4,
                            shadowColor: Colors.black26,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(
                                color: Colors.white,
                                width: 3,
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => widget.onOpen(p),
                              child: Icon(
                                categoryIcon(p.category),
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: _teal,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.s.t('demo'),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 14,
            right: 14,
            child: Column(
              children: [
                control(
                  Icons.add_rounded,
                  widget.s.t('zoomIn'),
                  () => controller.move(
                    controller.camera.center,
                    (controller.camera.zoom + 1).clamp(10, 18),
                  ),
                ),
                const SizedBox(height: 8),
                control(
                  Icons.remove_rounded,
                  widget.s.t('zoomOut'),
                  () => controller.move(
                    controller.camera.center,
                    (controller.camera.zoom - 1).clamp(10, 18),
                  ),
                ),
                const SizedBox(height: 8),
                control(
                  Icons.center_focus_strong_rounded,
                  widget.s.t('center'),
                  () => controller.move(center, 14),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 5,
            left: 8,
            child: Material(
              color: Colors.white.withValues(alpha: .94),
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                onTap: () => launchUrl(
                  Uri.parse('https://www.openstreetmap.org/copyright'),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: Text(
                    '© OpenStreetMap contributors',
                    style: TextStyle(fontSize: 10, color: _muted),
                  ),
                ),
              ),
            ),
          ),
          if (failed)
            Positioned(
              bottom: 45,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  widget.s.t('mapError'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
