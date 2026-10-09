import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'api_contract.dart';
import 'backend.dart';
import 'backend_pages.dart';
import 'backend_strings.dart';
import 'service_forms.dart';
import 'service_strings.dart';
import 'ui.dart';

bool serviceVisible(ApiOperation operation, QogamApi api) {
  if (operation.path.startsWith('/v1/admin/')) {
    return api.mfa &&
        (operation.path.endsWith('/audit-events') &&
                [
                  'moderator',
                  'org_staff',
                  'org_admin',
                  'platform_admin',
                ].contains(api.user?.role) ||
            api.user?.role == 'platform_admin' ||
            (operation.path.endsWith('/user-restrictions') &&
                api.user?.role == 'moderator'));
  }
  if (operation.path.startsWith('/v1/staff/')) {
    if ((operation.path.startsWith('/v1/staff/reports') ||
            operation.path.startsWith('/v1/staff/media')) &&
        !['moderator', 'platform_admin'].contains(api.user?.role)) {
      return false;
    }
    return api.mfa &&
        [
          'moderator',
          'org_staff',
          'org_admin',
          'platform_admin',
        ].contains(api.user?.role);
  }
  return true;
}

Future<dynamic> openService(
  BuildContext context,
  QogamApi api,
  ServiceStrings s,
  ApiOperation operation, {
  Json path = const {},
  Json query = const {},
  Json seed = const {},
}) async {
  if (operation.authenticated && api.user == null) {
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
    if (!context.mounted || api.user == null) return null;
  }
  if (!serviceVisible(operation, api)) return null;
  final result = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => operation.method == 'GET'
          ? ServicePage(
              api: api,
              strings: s,
              operation: operation,
              path: path,
              query: query,
            )
          : ServiceFormPage(
              api: api,
              strings: s,
              operation: operation,
              path: path,
              initial: seed,
            ),
    ),
  );
  if (context.mounted &&
      operation.method == 'POST' &&
      result is Map &&
      result['id'] != null &&
      (operation.path == '/v1/staff/alerts' ||
          operation.path.startsWith('/v1/admin/') ||
          operation.path.endsWith('/requests'))) {
    final source = operation.path.endsWith('/requests')
        ? ApiContract.operation('GET', '/v1/me/house-requests')
        : operation;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceEntityPage(
          api: api,
          strings: s,
          source: source,
          item: Map<String, dynamic>.from(result),
          contextPath: path,
        ),
      ),
    );
  }
  return result;
}

class ServiceCatalog extends StatelessWidget {
  final QogamApi api;
  final ServiceStrings strings;
  final String mode;
  final String? city;
  const ServiceCatalog({
    super.key,
    required this.api,
    required this.strings,
    this.mode = 'resident',
    this.city,
  });
  List<ApiOperation> get entries {
    if (mode == 'resident') {
      return [
        for (final path in [
          '/v1/me/notifications',
          '/v1/me/notifications/unread-count',
          '/v1/me/notification-settings',
          '/v1/alerts',
          '/v1/me/subscriptions/problems',
          '/v1/me/house-memberships',
          '/v1/me/house-invitations',
          '/v1/me/house-requests',
          '/v1/houses',
        ])
          ApiContract.operation('GET', path),
      ];
    }
    return ApiContract.operations
        .where(
          (o) =>
              serviceVisible(o, api) &&
              !o.path.contains('{') &&
              (mode == 'admin'
                  ? o.path.startsWith('/v1/admin/')
                  : (o.path.startsWith('/v1/staff/') ||
                        o.path == '/v1/admin/audit-events')) &&
              (o.method == 'GET' || o.method == 'POST'),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        strings.t(
          mode == 'admin'
              ? 'adminCabinet'
              : mode == 'staff'
              ? 'staffCabinet'
              : 'services',
        ),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (mode != 'resident' && !api.mfa) Text(strings.t('mfaNeeded')),
        for (final op in entries)
          Panel(
            child: ListTile(
              leading: Icon(
                op.method == 'GET'
                    ? Icons.view_list_outlined
                    : Icons.add_circle_outline,
              ),
              title: Text(
                op.method == 'POST'
                    ? '${strings.title(op)}: ${strings.t(op.path.split('/').last)}'
                    : strings.title(op),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openService(
                context,
                api,
                strings,
                op,
                query: {
                  if (op.parameters.any((p) => p['name'] == 'city_code'))
                    'city_code': city ?? api.user?.city ?? 'astana',
                },
              ),
            ),
          ),
      ],
    ),
  );
}

class ServicePage extends StatefulWidget {
  final QogamApi api;
  final ServiceStrings strings;
  final ApiOperation operation;
  final Json path, query;
  const ServicePage({
    super.key,
    required this.api,
    required this.strings,
    required this.operation,
    this.path = const {},
    this.query = const {},
  });
  @override
  State<ServicePage> createState() => _ServicePageState();
}

class _ServicePageState extends State<ServicePage> {
  dynamic data;
  late final ownerId = widget.api.user?.id;
  final items = <dynamic>[];
  late Json query = {...widget.query};
  String? cursor, error;
  bool busy = false, hasMore = false;
  ServiceStrings get s => widget.strings;
  @override
  void initState() {
    super.initState();
    widget.api.addListener(sessionChanged);
    load();
  }

  void sessionChanged() {
    if (mounted &&
        widget.operation.authenticated &&
        widget.api.user?.id != ownerId) {
      setState(() {
        data = null;
        items.clear();
        hasMore = false;
        error = BackendStrings(s.language).t('session');
      });
    }
  }

  @override
  void dispose() {
    widget.api.removeListener(sessionChanged);
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.operation.authenticated && widget.api.user?.id != ownerId) {
        throw const ApiException(401, 'session');
      }
      final result = await ContractApi(widget.api).call(
        widget.operation,
        path: widget.path,
        query: {...query, if (more && cursor != null) 'cursor': cursor},
      );
      if (!mounted ||
          widget.operation.authenticated && widget.api.user?.id != ownerId) {
        return;
      }
      setState(() {
        data = result;
        if (!more) items.clear();
        if (result is List) items.addAll(result);
        if (result is Map && result['items'] is List) {
          items.addAll(result['items']);
        }
        cursor = result is Map ? result['next_cursor'] as String? : null;
        hasMore = result is Map && result['has_more'] == true && cursor != null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = BackendStrings(s.language).error(e);
          if (widget.operation.authenticated &&
              e is ApiException &&
              [401, 403, 404].contains(e.status)) {
            data = null;
            items.clear();
            hasMore = false;
          }
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> filters() async {
    final properties = <String, dynamic>{
      for (final p in widget.operation.parameters)
        if (p['in'] == 'query' && p['name'] != 'cursor') p['name']: p['schema'],
    };
    final field = ContractField(
      'search',
      {
        'type': 'object',
        'properties': properties,
        'required': [
          for (final p in widget.operation.parameters)
            if (p['in'] == 'query' && p['required'] == true) p['name'],
        ],
      },
      required: true,
      initial: query,
    );
    final result = await Navigator.push<Json>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            FieldEditPage(api: widget.api, strings: s, field: field),
      ),
    );
    if (result != null && mounted) {
      query = result;
      await load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final collection = data is List || data is Map && data['items'] is List;
    final children = ApiContract.operations.where(
      (o) =>
          o.path.startsWith('${widget.operation.path}/') &&
          o.path
                  .substring(widget.operation.path.length + 1)
                  .split('/')
                  .length ==
              1 &&
          o.parameters
              .where((p) => p['in'] == 'path')
              .every((p) => widget.path.containsKey(p['name'])) &&
          serviceVisible(o, widget.api),
    );
    final mutation = ApiContract.operations.where(
      (o) =>
          o.path == widget.operation.path &&
          ['PUT', 'PATCH', 'POST'].contains(o.method) &&
          serviceVisible(o, widget.api),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(s.title(widget.operation)),
        actions: [
          IconButton(
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.operation.parameters.any(
            (p) => p['in'] == 'query' && p['name'] != 'cursor',
          ))
            OutlinedButton.icon(
              onPressed: busy ? null : filters,
              icon: const Icon(Icons.tune),
              label: Text(s.t('search')),
            ),
          if (busy) const LinearProgressIndicator(),
          ApiErrorBox(error),
          if (error != null)
            TextButton(
              onPressed: busy ? null : load,
              child: Text(s.t('retry')),
            ),
          for (final op in mutation)
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      await openService(
                        context,
                        widget.api,
                        s,
                        op,
                        path: widget.path,
                        seed: !collection && data is Map
                            ? Map<String, dynamic>.from(data)
                            : {},
                      );
                      if (mounted) await load();
                    },
              icon: Icon(op.method == 'POST' ? Icons.add : Icons.edit_outlined),
              label: Text(s.title(op)),
            ),
          if (widget.operation.path == '/v1/me/notifications')
            TextButton(
              onPressed: busy || widget.api.user == null
                  ? null
                  : () async {
                      await openService(
                        context,
                        widget.api,
                        s,
                        ApiContract.operation(
                          'POST',
                          '/v1/me/notifications/read-all',
                        ),
                        seed: {
                          'up_to': DateTime.now().toUtc().toIso8601String(),
                        },
                      );
                      if (mounted) await load();
                    },
              child: Text(s.t('readAll')),
            ),
          if (collection && items.isEmpty && !busy) Text(s.t('empty')),
          if (collection)
            for (final item in items)
              Panel(
                child: item is Map
                    ? ListTile(
                        title: Text(
                          serviceItemTitle(Map<String, dynamic>.from(item), s),
                        ),
                        subtitle: Text(
                          serviceItemSubtitle(
                            Map<String, dynamic>.from(item),
                            s,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ServiceEntityPage(
                                api: widget.api,
                                strings: s,
                                source: widget.operation,
                                item: Map<String, dynamic>.from(item),
                                contextPath: widget.path,
                              ),
                            ),
                          );
                          if (mounted) await load();
                        },
                      )
                    : Text('$item'),
              ),
          if (!collection && data != null)
            ServiceDataView(api: widget.api, strings: s, data: data),
          if (!collection && data is Map)
            for (final op in children)
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () async {
                        await openService(
                          context,
                          widget.api,
                          s,
                          op,
                          path: widget.path,
                          seed: Map<String, dynamic>.from(data),
                        );
                        if (mounted) await load();
                      },
                child: Text(s.title(op)),
              ),
          if (hasMore)
            OutlinedButton(
              onPressed: busy ? null : () => load(more: true),
              child: Text(s.t('more')),
            ),
        ],
      ),
    );
  }
}

String serviceItemTitle(Json item, ServiceStrings s) {
  final inner = (item['problem'] ?? item['house']) as Json?;
  return '${item['title_${s.language}'] ?? item['title'] ?? item['name_${s.language}'] ?? item['name'] ?? item['display_name'] ?? item['address_text'] ?? inner?['title'] ?? inner?['address_text'] ?? item['display_number'] ?? item['phone'] ?? item['code'] ?? item['event_type'] ?? s.t('continue')}';
}

String serviceItemSubtitle(Json item, ServiceStrings s) => [
  if (item['status'] != null || item['state'] != null)
    s.t('${item['status'] ?? item['state']}'),
  if (item['body'] is String) item['body'],
  if (item['created_at'] is String) item['created_at'].split('T').first,
].join(' • ');

class ServiceEntityPage extends StatefulWidget {
  final QogamApi api;
  final ServiceStrings strings;
  final ApiOperation source;
  final Json item, contextPath;
  const ServiceEntityPage({
    super.key,
    required this.api,
    required this.strings,
    required this.source,
    required this.item,
    this.contextPath = const {},
  });
  @override
  State<ServiceEntityPage> createState() => _ServiceEntityPageState();
}

class _ServiceEntityPageState extends State<ServiceEntityPage> {
  late final ownerId = widget.api.user?.id;
  late Json data = {...widget.item};
  late Json path = {...widget.contextPath};
  late String base;
  String? error;
  bool busy = false;
  ServiceStrings get s => widget.strings;
  @override
  void initState() {
    super.initState();
    widget.api.addListener(sessionChanged);
    base = widget.source.path;
    final resource = base.split('/').last;
    final key = switch (resource) {
      'houses' => 'house_id',
      'alerts' => 'alert_id',
      'reports' => 'report_id',
      'problems' || 'joined-problems' || 'similar' => 'problem_id',
      'house-memberships' || 'membership-requests' => 'membership_id',
      'house-invitations' || 'invitations' => 'invitation_id',
      'house-requests' || 'requests' => 'request_id',
      'news' => 'news_id',
      'notifications' => 'notification_id',
      'categories' || 'cities' => 'code',
      'organizations' => 'organization_id',
      'routing-zones' => 'zone_id',
      'staff' => 'user_id',
      _ => 'id',
    };
    final inner = widget.item['problem'] ?? widget.item['house'];
    final id =
        widget.item[key] ??
        (key == 'code' ? widget.item['code'] : widget.item['id']) ??
        (inner is Map ? inner['id'] : null);
    if (widget.item['problem'] is Map) {
      data = Map<String, dynamic>.from(widget.item['problem']);
      path['problem_id'] = data['id'];
      base = '/v1/problems';
    }
    if (id != null) path[key] = id;
    if (widget.item['house_id'] != null) {
      path['house_id'] = widget.item['house_id'];
    }
    if (base == '/v1/me/joined-problems' || base == '/v1/problems/similar') {
      base = '/v1/problems';
    }
    if (base == '/v1/houses/{house_id}/requests') {
      base = '/v1/me/house-requests';
    }
    if (base.endsWith('membership-requests') && widget.source.staff) {
      base = '/v1/staff/house-membership-requests';
    }
    load();
  }

  void sessionChanged() {
    if (mounted &&
        widget.source.authenticated &&
        widget.api.user?.id != ownerId) {
      setState(() {
        data = {};
        error = BackendStrings(s.language).t('session');
      });
    }
  }

  @override
  void dispose() {
    widget.api.removeListener(sessionChanged);
    super.dispose();
  }

  List<ApiOperation> get related => ApiContract.operations.where((op) {
    if (!serviceVisible(op, widget.api)) return false;
    if (!op.path.startsWith('$base/')) return false;
    final suffix = op.path.substring(base.length + 1);
    if (!suffix.startsWith('{')) return false;
    if (op.parameters
        .where((p) => p['in'] == 'path')
        .any((p) => !path.containsKey(p['name']))) {
      return false;
    }
    final parts = suffix.split('/');
    return parts.length <= 2 || (base.contains('/news') && parts.length <= 2);
  }).toList();
  Future<void> load() async {
    final detail = related
        .where(
          (o) =>
              o.method == 'GET' &&
              o.path.substring(base.length + 1).split('/').length == 1,
        )
        .firstOrNull;
    if (detail == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.source.authenticated && widget.api.user?.id != ownerId) {
        throw const ApiException(401, 'session');
      }
      final result =
          await ContractApi(widget.api).call(detail, path: path) as Json;
      if (mounted &&
          (!widget.source.authenticated || widget.api.user?.id == ownerId)) {
        setState(() => data = result);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = BackendStrings(s.language).error(e);
          if (widget.source.authenticated &&
              e is ApiException &&
              [401, 403, 404].contains(e.status)) {
            data = {};
          }
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openTarget() async {
    final target = data['target'] as Json;
    final route = switch (target['type']) {
      'report' => '/v1/me/reports/{report_id}',
      'problem' => '/v1/problems/{problem_id}',
      'alert' => '/v1/alerts/{alert_id}',
      'house' => '/v1/houses/{house_id}',
      'house_request' => '/v1/me/house-requests/{request_id}',
      _ => null,
    };
    if (route != null) {
      final operation = ApiContract.operation('GET', route);
      await openService(
        context,
        widget.api,
        s,
        operation,
        path: {
          operation.parameters.firstWhere((p) => p['in'] == 'path')['name']:
              target['id'],
        },
      );
    } else if (target['type'] == 'house_news') {
      await openService(
        context,
        widget.api,
        s,
        ApiContract.operation('GET', '/v1/me/house-memberships'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ops = related.where(
      (o) =>
          !(o.method == 'GET' &&
              o.path.substring(base.length + 1).split('/').length == 1),
    );
    final houseId = path['house_id'];
    final cross = <ApiOperation>[
      if (base == '/v1/problems')
        ApiContract.operation(
          data['subscribed_by_me'] == true ? 'DELETE' : 'PUT',
          '/v1/me/subscriptions/problems/{problem_id}',
        ),
      if (base == '/v1/houses/{house_id}/news')
        ...ApiContract.operations.where(
          (o) =>
              o.path.startsWith('/v1/staff/houses/{house_id}/news/{news_id}') &&
              serviceVisible(o, widget.api),
        ),
      if (base == '/v1/alerts')
        ...ApiContract.operations.where(
          (o) =>
              o.path.startsWith('/v1/staff/alerts/{alert_id}') &&
              serviceVisible(o, widget.api),
        ),
      if (houseId != null && ['/v1/houses', '/v1/admin/houses'].contains(base))
        ...ApiContract.operations.where(
          (o) =>
              o.path.startsWith('/v1/staff/houses/{house_id}/') &&
              !o.path.contains('{news_id}') &&
              serviceVisible(o, widget.api),
        ),
      if (houseId != null && base == '/v1/me/house-memberships')
        ApiContract.operation('GET', '/v1/houses/{house_id}'),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(serviceItemTitle(data, s))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (busy) const LinearProgressIndicator(),
          ApiErrorBox(error),
          if (error != null)
            TextButton(
              onPressed: busy ? null : load,
              child: Text(s.t('retry')),
            ),
          ServiceDataView(api: widget.api, strings: s, data: data),
          if (base == '/v1/me/notifications' && data['target'] is Map)
            OutlinedButton(
              onPressed: busy ? null : openTarget,
              child: Text(s.t('continue')),
            ),
          for (final op in [...ops, ...cross])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                onPressed: busy
                    ? null
                    : () async {
                        final result = await openService(
                          context,
                          widget.api,
                          s,
                          op,
                          path: path,
                          seed: {
                            ...data,
                            if (data['revision'] != null)
                              'expected_revision': data['revision'],
                          },
                        );
                        if (!mounted) return;
                        if (op.method == 'DELETE' &&
                            base == '/v1/me/house-memberships' &&
                            result != null) {
                          if (!context.mounted) return;
                          Navigator.pop(context, true);
                          return;
                        }
                        if (result is Map && result.containsKey('revision')) {
                          setState(
                            () => data = Map<String, dynamic>.from(result),
                          );
                        }
                        await load();
                      },
                child: Text(
                  op.method == 'GET' && op.path.endsWith('news')
                      ? s.t('news')
                      : s.title(op),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ServiceDataView extends StatelessWidget {
  final QogamApi api;
  final ServiceStrings strings;
  final dynamic data;
  const ServiceDataView({
    super.key,
    required this.api,
    required this.strings,
    required this.data,
  });
  static const hidden = [
    'id',
    'client_request_id',
    'client_media_id',
    'next_cursor',
    'has_more',
    'access_token',
    'refresh_token',
    'otpauth_uri',
    'secret',
    'trace_id',
    'revision',
  ];
  @override
  Widget build(BuildContext context) {
    if (data == null) return const SizedBox.shrink();
    if (data is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in data as List)
            ServiceDataView(api: api, strings: strings, data: item),
        ],
      );
    }
    if (data is! Map) {
      return SelectableText(
        data is bool ? strings.t(data ? 'yes' : 'no') : '$data',
      );
    }
    final map = Map<String, dynamic>.from(data as Map);
    final url =
        map['preview_url'] ??
        map['thumbnail_url'] ??
        (map.containsKey('width') ? map['url'] : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (url is String)
          Image.network(
            url,
            height: 180,
            errorBuilder: (_, e, stack) =>
                const Icon(Icons.broken_image_outlined),
          ),
        if (map.containsKey('media_id') ||
            map.containsKey('width') && map.containsKey('id'))
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MediaServicePage(
                  api: api,
                  strings: strings,
                  id: map['media_id'] ?? map['id'],
                ),
              ),
            ),
            child: Text(strings.t('photos')),
          ),
        for (final e in map.entries)
          if (!hidden.contains(e.key) &&
              e.value != null &&
              !['url', 'preview_url', 'thumbnail_url'].contains(e.key))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: e.value is Map || e.value is List
                  ? ExpansionTile(
                      title: Text(strings.t(e.key)),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: ServiceDataView(
                            api: api,
                            strings: strings,
                            data: e.value,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      '${strings.t(e.key)}: ${e.value is bool
                          ? strings.t(e.value ? 'yes' : 'no')
                          : ['status', 'state', 'role', 'kind', 'type', 'visibility', 'action', 'decision', 'moderation_state', 'workflow_state', 'publication', 'event_type'].contains(e.key)
                          ? strings.t('${e.value}')
                          : '${e.value}'}',
                    ),
            ),
      ],
    );
  }
}

class FieldEditPage extends StatefulWidget {
  final QogamApi api;
  final ServiceStrings strings;
  final ContractField field;
  const FieldEditPage({
    super.key,
    required this.api,
    required this.strings,
    required this.field,
  });
  @override
  State<FieldEditPage> createState() => _FieldEditPageState();
}

class _FieldEditPageState extends State<FieldEditPage> {
  String? error;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.strings.t(widget.field.name))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ContractFieldEditor(
          field: widget.field,
          strings: widget.strings,
          api: widget.api,
          changed: () {},
        ),
        ApiErrorBox(error),
        FilledButton(
          onPressed: () {
            try {
              final value = widget.field.value() as Json;
              if (ApiContract.validate(widget.field.schema, value).isNotEmpty) {
                throw const FormatException();
              }
              Navigator.pop(context, value);
            } catch (_) {
              setState(() => error = widget.strings.t('validation'));
            }
          },
          child: Text(widget.strings.t('apply')),
        ),
      ],
    ),
  );
}

class ServiceFormPage extends StatefulWidget {
  final QogamApi api;
  final ServiceStrings strings;
  final ApiOperation operation;
  final Json path, initial;
  final SessionStore? pendingStore;
  const ServiceFormPage({
    super.key,
    required this.api,
    required this.strings,
    required this.operation,
    this.path = const {},
    this.initial = const {},
    this.pendingStore,
  });
  @override
  State<ServiceFormPage> createState() => _ServiceFormPageState();
}

class _ServiceFormPageState extends State<ServiceFormPage> {
  late ContractField field;
  bool busy = false, uncertain = false;
  Json? frozen;
  late final owner = widget.api.user?.id;
  late final pendingStore =
      widget.pendingStore ??
      SecureSessionStore(
        '${widget.api.baseUri}#pending.${owner ?? 'guest'}.${widget.operation.path}.${widget.path}',
      );
  String? error;
  ServiceStrings get s => widget.strings;
  @override
  void initState() {
    super.initState();
    widget.api.addListener(sessionChanged);
    final schema =
        widget.operation.bodySchema ??
        {'type': 'object', 'properties': <String, dynamic>{}};
    var resolved = ApiContract.nonNull(schema);
    if (resolved['oneOf'] is List) {
      resolved = ApiContract.resolve((resolved['oneOf'] as List).first as Json);
    }
    final properties = resolved['properties'] as Json? ?? {};
    final initial = <String, dynamic>{
      for (final e in widget.initial.entries)
        if (properties.containsKey(e.key)) e.key: e.value,
      if (properties.containsKey('client_request_id'))
        'client_request_id': const Uuid().v4(),
      if (properties.containsKey('expected_revision') &&
          widget.initial['revision'] != null)
        'expected_revision': widget.initial['revision'],
    };
    // Publication confirmation is never selected from existing data.
    if (properties.containsKey('confirmed')) initial['confirmed'] = false;
    field = ContractField('details', schema, required: true, initial: initial);
    if (widget.operation.method == 'PATCH') {
      for (final child in field.children.values) {
        if (!child.required) child.included = false;
      }
    }
    if (properties.containsKey('client_request_id')) restorePending();
  }

  void sessionChanged() {
    if (mounted &&
        widget.operation.authenticated &&
        widget.api.user?.id != owner) {
      setState(() {
        field = ContractField(
          'details',
          widget.operation.bodySchema ??
              {'type': 'object', 'properties': <String, dynamic>{}},
          required: true,
        );
        frozen = null;
        error = BackendStrings(s.language).t('session');
      });
    }
  }

  @override
  void dispose() {
    widget.api.removeListener(sessionChanged);
    super.dispose();
  }

  Future<void> restorePending() async {
    setState(() => busy = true);
    try {
      final raw = await pendingStore.read();
      if (raw != null && mounted && widget.api.user?.id == owner) {
        final payload = jsonDecode(raw) as Json;
        setState(() {
          frozen = payload;
          uncertain = true;
          field = ContractField(
            'details',
            widget.operation.bodySchema!,
            required: true,
            initial: payload,
          );
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = BackendStrings(s.language).error(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (busy || field.uploading) return;
    if (owner != widget.api.user?.id) {
      setState(() => error = BackendStrings(s.language).t('session'));
      return;
    }
    Json payload;
    try {
      payload = frozen ?? field.value() as Json;
      if (widget.operation.bodySchema != null &&
          ApiContract.validate(
            widget.operation.bodySchema!,
            payload,
          ).isNotEmpty) {
        throw const FormatException();
      }
    } catch (_) {
      setState(() => error = s.t('validation'));
      return;
    }
    if (widget.operation.method == 'DELETE' ||
        [
          '/withdraw',
          '/unpublish',
          '/cancel',
        ].any(widget.operation.path.endsWith)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.t('confirmChange')),
          content: Text(s.t('confirmBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.t('continue')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (payload.containsKey('client_request_id')) {
        await pendingStore.write(jsonEncode(payload));
      }
      final result = await ContractApi(widget.api).call(
        widget.operation,
        path: widget.path,
        body: widget.operation.bodySchema == null ? null : payload,
        headers: {
          if (widget.operation.path == '/v1/reports')
            'idempotency-key': payload['client_request_id'],
        },
      );
      if (!mounted) return;
      if (payload.containsKey('client_request_id')) await pendingStore.clear();
      if (!mounted) return;
      Navigator.pop(context, result ?? true);
    } catch (e) {
      if (payload.containsKey('client_request_id') &&
          e is ApiException &&
          e.status >= 400 &&
          e.status < 500 &&
          e.status != 408) {
        await pendingStore.clear();
        frozen = null;
        uncertain = false;
      }
      if (mounted) {
        setState(() {
          error = BackendStrings(s.language).error(e);
          if (payload.containsKey('client_request_id') &&
              (e is! ApiException || e.status == 0 || e.status >= 500)) {
            uncertain = true;
            frozen = payload;
          }
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && !field.uploading,
    child: Scaffold(
      appBar: AppBar(title: Text(s.title(widget.operation))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.operation.path.contains('/requests'))
            Text(s.t('privateHouse')),
          ContractFieldEditor(
            field: field,
            strings: s,
            api: widget.api,
            enabled: !busy && !uncertain,
            changed: () {
              if (mounted) setState(() {});
            },
          ),
          ApiErrorBox(error),
          if (busy) const LinearProgressIndicator(),
          FilledButton(
            onPressed: busy || field.uploading ? null : submit,
            child: Text(s.t(uncertain ? 'retry' : 'save')),
          ),
        ],
      ),
    ),
  );
}

class MediaServicePage extends StatelessWidget {
  final QogamApi api;
  final ServiceStrings strings;
  final String id;
  const MediaServicePage({
    super.key,
    required this.api,
    required this.strings,
    required this.id,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(strings.t('photos'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final op in [
          ApiContract.operation('GET', '/v1/media/{media_id}'),
          ApiContract.operation('DELETE', '/v1/media/{media_id}'),
          ...ApiContract.operations.where(
            (o) =>
                o.path.startsWith('/v1/staff/media/') && serviceVisible(o, api),
          ),
        ])
          OutlinedButton(
            onPressed: () =>
                openService(context, api, strings, op, path: {'media_id': id}),
            child: Text(
              op.method == 'GET' ? strings.t('photos') : strings.title(op),
            ),
          ),
      ],
    ),
  );
}

class MfaPage extends StatefulWidget {
  final QogamApi api;
  final ServiceStrings strings;
  const MfaPage({super.key, required this.api, required this.strings});
  @override
  State<MfaPage> createState() => _MfaPageState();
}

class _MfaPageState extends State<MfaPage> {
  final code = TextEditingController();
  Json? enrollment;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> act(bool confirm) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await ContractApi(widget.api).call(
        ApiContract.operation(
          'POST',
          confirm ? '/v1/auth/mfa/confirm' : '/v1/auth/mfa/setup',
        ),
        body: confirm ? {'totp': code.text.trim()} : null,
      );
      if (mounted) {
        if (confirm) {
          Navigator.pop(context, true);
        } else {
          setState(() => enrollment = result as Json);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = BackendStrings(widget.strings.language).error(e),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.strings.t('mfaSetup'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(widget.strings.t('mfaInstructions')),
        if (enrollment == null)
          FilledButton(
            onPressed: busy ? null : () => act(false),
            child: Text(widget.strings.t('mfaSetup')),
          ),
        if (enrollment != null) SelectableText(enrollment!['secret']),
        TextField(
          controller: code,
          enabled: !busy,
          keyboardType: TextInputType.number,
          maxLength: 6,
          obscureText: true,
          decoration: InputDecoration(labelText: widget.strings.t('totp')),
        ),
        ApiErrorBox(error),
        if (busy) const LinearProgressIndicator(),
        if (enrollment != null)
          FilledButton(
            onPressed: busy ? null : () => act(true),
            child: Text(widget.strings.t('mfaConfirm')),
          ),
      ],
    ),
  );
}
