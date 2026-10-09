import 'dart:async';
import 'package:flutter/material.dart';
import 'backend.dart';
import 'backend_pages.dart';
import 'backend_strings.dart';
import 'civic_repository.dart';
import 'civic_strings.dart';
import 'nearby.dart';
import 'strings.dart';
import 'ui.dart';

class CivicForm extends StatefulWidget {
  final QogamApi api;
  final CivicRepository repository;
  final CivicDraft draft;
  final List<ApiCategory> categories;
  final List<ApiCity> cities;
  final CivicStrings s;
  final bool tilesEnabled;
  const CivicForm({
    super.key,
    required this.api,
    required this.repository,
    required this.draft,
    required this.categories,
    required this.cities,
    required this.s,
    this.tilesEnabled = true,
  });
  @override
  State<CivicForm> createState() => _CivicFormState();
}

class _CivicFormState extends State<CivicForm> {
  late final draft = widget.draft;
  late final description = TextEditingController(text: draft.description);
  late final title = TextEditingController(text: draft.title);
  late final address = TextEditingController(text: draft.address);
  CivicStrings get s => widget.s;
  int step = 0;
  bool busy = false, leaveAllowed = false;
  String? error, saveError;
  Timer? debounce;
  Future<void> writes = Future.value();
  List<Json> addresses = [];
  bool geoBusy = false;
  @override
  void initState() {
    super.initState();
    if (draft.uncertain) step = 2;
  }

  bool get editable => !busy && !draft.uncertain;
  void changed() {
    draft.description = description.text;
    draft.title = title.text;
    draft.address = address.text;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 350), persist);
    setState(() {});
  }

  Future<void> persist() {
    final snapshot = CivicDraft.fromJson(draft.stored());
    final task = writes.then((_) => widget.repository.saveDraft(snapshot));
    writes = task.catchError((Object e) {
      if (mounted) setState(() => saveError = s.t('draftSaveError'));
    });
    return task;
  }

  Future<void> exit() async {
    if (busy) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('leaveForm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'keep'),
            child: Text(s.t('keepEditing')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: Text(s.t('saveDraft')),
          ),
          if (!draft.uncertain)
            TextButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: Text(s.t('discardDraft')),
            ),
        ],
      ),
    );
    if (choice == null || choice == 'keep' || !mounted) return;
    debounce?.cancel();
    try {
      if (choice == 'save') {
        await persist();
      } else {
        await writes;
        await widget.repository.saveDraft(null);
      }
      if (!mounted) return;
      setState(() => leaveAllowed = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    } catch (e) {
      if (mounted) setState(() => saveError = s.t('draftSaveError'));
    }
  }

  Future<void> advance() async {
    if (busy) return;
    if (draft.validate(step).isNotEmpty ||
        !widget.categories.any((c) => c.code == draft.category)) {
      setState(() => error = s.t('validation'));
      return;
    }
    if (step < 2) {
      debounce?.cancel();
      setState(() => busy = true);
      try {
        await persist();
        if (mounted) {
          setState(() {
            step++;
            error = null;
          });
        }
      } catch (_) {
        return;
      } finally {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => busy = false);
        });
      }
      return;
    }
    debounce?.cancel();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await writes;
      final result = await widget.repository.submit(draft);
      if (mounted) {
        setState(() => leaveAllowed = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context, result);
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = BackendStrings(s.language).error(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> findAddress() async {
    if (address.text.trim().isEmpty) return;
    setState(() => geoBusy = true);
    try {
      final result = await widget.api.request(
        'GET',
        '/v1/geo/search',
        query: {'q': address.text.trim(), 'city_code': draft.city},
      );
      if (mounted) setState(() => addresses = (result as List).cast<Json>());
    } catch (e) {
      if (mounted) setState(() => error = BackendStrings(s.language).error(e));
    } finally {
      if (mounted) setState(() => geoBusy = false);
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    description.dispose();
    title.dispose();
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leaveAllowed,
    onPopInvokedWithResult: (popped, _) {
      if (!popped) exit();
    },
    child: Scaffold(
      appBar: AppBar(title: Text(s.t('newReport'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < 3; i++)
                ChoiceChip(
                  label: Text(
                    '${i + 1}. ${s.t(['descriptionStep', 'placeStep', 'reviewStep'][i])}',
                  ),
                  selected: step == i,
                  onSelected: editable && i < step
                      ? (v) => setState(() => step = i)
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (draft.uncertain) Panel(child: Text(s.t('uncertain'))),
          if (step == 0) ...[
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: widget.cities.any((c) => c.code == draft.city)
                  ? draft.city
                  : null,
              decoration: InputDecoration(labelText: s.t('city')),
              items: widget.cities
                  .map(
                    (c) => DropdownMenuItem(value: c.code, child: Text(c.name)),
                  )
                  .toList(),
              onChanged: editable
                  ? (v) {
                      draft.city = v!;
                      draft.latitude = null;
                      draft.longitude = null;
                      draft.confirmed = false;
                      changed();
                    }
                  : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue:
                  widget.categories.any(
                    (c) => c.code == draft.category && c.parent != null,
                  )
                  ? draft.category
                  : null,
              decoration: InputDecoration(labelText: s.t('categoryField')),
              items: widget.categories
                  .where((c) => c.parent != null)
                  .map(
                    (c) => DropdownMenuItem(value: c.code, child: Text(c.name)),
                  )
                  .toList(),
              onChanged: editable
                  ? (v) {
                      draft.category = v;
                      changed();
                    }
                  : null,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: title,
              enabled: editable,
              maxLength: 120,
              decoration: InputDecoration(labelText: s.t('titleField')),
              onChanged: (_) => changed(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: description,
              enabled: editable,
              minLines: 5,
              maxLines: 10,
              decoration: InputDecoration(
                labelText: s.t('descriptionField'),
                helperText: '${description.text.trim().runes.length}/2000',
              ),
              onChanged: (_) => changed(),
            ),
          ],
          if (step == 1) ...[
            TextField(
              controller: address,
              enabled: editable,
              maxLength: 300,
              decoration: InputDecoration(labelText: s.t('addressField')),
              onChanged: (_) {
                draft.confirmed = false;
                changed();
              },
            ),
            OutlinedButton.icon(
              onPressed: editable && !geoBusy ? findAddress : null,
              icon: const Icon(Icons.search),
              label: Text(s.t(geoBusy ? 'loading' : 'geoSearch')),
            ),
            for (final candidate in addresses)
              ListTile(
                title: Text(
                  candidate['address_text'] ?? candidate['label'] ?? '',
                ),
                onTap: editable
                    ? () {
                        final point = candidate['location'];
                        address.text =
                            candidate['address_text'] ??
                            candidate['label'] ??
                            '';
                        draft.latitude = (point['lat'] as num).toDouble();
                        draft.longitude = (point['lng'] as num).toDouble();
                        draft.confirmed = false;
                        addresses = [];
                        changed();
                      }
                    : null,
              ),
            const SizedBox(height: 12),
            AbsorbPointer(
              absorbing: !editable,
              child: SizedBox(
                height: 300,
                child: LocationPicker(
                  s: Strings(s.language),
                  latitude: draft.latitude,
                  longitude: draft.longitude,
                  tilesEnabled: widget.tilesEnabled,
                  onPick: (p) {
                    draft.latitude = p.latitude;
                    draft.longitude = p.longitude;
                    draft.confirmed = false;
                    changed();
                  },
                ),
              ),
            ),
            if (draft.latitude != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${draft.latitude!.toStringAsFixed(5)}, ${draft.longitude!.toStringAsFixed(5)}',
                ),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('confirmPoint')),
              value: draft.confirmed,
              onChanged: editable && draft.latitude != null
                  ? (v) {
                      draft.confirmed = v == true;
                      changed();
                    }
                  : null,
            ),
          ],
          if (step == 2) ...[
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.categories
                            .where((c) => c.code == draft.category)
                            .firstOrNull
                            ?.name ??
                        s.t('categoryField'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(draft.title),
                  Text(draft.description),
                  const SizedBox(height: 16),
                  Text(draft.address),
                  if (draft.latitude != null)
                    Text('${draft.latitude}, ${draft.longitude}'),
                ],
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('publication')),
              value: draft.consent,
              onChanged: editable
                  ? (v) {
                      draft.consent = v == true;
                      changed();
                    }
                  : null,
            ),
            Text(s.t('pendingNote'), style: const TextStyle(color: muted)),
          ],
          ApiErrorBox(error),
          ApiErrorBox(saveError),
          if (saveError != null)
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () async {
                      try {
                        await persist();
                        if (mounted) setState(() => saveError = null);
                      } catch (_) {
                        return;
                      }
                    },
              child: Text(s.t('retry')),
            ),
          const SizedBox(height: 12),
        ],
      ),
      bottomNavigationBar: BottomAction(
        label: s.t(
          draft.uncertain
              ? 'checkSubmission'
              : step == 2
              ? 'send'
              : 'continue',
        ),
        onPressed: advance,
        busy: busy,
        hint: s.t('draftSaved'),
      ),
    ),
  );
}
