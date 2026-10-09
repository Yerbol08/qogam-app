import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'backend.dart';
import 'backend_pages.dart';
import 'backend_strings.dart';
import 'civic_repository.dart';
import 'civic_strings.dart';
import 'civic_home.dart';
import 'ui.dart';

class CivicDetail extends StatefulWidget {
  final QogamApi api;
  final CivicRepository repo;
  final String id;
  final bool own;
  final Map<String, String> names;
  final CivicStrings s;
  const CivicDetail({
    super.key,
    required this.api,
    required this.repo,
    required this.id,
    required this.names,
    required this.s,
    this.own = false,
  });
  @override
  State<CivicDetail> createState() => _CivicDetailState();
}

class _CivicDetailState extends State<CivicDetail> {
  Json? data;
  CivicPage? history;
  bool busy = true, acting = false;
  String? error;
  CivicStrings get s => widget.s;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await Future.wait<Object>([
        widget.repo.detail(widget.id, own: widget.own),
        widget.repo.history(widget.id, own: widget.own),
      ]);
      if (mounted) {
        setState(() {
          data = result[0] as Json;
          history = result[1] as CivicPage;
          busy = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = BackendStrings(s.language).error(e);
        });
      }
    }
  }

  Future<void> action(
    Future<void> Function() callback, {
    bool reload = true,
  }) async {
    if (acting) return;
    if (!await civicLogin(context, widget.api, s) || !mounted) return;
    setState(() {
      acting = true;
      error = null;
    });
    try {
      await callback();
      if (reload) await load();
    } catch (e) {
      if (mounted) setState(() => error = BackendStrings(s.language).error(e));
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  String date(String? value) => value == null
      ? ''
      : DateFormat.yMMMd(
          s.language,
        ).add_Hm().format(DateTime.parse(value).toLocal());
  Future<String?> textInput(String heading, {int max = 2000}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(heading),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          maxLength: max,
          decoration: InputDecoration(labelText: s.t('explanation')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(s.t('send')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(data?['display_number'] ?? s.t('details'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (busy) const Center(child: CircularProgressIndicator()),
        ApiErrorBox(error),
        if (error != null)
          FilledButton(
            onPressed: acting ? null : load,
            child: Text(s.t('retry')),
          ),
        if (data != null) ...[
          PageHeading(
            data!['title'],
            subtitle: widget.own ? s.t('private') : null,
          ),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Chip(
                  label: Text(widget.names[data!['status']] ?? data!['status']),
                  backgroundColor: soft,
                ),
                const SizedBox(height: 16),
                Text(data!['description']),
                const SizedBox(height: 16),
                Text(data!['address_text']),
                Text(
                  date(data!['created_at']),
                  style: const TextStyle(color: muted),
                ),
                if (data!['supporters_count'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '${s.t('supports')}: ${data!['supporters_count']}',
                    ),
                  ),
                if (data!['organization'] != null)
                  Text(data!['organization']['name']),
                if (data!['due_at'] != null) Text(date(data!['due_at'])),
              ],
            ),
          ),
          for (final media in data!['media'] as List? ?? [])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  media['url'],
                  fit: BoxFit.cover,
                  errorBuilder: (_, error, stack) => const SizedBox(
                    height: 100,
                    child: Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
            ),
          if (data!['moderation_reason'] != null)
            Panel(
              child: Text(
                data!['moderation_reason']['text'] ??
                    data!['moderation_reason']['code'],
              ),
            ),
          if (data!['info_request'] != null) ...[
            Panel(child: Text(data!['info_request']['question'] ?? '')),
            FilledButton(
              onPressed: acting
                  ? null
                  : () async {
                      final text = await textInput(s.t('clarify'));
                      if (text == null || text.isEmpty || !mounted) return;
                      await action(() async {
                        await widget.api.request(
                          'POST',
                          '/v1/me/reports/${widget.id}/clarifications',
                          authenticated: true,
                          body: {
                            'expected_revision': data!['revision'],
                            'text': text,
                            'media_ids': <String>[],
                          },
                        );
                      });
                    },
              child: Text(s.t('clarify')),
            ),
          ],
          if (data!['result'] != null)
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data!['result']['comment'] ?? ''),
                  Text(date(data!['result']['resolved_at'])),
                  for (final media in data!['result']['media'] as List)
                    Image.network(
                      media['url'],
                      errorBuilder: (_, error, stack) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
                ],
              ),
            ),
          if (!widget.own) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('subscription')),
              value: data!['subscribed_by_me'] ?? false,
              onChanged: acting
                  ? null
                  : (value) => action(() async {
                      await widget.api.request(
                        value ? 'PUT' : 'DELETE',
                        '/v1/me/subscriptions/problems/${widget.id}',
                        authenticated: true,
                      );
                    }),
            ),
            if (data!['status'] == 'resolved') ...[
              OutlinedButton(
                onPressed: acting
                    ? null
                    : () => action(() async {
                        await widget.api.request(
                          'POST',
                          '/v1/problems/${widget.id}/feedback',
                          authenticated: true,
                          body: {
                            'outcome': 'confirmed',
                            'media_ids': <String>[],
                          },
                        );
                      }),
                child: Text(s.t('confirmResult')),
              ),
              OutlinedButton(
                onPressed: acting
                    ? null
                    : () async {
                        final text = await textInput(s.t('stillPresent'));
                        if (text == null || text.isEmpty || !mounted) return;
                        await action(() async {
                          await widget.api.request(
                            'POST',
                            '/v1/problems/${widget.id}/feedback',
                            authenticated: true,
                            body: {
                              'outcome': 'still_present',
                              'text': text,
                              'media_ids': <String>[],
                            },
                          );
                        });
                      },
                child: Text(s.t('stillPresent')),
              ),
            ],
            TextButton(
              onPressed: acting
                  ? null
                  : () async {
                      final text = await textInput(s.t('flag'), max: 1000);
                      if (text == null || text.isEmpty || !mounted) return;
                      await action(() async {
                        await widget.api.request(
                          'POST',
                          '/v1/problems/${widget.id}/flags',
                          authenticated: true,
                          body: {'reason_code': 'other', 'text': text},
                        );
                      });
                    },
              child: Text(s.t('flag')),
            ),
          ],
          PageHeading(s.t('history')),
          for (final event in history?.items ?? <Json>[])
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.names['event:${event['event_type']}'] ??
                        event['event_type'],
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    date(event['occurred_at']),
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                  if ((event['public_comment'] ?? event['comment']) != null)
                    Text(event['public_comment'] ?? event['comment']),
                ],
              ),
            ),
          if (history?.hasMore == true)
            OutlinedButton(
              onPressed: acting
                  ? null
                  : () => action(() async {
                      final next = await widget.repo.history(
                        widget.id,
                        own: widget.own,
                        cursor: history!.cursor,
                      );
                      if (mounted) {
                        setState(
                          () => history = CivicPage.fromJson({
                            'items': [...history!.items, ...next.items],
                            'next_cursor': next.cursor,
                            'has_more': next.hasMore,
                          }),
                        );
                      }
                    }, reload: false),
              child: Text(s.t('more')),
            ),
          if (widget.own &&
              ![
                'withdrawn',
                'rejected',
                'hidden',
                'published',
                'merged',
              ].contains(data!['moderation_state']))
            TextButton(
              onPressed: acting
                  ? null
                  : () async {
                      if (!await confirmAction(
                            context,
                            BackendStrings(s.language),
                            s.t('withdraw'),
                            s.t('withdrawBody'),
                          ) ||
                          !mounted) {
                        return;
                      }
                      await action(() async {
                        await widget.api.request(
                          'POST',
                          '/v1/me/reports/${widget.id}/withdraw',
                          authenticated: true,
                          body: {'expected_revision': data!['revision']},
                        );
                      });
                    },
              child: Text(s.t('withdraw')),
            ),
        ],
      ],
    ),
    bottomNavigationBar: !widget.own && data != null
        ? BottomAction(
            label: s.t(data!['joined_by_me'] == true ? 'joined' : 'join'),
            busy: acting,
            onPressed: data!['joined_by_me'] == true
                ? null
                : () => action(() async {
                    final result = await widget.repo.join(widget.id);
                    if (mounted) setState(() => data = {...data!, ...result});
                  }),
          )
        : null,
  );
}
