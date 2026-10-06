import 'package:flutter/material.dart';
import 'domain.dart';
import 'nearby.dart';
import 'strings.dart';
import 'ui.dart';

class RequestsView extends StatefulWidget {
  final List<Problem> own, public;
  final Set<String> joined;
  final Draft? draft;
  final Strings s;
  final VoidCallback onDraft;
  final ValueChanged<Problem> onOpen;
  const RequestsView({
    super.key,
    required this.own,
    required this.public,
    required this.joined,
    required this.draft,
    required this.s,
    required this.onDraft,
    required this.onOpen,
  });
  @override
  State<RequestsView> createState() => _RequestsViewState();
}

class _RequestsViewState extends State<RequestsView> {
  int filter = 0;
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final hasDraft =
        widget.draft != null &&
        (widget.draft!.category != null ||
            widget.draft!.description.isNotEmpty ||
            widget.draft!.address.isNotEmpty);
    final supported = widget.public
        .where((p) => widget.joined.contains(p.id))
        .toList();
    final counts = [widget.own.length, supported.length, hasDraft ? 1 : 0];
    final keys = ['own', 'joinedList', 'drafts'];
    final items = filter == 0 ? widget.own : supported;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        PageHeading(s.t('mine'), subtitle: s.t('mineSubtitle')),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    showCheckmark: false,
                    label: Text('${s.t(keys[i])} · ${counts[i]}'),
                    selected: filter == i,
                    onSelected: (_) => setState(() => filter = i),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (hasDraft && (filter == 0 || filter == 2))
          Panel(
            child: InkWell(
              onTap: widget.onDraft,
              borderRadius: BorderRadius.circular(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InfoRow(
                    icon: Icons.edit_note_rounded,
                    title: s.t('draftTitle'),
                    subtitle: s.t('saved'),
                  ),
                  if (widget.draft!.description.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      widget.draft!.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.t('draft'),
                          style: const TextStyle(
                            color: teal,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: teal,
                        size: 18,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (filter < 2 && items.isEmpty)
          EmptyState(
            icon: filter == 0
                ? Icons.assignment_outlined
                : Icons.people_outline_rounded,
            title: s.t(filter == 0 ? 'ownEmptyTitle' : 'joinedEmptyTitle'),
            body: s.t(filter == 0 ? 'ownEmptyBody' : 'joinedEmptyBody'),
          ),
        if (filter == 2 && !hasDraft)
          EmptyState(
            icon: Icons.edit_note_rounded,
            title: s.t('draftEmptyTitle'),
            body: s.t('draftEmptyBody'),
          ),
        if (filter < 2)
          ...items.map(
            (p) => ProblemTile(
              problem: p,
              s: s,
              joined: widget.joined.contains(p.id),
              onTap: () => widget.onOpen(p),
            ),
          ),
        const SizedBox(height: 8),
        DemoNotice(s),
      ],
    );
  }
}

class HouseView extends StatelessWidget {
  final Strings s;
  const HouseView({super.key, required this.s});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      PageHeading(s.t('home'), subtitle: s.t('homeSubtitle')),
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xff087f75), Color(0xff075c57)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.apartment_rounded,
                  color: Colors.white,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s.t('homeConnection'),
                    style: const TextStyle(
                      color: Color(0xffbde4d9),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              s.t('homeAddress'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.t('homeNote'),
              style: const TextStyle(color: Color(0xffd6eee7), fontSize: 12),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Panel(
        child: InfoRow(
          icon: Icons.lock_outline_rounded,
          title: s.t('homePrivate'),
          subtitle: s.t('homePrivateBody'),
        ),
      ),
      const SizedBox(height: 12),
      Text(s.t('news'), style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 14),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.elevator_outlined, color: teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.t('planned'),
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ),
                Text(
                  s.t('demo'),
                  style: const TextStyle(color: teal, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              s.t('lift'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(s.t('liftNote'), style: const TextStyle(color: muted)),
          ],
        ),
      ),
      Panel(
        child: InfoRow(
          icon: Icons.auto_awesome_outlined,
          title: s.t('comingNext'),
          subtitle: s.t('homeLater'),
        ),
      ),
    ],
  );
}

class ProfileView extends StatelessWidget {
  final Strings s;
  final VoidCallback changeLanguage;
  const ProfileView({super.key, required this.s, required this.changeLanguage});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      PageHeading(s.t('profile'), subtitle: s.t('profileSubtitle')),
      Panel(
        child: Column(
          children: [
            const CircleAvatar(
              radius: 36,
              backgroundColor: soft,
              child: Icon(Icons.person_outline_rounded, color: teal, size: 36),
            ),
            const SizedBox(height: 16),
            Text(s.t('user'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              s.t('profileDemoBody'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 13),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text(s.t('preferences'), style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 14),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoRow(
              icon: Icons.language_rounded,
              title: s.t('language'),
              subtitle: s.t('chooseLanguage'),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'ru', label: Text('Русский')),
                  ButtonSegment(value: 'kk', label: Text('Қазақша')),
                ],
                selected: {s.language},
                onSelectionChanged: (value) {
                  if (value.first != s.language) {
                    changeLanguage();
                  }
                },
              ),
            ),
          ],
        ),
      ),
      Panel(
        child: InfoRow(
          icon: Icons.auto_awesome_outlined,
          title: s.t('comingNext'),
          subtitle: s.t('profileLater'),
        ),
      ),
    ],
  );
}

class SuccessView extends StatelessWidget {
  final Problem problem;
  final Strings s;
  const SuccessView({super.key, required this.problem, required this.s});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(s.t('success'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 20),
        Center(
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: const BoxDecoration(
              color: soft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: teal, size: 48),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          s.t('success'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(
          s.t('successNote'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted),
        ),
        const SizedBox(height: 28),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.t('number'),
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 6),
              SelectableText(
                problem.id,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              StatusBadge(problem.status, s),
            ],
          ),
        ),
        Panel(
          child: InfoRow(
            icon: Icons.schedule_rounded,
            title: s.t('successNext'),
            subtitle: s.t('successNextBody'),
          ),
        ),
      ],
    ),
    bottomNavigationBar: BottomAction(
      label: s.t('toMine'),
      icon: Icons.assignment_outlined,
      onPressed: () => Navigator.pop(context),
    ),
  );
}
