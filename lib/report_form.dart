import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'domain.dart';
import 'nearby.dart';
import 'strings.dart';
import 'ui.dart';

class ReportForm extends StatefulWidget {
  final Draft initial;
  final QogamRepository repository;
  final Strings s;
  final VoidCallback? changeLanguage;
  final bool tilesEnabled;
  const ReportForm({
    super.key,
    required this.initial,
    required this.repository,
    required this.s,
    this.changeLanguage,
    this.tilesEnabled = true,
  });
  @override
  State<ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends State<ReportForm> {
  late Draft d = Draft.fromJson(widget.initial.toJson());
  late final description = TextEditingController(text: d.description),
      address = TextEditingController(text: d.address);
  late Strings s = widget.s;
  final scroll = ScrollController();
  int step = 0;
  bool busy = false;
  List<String> errors = [];
  Future<void> writes = Future.value();
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
    scroll.dispose();
    super.dispose();
  }

  void go(int target) {
    FocusScope.of(context).unfocus();
    setState(() {
      step = target;
      errors = [];
    });
    if (scroll.hasClients) {
      scroll.jumpTo(0);
    }
  }

  Future<void> next() async {
    if (busy) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => errors = d.validate(step: step));
    if (errors.isNotEmpty) {
      if (scroll.hasClients) {
        scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      return;
    }
    if (step < 2) {
      go(step + 1);
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

  Widget fieldTitle(String key) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      s.t(key),
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
  Widget error(String key) => errors.contains(key)
      ? Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            s.t(key),
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 13,
            ),
          ),
        )
      : const SizedBox.shrink();
  Widget check({
    required String title,
    required bool value,
    required ValueChanged<bool?>? onChanged,
  }) => Card(
    child: CheckboxListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(title, style: const TextStyle(fontSize: 14, height: 1.5)),
      value: value,
      onChanged: onChanged,
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(s.t('new')),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: busy
              ? null
              : () async {
                  if (step > 0) {
                    go(step - 1);
                  } else {
                    await writes.catchError((Object _) {});
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  }
                },
        ),
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
      ),
      body: ListView(
        controller: scroll,
        padding: const EdgeInsets.all(20),
        children: [
          FormProgress(step: step, s: s),
          const SizedBox(height: 28),
          PageHeading(
            s.t(['describeTitle', 'placeTitle', 'reviewTitle'][step]),
            subtitle: s.t(['describeHint', 'placeHint', 'reviewHint'][step]),
          ),
          if (step == 0) ...[
            fieldTitle('category'),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 10,
                runSpacing: 10,
                children: Category.values
                    .map(
                      (c) => SizedBox(
                        width: (constraints.maxWidth - 10) / 2,
                        child: Material(
                          color: d.category == c ? soft : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: d.category == c ? teal : line,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              setState(() {
                                d.category = c;
                                errors.remove('categoryError');
                              });
                              save();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Icon(categoryIcon(c), color: teal, size: 20),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      s.t(c.name),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: d.category == c
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: d.category == c ? teal : ink,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            error('categoryError'),
            const SizedBox(height: 24),
            fieldTitle('description'),
            TextField(
              controller: description,
              minLines: 4,
              maxLines: 8,
              maxLength: 2000,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: s.t('descriptionPlaceholder'),
                helperText: s.t('descriptionLength'),
                helperMaxLines: 2,
                errorText: errors.contains('descriptionError')
                    ? s.t('descriptionError')
                    : null,
              ),
              onChanged: (value) {
                setState(() {
                  d.description = value;
                  if (d.validate(step: 0).contains('descriptionError') ==
                      false) {
                    errors.remove('descriptionError');
                  }
                });
                save();
              },
            ),
            const SizedBox(height: 8),
            InfoRow(icon: Icons.shield_outlined, title: s.t('privacy')),
          ],
          if (step == 1) ...[
            TextField(
              controller: address,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: s.t('address'),
                hintText: s.t('addressPlaceholder'),
              ),
              onChanged: (value) {
                setState(() {
                  d.address = value;
                  d.confirmed = false;
                });
                save();
              },
            ),
            const SizedBox(height: 24),
            fieldTitle('point'),
            LocationPicker(
              s: s,
              latitude: d.latitude,
              longitude: d.longitude,
              tilesEnabled: widget.tilesEnabled,
              onPick: (point) {
                setState(() {
                  d.latitude = point.latitude;
                  d.longitude = point.longitude;
                  d.confirmed = false;
                });
                save();
              },
            ),
            const SizedBox(height: 12),
            InfoRow(
              icon: d.latitude == null
                  ? Icons.touch_app_outlined
                  : Icons.location_on_outlined,
              title: s.t(d.latitude == null ? 'pointMissing' : 'pointSelected'),
              subtitle: d.latitude == null
                  ? null
                  : '${d.latitude!.toStringAsFixed(5)}, ${d.longitude!.toStringAsFixed(5)}',
            ),
            const SizedBox(height: 18),
            check(
              title: s.t('confirm'),
              value: d.confirmed,
              onChanged: d.latitude == null || d.address.trim().isEmpty
                  ? null
                  : (value) {
                      setState(() {
                        d.confirmed = value ?? false;
                        if (d.confirmed) {
                          errors.remove('locationError');
                        }
                      });
                      save();
                    },
            ),
            error('locationError'),
          ],
          if (step == 2) ...[
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.t('description'),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => go(0),
                        child: Text(s.t('edit')),
                      ),
                    ],
                  ),
                  Text(
                    s.t(d.category?.name ?? 'categoryError'),
                    style: const TextStyle(
                      color: teal,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    d.description,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            Panel(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.t('place'),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => go(1),
                        child: Text(s.t('edit')),
                      ),
                    ],
                  ),
                  InfoRow(
                    icon: Icons.location_on_outlined,
                    title: d.address,
                    subtitle:
                        '${d.latitude?.toStringAsFixed(5)}, ${d.longitude?.toStringAsFixed(5)}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            InfoRow(
              icon: Icons.visibility_outlined,
              title: s.t('reviewPrivacy'),
            ),
            const SizedBox(height: 18),
            check(
              title: s.t('consent'),
              value: d.consent,
              onChanged: busy
                  ? null
                  : (value) {
                      setState(() {
                        d.consent = value ?? false;
                        if (d.consent) {
                          errors.remove('consentError');
                        }
                      });
                      save();
                    },
            ),
            error('consentError'),
          ],
          error('error'),
          const SizedBox(height: 24),
          DemoNotice(s),
        ],
      ),
      bottomNavigationBar: BottomAction(
        label: s.t(step == 2 ? 'send' : 'next'),
        icon: step == 2 ? Icons.send_outlined : Icons.arrow_forward_rounded,
        onPressed: next,
        busy: busy,
        hint: s.t('saved'),
      ),
    ),
  );
}

class FormProgress extends StatelessWidget {
  final int step;
  final Strings s;
  const FormProgress({super.key, required this.step, required this.s});
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < 3; i++)
        Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 2,
                      color: i == 0
                          ? Colors.transparent
                          : i <= step
                          ? teal
                          : line,
                    ),
                  ),
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i <= step ? teal : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: i <= step ? teal : line),
                    ),
                    child: i < step
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 16,
                          )
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              color: i <= step ? Colors.white : muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  Expanded(
                    child: Container(
                      height: 2,
                      color: i == 2
                          ? Colors.transparent
                          : i < step
                          ? teal
                          : line,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                s.t(['description', 'place', 'review'][i]),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: i == step ? teal : muted,
                  fontWeight: i == step ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
