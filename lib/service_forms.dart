import 'package:intl/intl.dart';
import 'backend_strings.dart';
import 'package:flutter/material.dart';
import 'api_contract.dart';
import 'backend.dart';
import 'service_strings.dart';
import 'media_attachments.dart';

/// A field tree retains omitted/null/value distinctions required by PATCH DTOs.
class ContractField {
  final String name;
  final Json schema;
  final bool required;
  bool included, cleared = false;
  dynamic scalar;
  late Json resolved;
  final Map<String, ContractField> children = {};
  final List<ContractField> items = [];
  String? variant;
  String mediaKind = 'photo';
  bool busy = false;
  bool get uploading =>
      busy ||
      children.values.any((c) => c.uploading) ||
      items.any((c) => c.uploading);
  ContractField(
    this.name,
    this.schema, {
    this.required = false,
    dynamic initial,
    bool supplied = false,
  }) : included = required || supplied {
    cleared = supplied && initial == null && nullable;
    resolved = ApiContract.nonNull(schema);
    final choices = resolved['oneOf'] as List?;
    if (choices != null) {
      final discriminator = resolved['discriminator'] as Json?;
      variant = initial is Map
          ? initial[discriminator?['propertyName'] ?? 'action'] as String?
          : null;
      final mapping = discriminator?['mapping'] as Json? ?? {};
      variant ??= mapping.keys.firstOrNull;
      if (variant != null) {
        resolved = ApiContract.resolve({r'$ref': mapping[variant]});
      }
    }
    scalar =
        initial ??
        resolved['const'] ??
        resolved['default'] ??
        (resolved['type'] == 'boolean' ? false : '');
    if (resolved['type'] == 'object' && resolved['properties'] is Map) {
      final properties = resolved['properties'] as Json;
      for (final e in properties.entries) {
        final childInitial = initial is Map
            ? initial[e.key]
            : (resolved['default'] is Map ? resolved['default'][e.key] : null);
        children[e.key] = ContractField(
          e.key,
          e.value as Json,
          required: (resolved['required'] as List? ?? []).contains(e.key),
          initial: childInitial,
          supplied: initial is Map && initial.containsKey(e.key),
        );
      }
    }
    if (resolved['type'] == 'array') {
      final initialItems = initial is List
          ? initial
          : resolved['default'] as List? ??
                List.filled(resolved['minItems'] ?? 0, null);
      for (int i = 0; i < initialItems.length; i++) {
        final itemName = name == 'boxes' && resolved['minItems'] == 4
            ? ['x', 'y', 'width', 'height'][i]
            : name;
        items.add(
          ContractField(
            itemName,
            resolved['items'] as Json,
            required: true,
            initial: initialItems[i],
            supplied: true,
          ),
        );
      }
    }
    if (children['action']?.scalar == 'resolve') {
      children['media_ids']?.mediaKind = 'result_photo';
    }
  }
  bool get nullable => (ApiContract.resolve(schema)['anyOf'] as List? ?? [])
      .any((s) => s['type'] == 'null');
  dynamic value() {
    if (cleared) return null;
    if (children.isNotEmpty || resolved['properties'] is Map) {
      return {
        for (final e in children.entries)
          if (e.value.included) e.key: e.value.value(),
      };
    }
    if (resolved['type'] == 'array') {
      return items.map((i) => i.value()).toList();
    }
    if (['boundary', 'area', 'service_area'].contains(name) &&
        resolved['type'] == 'object') {
      if (scalar is Map) return scalar;
      final polygons = (scalar as String).trim().split(RegExp(r'\n\s*\n')).map((
        block,
      ) {
        final ring = block.split('\n').where((s) => s.trim().isNotEmpty).map((
          line,
        ) {
          final parts = line.trim().split(RegExp(r'[,;\s]+'));
          if (parts.length != 2) throw const FormatException('point');
          final lat = double.parse(parts[0]), lng = double.parse(parts[1]);
          if (!lat.isFinite ||
              !lng.isFinite ||
              lat.abs() > 90 ||
              lng.abs() > 180) {
            throw const FormatException('point');
          }
          return [lng, lat];
        }).toList();
        if (ring.length < 3) throw const FormatException('polygon');
        if (ring.first[0] != ring.last[0] || ring.first[1] != ring.last[1]) {
          ring.add(ring.first);
        }
        return [ring];
      }).toList();
      return polygons.length == 1
          ? {'type': 'Polygon', 'coordinates': polygons.first}
          : {'type': 'MultiPolygon', 'coordinates': polygons};
    }
    if (resolved['type'] == 'integer') {
      return scalar is int ? scalar : int.parse('$scalar');
    }
    if (resolved['type'] == 'number') {
      return scalar is num ? scalar : double.parse('$scalar');
    }
    if (resolved['type'] == 'boolean') return scalar == true;
    if (resolved['type'] == 'object') {
      return scalar is Map ? scalar : <String, dynamic>{};
    }
    return '$scalar'.trim();
  }
}

class ContractFieldEditor extends StatefulWidget {
  final ContractField field;
  final ServiceStrings strings;
  final QogamApi api;
  final bool enabled;
  final VoidCallback changed;
  const ContractFieldEditor({
    super.key,
    required this.field,
    required this.strings,
    required this.api,
    required this.changed,
    this.enabled = true,
  });
  @override
  State<ContractFieldEditor> createState() => _ContractFieldEditorState();
}

class _ContractFieldEditorState extends State<ContractFieldEditor> {
  ContractField get f => widget.field;
  ServiceStrings get s => widget.strings;
  void change(VoidCallback action) {
    setState(action);
    widget.changed();
  }

  @override
  Widget build(BuildContext context) {
    if ([
      'expected_revision',
      'client_request_id',
      'client_media_id',
    ].contains(f.name)) {
      return const SizedBox.shrink();
    }
    if (f.resolved.containsKey('const')) return const SizedBox.shrink();
    final original = ApiContract.nonNull(f.schema);
    final discriminator = original['discriminator'] as Json?;
    final variants = discriminator?['mapping'] as Json?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!f.required)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.t(f.name)),
              value: f.included,
              onChanged: widget.enabled
                  ? (v) => change(() => f.included = v == true)
                  : null,
            ),
          if (f.included) ...[
            if (f.nullable && !f.required)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.t('clearValue')),
                value: f.cleared,
                onChanged: widget.enabled
                    ? (v) => change(() => f.cleared = v == true)
                    : null,
              ),
            if (!f.cleared) ...[
              if (variants != null)
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: f.variant,
                  decoration: InputDecoration(labelText: s.t('action')),
                  items: variants.keys
                      .map(
                        (k) => DropdownMenuItem(value: k, child: Text(s.t(k))),
                      )
                      .toList(),
                  onChanged: !widget.enabled
                      ? null
                      : (v) => change(() {
                          final revision =
                              f.children['expected_revision']?.scalar;
                          final replacement = ContractField(
                            f.name,
                            {r'$ref': variants[v]},
                            required: true,
                            initial: {
                              'action': v,
                              'expected_revision': ?revision,
                            },
                          );
                          f.variant = v;
                          f.resolved = replacement.resolved;
                          f.children
                            ..clear()
                            ..addAll(replacement.children);
                        }),
                ),
              if (f.children.isNotEmpty) ...[
                if (variants == null)
                  Text(
                    s.t(f.name),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Column(
                    children: [
                      for (final child in f.children.values)
                        ContractFieldEditor(
                          key: ObjectKey(child),
                          field: child,
                          strings: s,
                          api: widget.api,
                          enabled: widget.enabled,
                          changed: widget.changed,
                        ),
                    ],
                  ),
                ),
              ] else if (f.resolved['type'] == 'array') ...[
                Text(
                  s.t(f.name),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (['media_ids', 'attachment_ids'].contains(f.name))
                  MediaAttachments(
                    api: widget.api,
                    strings: s,
                    ids: f.items.map((i) => '${i.scalar}').toList(),
                    enabled: widget.enabled,
                    limit: f.resolved['maxItems'] ?? 5,
                    kind: f.mediaKind,
                    onBusyChanged: (value) {
                      f.busy = value;
                      widget.changed();
                    },
                    onChanged: (ids) => change(() {
                      f.items
                        ..clear()
                        ..addAll(
                          ids.map(
                            (id) => ContractField(
                              f.name,
                              f.resolved['items'] as Json,
                              required: true,
                              initial: id,
                            ),
                          ),
                        );
                    }),
                  )
                else ...[
                  for (int i = 0; i < f.items.length; i++)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ContractFieldEditor(
                            key: ObjectKey(f.items[i]),
                            field: f.items[i],
                            strings: s,
                            api: widget.api,
                            enabled: widget.enabled,
                            changed: widget.changed,
                          ),
                        ),
                        IconButton(
                          onPressed: widget.enabled
                              ? () => change(() => f.items.removeAt(i))
                              : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ],
                    ),
                  TextButton.icon(
                    onPressed:
                        !widget.enabled ||
                            f.items.length >= (f.resolved['maxItems'] ?? 1000)
                        ? null
                        : () => change(
                            () => f.items.add(
                              ContractField(
                                f.name,
                                f.resolved['items'] as Json,
                                required: true,
                              ),
                            ),
                          ),
                    icon: const Icon(Icons.add),
                    label: Text(s.t('create')),
                  ),
                ],
              ] else if (f.resolved['type'] == 'boolean')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    s.t(f.name == 'confirmed' ? 'publicationConsent' : f.name),
                  ),
                  value: f.scalar == true,
                  onChanged: widget.enabled
                      ? (v) => change(() => f.scalar = v)
                      : null,
                )
              else if (f.resolved['enum'] is List)
                DropdownButtonFormField<dynamic>(
                  isExpanded: true,
                  initialValue: (f.resolved['enum'] as List).contains(f.scalar)
                      ? f.scalar
                      : null,
                  decoration: InputDecoration(labelText: s.t(f.name)),
                  items: (f.resolved['enum'] as List)
                      .map(
                        (v) =>
                            DropdownMenuItem(value: v, child: Text(s.t('$v'))),
                      )
                      .toList(),
                  onChanged: widget.enabled
                      ? (v) => change(() => f.scalar = v)
                      : null,
                )
              else if (f.resolved['format'] == 'date-time' ||
                  ['start', 'end'].contains(f.name))
                ServiceDateField(
                  field: f,
                  strings: s,
                  enabled: widget.enabled,
                  onChanged: widget.changed,
                )
              else if ([
                'city_code',
                'category_code',
                'parent_code',
                'organization_id',
                'house_id',
                'house_ids',
                'cities',
                'into_problem_id',
              ].contains(f.name))
                ReferenceFieldEditor(
                  field: f,
                  api: widget.api,
                  strings: s,
                  enabled: widget.enabled,
                  onChanged: widget.changed,
                )
              else
                TextFormField(
                  initialValue: _text(f),
                  enabled: widget.enabled,
                  obscureText: ['totp', 'push_token'].contains(f.name),
                  minLines:
                      [
                        'description',
                        'body_ru',
                        'body_kk',
                        'boundary',
                        'area',
                        'service_area',
                      ].contains(f.name)
                      ? 3
                      : 1,
                  maxLines:
                      [
                        'description',
                        'body_ru',
                        'body_kk',
                        'boundary',
                        'area',
                        'service_area',
                      ].contains(f.name)
                      ? 8
                      : 1,
                  keyboardType:
                      ['number', 'integer'].contains(f.resolved['type'])
                      ? const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        )
                      : TextInputType.text,
                  decoration: InputDecoration(
                    labelText: s.t(f.name),
                    helperText: f.resolved['format'] == 'date-time'
                        ? '2026-10-10T12:00:00+05:00'
                        : ['boundary', 'area', 'service_area'].contains(f.name)
                        ? s.t('polygonHint')
                        : null,
                  ),
                  onChanged: (v) {
                    f.scalar = v;
                    widget.changed();
                  },
                ),
            ],
          ],
        ],
      ),
    );
  }

  String _text(ContractField field) {
    final value = field.scalar;
    if (value is Map &&
        ['boundary', 'area', 'service_area'].contains(field.name)) {
      final coordinates = value['coordinates'] as List? ?? [];
      final polygons = value['type'] == 'MultiPolygon'
          ? coordinates
          : [coordinates];
      return polygons
          .map(
            (p) => (p as List)
                .map(
                  (ring) => (ring as List)
                      .map((point) => '${point[1]}, ${point[0]}')
                      .join('\n'),
                )
                .join('\n\n'),
          )
          .join('\n\n');
    }
    return value is String || value is num ? '$value' : '';
  }
}

class ReferenceFieldEditor extends StatefulWidget {
  final ContractField field;
  final QogamApi api;
  final ServiceStrings strings;
  final bool enabled;
  final VoidCallback onChanged;
  const ReferenceFieldEditor({
    super.key,
    required this.field,
    required this.api,
    required this.strings,
    required this.enabled,
    required this.onChanged,
  });
  @override
  State<ReferenceFieldEditor> createState() => _ReferenceFieldEditorState();
}

class _ReferenceFieldEditorState extends State<ReferenceFieldEditor> {
  List<Json> values = [];
  bool busy = true;
  bool manual = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final route = switch (widget.field.name) {
        'category_code' || 'parent_code' => '/v1/categories',
        'city_code' || 'cities' => '/v1/cities',
        'organization_id' => '/v1/admin/organizations',
        'into_problem_id' => '/v1/staff/problems',
        _ => '/v1/houses',
      };
      final operation = ApiContract.operation('GET', route);
      final result = await ContractApi(widget.api).call(
        operation,
        query: route == '/v1/houses'
            ? {'city_code': widget.api.user?.city ?? 'astana'}
            : {},
      );
      final items = result is List ? result : (result as Json)['items'] as List;
      if (mounted) {
        setState(() {
          values = items.cast<Json>();
          busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          manual = true;
          error = BackendStrings(widget.strings.language).error(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.field, s = widget.strings;
    final code = [
      'category_code',
      'parent_code',
      'city_code',
      'cities',
    ].contains(f.name);
    final options = {
      for (final v in values)
        '${v[code ? 'code' : 'id']}':
            '${v['name'] ?? v['name_${s.language}'] ?? v['title'] ?? v['address_text'] ?? v['id']}',
    };
    if (f.scalar is String && (f.scalar as String).isNotEmpty) {
      options.putIfAbsent(f.scalar, () => '${f.scalar}');
    }
    if (manual) {
      return TextFormField(
        initialValue: f.scalar is String ? f.scalar : '',
        enabled: widget.enabled,
        decoration: InputDecoration(labelText: s.t(f.name), helperText: error),
        onChanged: (value) {
          f.scalar = value;
          widget.onChanged();
        },
      );
    }
    return Column(
      children: [
        if (busy) const LinearProgressIndicator(),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: options.containsKey(f.scalar) ? f.scalar : null,
          decoration: InputDecoration(labelText: s.t(f.name)),
          items: options.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: !widget.enabled || busy
              ? null
              : (value) {
                  setState(() => f.scalar = value);
                  widget.onChanged();
                },
        ),
        TextButton(
          onPressed: widget.enabled
              ? () => setState(() => manual = true)
              : null,
          child: Text(s.t('enterCode')),
        ),
      ],
    );
  }
}

class ServiceDateField extends StatefulWidget {
  final ContractField field;
  final ServiceStrings strings;
  final bool enabled;
  final VoidCallback onChanged;
  const ServiceDateField({
    super.key,
    required this.field,
    required this.strings,
    required this.enabled,
    required this.onChanged,
  });
  @override
  State<ServiceDateField> createState() => _ServiceDateFieldState();
}

class _ServiceDateFieldState extends State<ServiceDateField> {
  bool get timeOnly => widget.field.resolved['format'] != 'date-time';
  Future<void> pick() async {
    final parsed = DateTime.tryParse('${widget.field.scalar}')?.toLocal();
    final now = DateTime.now();
    DateTime date = parsed ?? now;
    if (!timeOnly) {
      final selected = await showDatePicker(
        context: context,
        initialDate: date.year >= 1900 && date.year <= 2200 ? date : now,
        firstDate: DateTime(1900),
        lastDate: DateTime(2200, 12, 31),
      );
      if (selected == null || !mounted) return;
      date = selected;
    }
    final parts = '${widget.field.scalar}'.split(':');
    final time = timeOnly && parts.length == 2
        ? TimeOfDay(
            hour: (int.tryParse(parts[0]) ?? now.hour).clamp(0, 23),
            minute: (int.tryParse(parts[1]) ?? now.minute).clamp(0, 59),
          )
        : TimeOfDay.fromDateTime(parsed ?? now);
    if (!mounted) return;
    final selected = await showTimePicker(context: context, initialTime: time);
    if (selected == null || !mounted) return;
    setState(
      () => widget.field.scalar = timeOnly
          ? '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}'
          : DateTime(
              date.year,
              date.month,
              date.day,
              selected.hour,
              selected.minute,
            ).toUtc().toIso8601String(),
    );
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse('${widget.field.scalar}')?.toLocal();
    final value = timeOnly
        ? '${widget.field.scalar}'
        : date == null
        ? ''
        : DateFormat.yMMMd(widget.strings.language).add_Hm().format(date);
    return InkWell(
      onTap: widget.enabled ? pick : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.strings.t(widget.field.name),
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(value.isEmpty ? '—' : value),
      ),
    );
  }
}
