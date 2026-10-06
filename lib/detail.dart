import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'domain.dart';
import 'nearby.dart';
import 'strings.dart';
import 'ui.dart';

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
  bool joined = false, busy = true, failed = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final ids = await widget.repository.joined();
      if (mounted) {
        setState(() {
          joined = ids.contains(widget.problem.id);
          busy = false;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          failed = true;
        });
      }
    }
  }

  Future<void> join() async {
    if (busy || joined) {
      return;
    }
    setState(() => busy = true);
    try {
      await widget.repository.join(widget.problem.id);
      if (mounted) {
        setState(() => joined = true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(widget.s.t('error'))));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.problem;
    final s = widget.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('details'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: soft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(categoryIcon(p.category), size: 28, color: teal),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.t(p.category.name),
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    StatusBadge(p.status, s),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(p.title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 10),
          Text(p.id, style: const TextStyle(color: muted, fontSize: 11)),
          const SizedBox(height: 24),
          if (p.description.isNotEmpty)
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.t('aboutProblem'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    p.description,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          Panel(
            child: Column(
              children: [
                InfoRow(
                  icon: Icons.location_on_outlined,
                  title: p.address,
                  subtitle: s.t('locationLabel'),
                ),
                const Divider(),
                InfoRow(
                  icon: Icons.schedule_rounded,
                  title: DateFormat.yMMMd(
                    s.language,
                  ).add_Hm().format(p.createdAt.toLocal()),
                  subtitle: s.t('created'),
                ),
              ],
            ),
          ),
          Panel(
            child: InfoRow(
              icon: Icons.people_outline_rounded,
              title: '${p.supporters + (joined ? 1 : 0)} ${s.t('residents')}',
              subtitle: s.t(joined ? 'joinedHint' : 'joinHint'),
            ),
          ),
          const SizedBox(height: 12),
          Text(s.t('history'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            s.t('historyHint'),
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Panel(
            child: Column(
              children: [
                for (var i = 0; i < p.history.length; i++)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 24,
                          child: Column(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                margin: const EdgeInsets.only(top: 5),
                                decoration: BoxDecoration(
                                  color: i == p.history.length - 1
                                      ? teal
                                      : soft,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: teal, width: 2),
                                ),
                              ),
                              if (i < p.history.length - 1)
                                Expanded(
                                  child: Container(width: 1, color: line),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              bottom: i == p.history.length - 1 ? 0 : 24,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.t(p.history[i]),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  s.t('demo'),
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          DemoNotice(s),
          const SizedBox(height: 12),
          Text(
            s.t('source'),
            style: const TextStyle(color: muted, fontSize: 11),
          ),
        ],
      ),
      bottomNavigationBar: p.published
          ? BottomAction(
              label: s.t(
                failed
                    ? 'retry'
                    : joined
                    ? 'joined'
                    : 'join',
              ),
              icon: joined
                  ? Icons.check_circle_outline_rounded
                  : Icons.add_circle_outline_rounded,
              busy: busy,
              hint: s.t(joined ? 'joinedHint' : 'joinHint'),
              onPressed: failed
                  ? load
                  : joined
                  ? null
                  : join,
            )
          : null,
    );
  }
}
