import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'backend.dart';
import 'backend_strings.dart';
import 'nearby.dart';
import 'strings.dart';
import 'ui.dart';

Future<bool> confirmAction(
  BuildContext context,
  BackendStrings b,
  String title,
  String body,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(b.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(b.t('delete')),
          ),
        ],
      ),
    ) ??
    false;

class ApiErrorBox extends StatelessWidget {
  final String? error;
  const ApiErrorBox(this.error, {super.key});
  @override
  Widget build(BuildContext context) => error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Semantics(
            liveRegion: true,
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        );
}

class BackendProfile extends StatefulWidget {
  final QogamApi api;
  final Strings s;
  final VoidCallback changeLanguage;
  final bool tilesEnabled;
  final bool demoFeatures, restoreSession;
  const BackendProfile({
    super.key,
    required this.api,
    required this.s,
    required this.changeLanguage,
    this.tilesEnabled = true,
    this.demoFeatures = true,
    this.restoreSession = true,
  });
  @override
  State<BackendProfile> createState() => _BackendProfileState();
}

class _BackendProfileState extends State<BackendProfile> {
  BackendStrings get b => BackendStrings(widget.s.language);
  bool busy = true;
  String? error;
  ApiUser? profile;
  @override
  void initState() {
    super.initState();
    widget.api.addListener(changed);
    initialize();
  }

  void changed() {
    if (mounted) {
      setState(() {
        if (widget.api.user == null) profile = null;
      });
    }
  }

  Future<void> initialize() async {
    await run(() async {
      if (widget.restoreSession) await widget.api.restore();
      if (widget.api.user != null) profile = await widget.api.getMe();
    });
  }

  Future<void> run(Future<void> Function() action, {String? success}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (mounted && success != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (e) {
      if (mounted) error = b.error(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted && widget.api.user != null) {
      await run(() async {
        profile = await widget.api.getMe();
      });
    }
  }

  @override
  void dispose() {
    widget.api.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = profile ?? widget.api.user;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        PageHeading(b.t('account'), subtitle: b.t('accountBody')),
        Panel(
          child: Column(
            children: [
              const CircleAvatar(
                radius: 34,
                backgroundColor: soft,
                child: Icon(
                  Icons.person_outline_rounded,
                  color: teal,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                user?.name ?? b.t('account'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (user?.phone != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(user!.phone!),
                ),
              ApiErrorBox(error),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              if (user == null && !busy)
                FilledButton.icon(
                  onPressed: () => open(
                    LoginPage(
                      api: widget.api,
                      b: b,
                      legalRequired: !widget.demoFeatures,
                    ),
                  ),
                  icon: const Icon(Icons.login_rounded),
                  label: Text(b.t('login')),
                ),
              if (error != null && !busy)
                TextButton(
                  onPressed: () => run(() async {
                    if (widget.api.user != null) {
                      profile = await widget.api.getMe();
                    } else {
                      await widget.api.restore();
                    }
                  }),
                  child: Text(b.t('retry')),
                ),
            ],
          ),
        ),
        if (user != null) ...[
          tile(
            Icons.edit_outlined,
            'edit',
            () => open(
              EditProfilePage(
                api: widget.api,
                user: user,
                b: b,
                onLocale: (locale) {
                  if (locale != widget.s.language) widget.changeLanguage();
                },
              ),
            ),
          ),
          tile(
            Icons.place_outlined,
            'places',
            () => open(
              PlacesPage(
                api: widget.api,
                b: b,
                tilesEnabled: widget.tilesEnabled,
              ),
            ),
          ),
          tile(
            Icons.fact_check_outlined,
            'consentsTitle',
            () => open(ConsentsPage(api: widget.api, b: b)),
          ),
          tile(
            Icons.download_outlined,
            'export',
            () => open(ExportPage(api: widget.api, b: b)),
          ),
          tile(
            Icons.notifications_outlined,
            'device',
            () => open(DevicePage(api: widget.api, b: b)),
          ),
          tile(
            Icons.refresh_rounded,
            'refreshSession',
            () => run(() async {
              await widget.api.refreshSession();
              profile = await widget.api.getMe();
            }, success: b.t('sessionUpdated')),
          ),
        ],
        tile(
          Icons.category_outlined,
          'catalog',
          () => open(CatalogPage(api: widget.api, b: b)),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.s.t('language'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'ru', label: Text('Русский')),
                  ButtonSegment(value: 'kk', label: Text('Қазақша')),
                ],
                selected: {widget.s.language},
                onSelectionChanged: busy
                    ? null
                    : (value) async {
                        if (value.first == widget.s.language) return;
                        if (widget.api.user != null) {
                          await run(() async {
                            profile = await widget.api.patchMe(
                              locale: value.first,
                            );
                            widget.changeLanguage();
                          });
                        } else {
                          widget.changeLanguage();
                        }
                      },
              ),
            ],
          ),
        ),
        Panel(
          child: Text(
            b.t(widget.demoFeatures ? 'demoNotice' : 'serverNotice'),
            style: const TextStyle(color: muted),
          ),
        ),
        if (user != null) ...[
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => run(() async {
                    await widget.api.logout();
                    profile = null;
                  }),
            icon: const Icon(Icons.logout),
            label: Text(b.t('logout')),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    if (await confirmAction(
                          context,
                          b,
                          b.t('deleteAccount'),
                          b.t('deleteAccountBody'),
                        ) &&
                        mounted) {
                      await run(() async {
                        await widget.api.deleteMe();
                        profile = null;
                      });
                    }
                  },
            child: Text(
              b.t('deleteAccount'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ],
    );
  }

  Widget tile(IconData icon, String key, VoidCallback onTap) => Panel(
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: teal),
      title: Text(b.t(key)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: busy ? null : onTap,
    ),
  );
}

class LoginPage extends StatefulWidget {
  final QogamApi api;
  final BackendStrings b;
  final bool legalRequired;
  const LoginPage({
    super.key,
    required this.api,
    required this.b,
    this.legalRequired = false,
  });
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final phone = TextEditingController(), code = TextEditingController();
  BackendStrings get b => widget.b;
  ApiMeta? meta;
  List<Json> legal = [];
  final consents = <String>{};
  bool sent = false, busy = false;
  String? error;
  int cooldown = 0;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    loadMeta();
  }

  Future<void> loadMeta() => action(() async {
    final next = await widget.api.meta();
    final docs = widget.legalRequired
        ? await widget.api.request(
                'GET',
                '/v1/legal/documents',
                query: {'language': b.language},
              )
              as List
        : <Json>[];
    if (mounted) {
      meta = next;
      legal = docs.cast<Json>();
    }
  });
  Future<void> action(Future<void> Function() callback) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await callback();
    } catch (e) {
      if (mounted) {
        error = sent && e is ApiException && e.status == 401
            ? b.t('badCode')
            : b.error(e);
        if (e is ApiException && e.status == 429) {
          startCooldown(e.retryAfter ?? 60);
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void startCooldown(int seconds) {
    timer?.cancel();
    cooldown = seconds.clamp(1, 3600);
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        cooldown--;
        if (cooldown <= 0) t.cancel();
      });
    });
  }

  Future<void> send() => action(() async {
    final number = phone.text.replaceAll(RegExp(r'[\s()\-]'), '');
    await widget.api.requestOtp(number);
    if (mounted) {
      phone.text = number;
      sent = true;
      code.clear();
      startCooldown(60);
    }
  });
  @override
  void dispose() {
    timer?.cancel();
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(b.t('login'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        PageHeading(
          sent ? b.t('codeLabel') : b.t('phoneLabel'),
          subtitle: sent ? '${b.t('sent')} ${phone.text}' : b.t('accountBody'),
        ),
        if (!sent)
          TextField(
            controller: phone,
            enabled: !busy,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: InputDecoration(
              labelText: b.t('phoneLabel'),
              hintText: b.t('phoneHint'),
            ),
          ),
        if (sent) ...[
          TextField(
            controller: code,
            enabled: !busy,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 6,
            decoration: InputDecoration(labelText: b.t('codeLabel')),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => setState(() {
                    sent = false;
                    error = null;
                    code.clear();
                  }),
            child: Text(b.t('changePhone')),
          ),
          TextButton(
            onPressed: busy || cooldown > 0 ? null : send,
            child: Text(
              '${b.t('resend')}${cooldown > 0 ? ' ($cooldown)' : ''}',
            ),
          ),
        ],
        for (final document in legal)
          TextButton.icon(
            icon: const Icon(Icons.description_outlined),
            label: Text(document['title']),
            onPressed: () async {
              if (document['body'] != null) {
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(document['title']),
                    content: SingleChildScrollView(
                      child: SelectableText(document['body']),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(b.t('cancel')),
                      ),
                    ],
                  ),
                );
              } else if (document['url'] != null) {
                final url = Uri.tryParse(document['url']);
                if (url != null && ['http', 'https'].contains(url.scheme)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              }
            },
          ),
        if (meta != null)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.t('consentsTitle'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text('${b.t('consentVersion')}: ${meta!.consentVersion}'),
                for (final purpose in ['processing', 'gov_transfer', 'push'])
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: consents.contains(purpose),
                    title: Text(b.t(purpose)),
                    onChanged: busy
                        ? null
                        : (value) => setState(() {
                            value == true
                                ? consents.add(purpose)
                                : consents.remove(purpose);
                          }),
                  ),
                Text(
                  b.t('consentNote'),
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ApiErrorBox(error),
        if (meta == null && !busy)
          OutlinedButton(onPressed: loadMeta, child: Text(b.t('retry'))),
        FilledButton(
          onPressed: busy || meta == null || (!sent && cooldown > 0)
              ? null
              : () {
                  if (!sent) {
                    send();
                    return;
                  }
                  action(() async {
                    await widget.api.verifyOtp(
                      phone.text,
                      code.text.trim(),
                      meta!.consentVersion,
                      consents,
                    );
                    if (context.mounted) Navigator.pop(context);
                  });
                },
          child: Text(
            busy
                ? b.t('loading')
                : sent
                ? b.t('verify')
                : '${b.t('sendCode')}${cooldown > 0 ? ' ($cooldown)' : ''}',
          ),
        ),
      ],
    ),
  );
}

class EditProfilePage extends StatefulWidget {
  final QogamApi api;
  final ApiUser user;
  final BackendStrings b;
  final ValueChanged<String> onLocale;
  const EditProfilePage({
    super.key,
    required this.api,
    required this.user,
    required this.b,
    required this.onLocale,
  });
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final name = TextEditingController(text: widget.user.name ?? '');
  late final city = TextEditingController(text: widget.user.city ?? '');
  late String locale = ['ru', 'kk'].contains(widget.user.locale)
      ? widget.user.locale
      : widget.b.language;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    city.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.b.t('edit'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: name,
          enabled: !busy,
          maxLength: 64,
          decoration: InputDecoration(labelText: widget.b.t('nameLabel')),
        ),
        TextField(
          controller: city,
          enabled: !busy,
          maxLength: 32,
          decoration: InputDecoration(labelText: widget.b.t('cityCode')),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: locale,
          decoration: InputDecoration(labelText: widget.b.t('localeLabel')),
          items: const [
            DropdownMenuItem(value: 'ru', child: Text('Русский')),
            DropdownMenuItem(value: 'kk', child: Text('Қазақша')),
          ],
          onChanged: busy ? null : (v) => setState(() => locale = v!),
        ),
        ApiErrorBox(error),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() {
                    busy = true;
                    error = null;
                  });
                  try {
                    await widget.api.patchMe(
                      name: name.text.trim().isEmpty ? null : name.text,
                      clearName: name.text.trim().isEmpty,
                      locale: locale,
                      cityCode: city.text.trim().isEmpty
                          ? null
                          : city.text.trim(),
                      clearCity: city.text.trim().isEmpty,
                    );
                    if (context.mounted) {
                      widget.onLocale(locale);
                      Navigator.pop(context);
                    }
                  } catch (e) {
                    if (mounted) setState(() => error = widget.b.error(e));
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(widget.b.t(busy ? 'loading' : 'save')),
        ),
      ],
    ),
  );
}

class CatalogPage extends StatefulWidget {
  final QogamApi api;
  final BackendStrings b;
  const CatalogPage({super.key, required this.api, required this.b});
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  List<ApiCategory> categories = [];
  List<ApiCity> cities = [];
  ApiMeta? meta;
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await Future.wait<Object>([
        widget.api.categories(),
        widget.api.cities(),
        widget.api.meta(),
      ]);
      if (mounted) {
        categories = result[0] as List<ApiCategory>;
        cities = result[1] as List<ApiCity>;
        meta = result[2] as ApiMeta;
      }
    } catch (e) {
      if (mounted) error = widget.b.error(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.b.t('catalog'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(widget.b.t('catalogBody')),
        const SizedBox(height: 20),
        if (busy) const Center(child: CircularProgressIndicator()),
        ApiErrorBox(error),
        if (error != null)
          FilledButton(onPressed: load, child: Text(widget.b.t('retry'))),
        if (meta != null)
          Text(
            '${widget.b.t('consentVersion')}: ${meta!.consentVersion} • ${meta!.environment}',
          ),
        PageHeading(widget.b.t('cities')),
        for (final city in cities) Panel(child: Text(city.name)),
        PageHeading(widget.b.t('categories')),
        for (final category in categories)
          Padding(
            padding: EdgeInsets.only(left: category.parent == null ? 0 : 12),
            child: Panel(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(category.name),
                subtitle: Text('${widget.b.t('sla')}: ${category.sla}'),
                leading: Icon(
                  category.parent == null
                      ? Icons.category_outlined
                      : Icons.subdirectory_arrow_right,
                  color: teal,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class PlacesPage extends StatefulWidget {
  final QogamApi api;
  final BackendStrings b;
  final bool tilesEnabled;
  const PlacesPage({
    super.key,
    required this.api,
    required this.b,
    this.tilesEnabled = true,
  });
  @override
  State<PlacesPage> createState() => _PlacesPageState();
}

class _PlacesPageState extends State<PlacesPage> {
  List<ApiPlace> places = [];
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await widget.api.places();
      if (mounted) places = value;
    } catch (e) {
      if (mounted) error = widget.b.error(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.b.t('places'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(widget.b.t('placesBody')),
        const SizedBox(height: 16),
        if (busy) const Center(child: CircularProgressIndicator()),
        ApiErrorBox(error),
        if (error != null && !busy)
          OutlinedButton(onPressed: load, child: Text(widget.b.t('retry'))),
        if (!busy && error == null && places.isEmpty)
          Panel(child: Text(widget.b.t('noPlaces'))),
        for (final place in places)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.name ?? widget.b.t(place.label),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  '${place.latitude.toStringAsFixed(5)}, ${place.longitude.toStringAsFixed(5)} • ${place.radius} м',
                ),
                if (place.address != null) Text(place.address!),
                if (place.city != null) Text(place.city!),
                Text(
                  widget.b.t(
                    place.notificationsEnabled
                        ? 'notificationsOn'
                        : 'notificationsOff',
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(widget.b.t('edit')),
                  onPressed: busy
                      ? null
                      : () async {
                          final changed = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AddPlacePage(
                                api: widget.api,
                                b: widget.b,
                                tilesEnabled: widget.tilesEnabled,
                                place: place,
                              ),
                            ),
                          );
                          if (changed == true) await load();
                        },
                ),
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          if (!await confirmAction(
                                context,
                                widget.b,
                                widget.b.t('delete'),
                                widget.b.t('deletePlaceBody'),
                              ) ||
                              !mounted) {
                            return;
                          }
                          setState(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            await widget.api.deletePlace(place.id);
                            if (mounted) await load();
                          } catch (e) {
                            if (mounted) {
                              setState(() => error = widget.b.error(e));
                            }
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        },
                  icon: const Icon(Icons.delete_outline),
                  label: Text(widget.b.t('delete')),
                ),
              ],
            ),
          ),
        FilledButton.icon(
          onPressed: busy
              ? null
              : () async {
                  final added = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddPlacePage(
                        api: widget.api,
                        b: widget.b,
                        tilesEnabled: widget.tilesEnabled,
                      ),
                    ),
                  );
                  if (mounted && added == true) await load();
                },
          icon: const Icon(Icons.add_location_alt_outlined),
          label: Text(widget.b.t('addPlace')),
        ),
      ],
    ),
  );
}

class AddPlacePage extends StatefulWidget {
  final QogamApi api;
  final BackendStrings b;
  final bool tilesEnabled;
  final ApiPlace? place;
  const AddPlacePage({
    super.key,
    required this.api,
    required this.b,
    this.tilesEnabled = true,
    this.place,
  });
  @override
  State<AddPlacePage> createState() => _AddPlacePageState();
}

class _AddPlacePageState extends State<AddPlacePage> {
  late final radius = TextEditingController(
    text: '${widget.place?.radius ?? 300}',
  );
  late final name = TextEditingController(text: widget.place?.name ?? '');
  late final address = TextEditingController(text: widget.place?.address ?? '');
  late String label = widget.place?.label ?? 'home';
  late double? lat = widget.place?.latitude, lng = widget.place?.longitude;
  late bool confirmed = widget.place != null;
  late bool notifications = widget.place?.notificationsEnabled ?? true;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    radius.dispose();
    name.dispose();
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.b.t(widget.place == null ? 'addPlace' : 'edit')),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: name,
          enabled: !busy,
          maxLength: 64,
          decoration: InputDecoration(labelText: widget.b.t('nameLabel')),
        ),
        TextField(
          controller: address,
          enabled: !busy,
          maxLength: 300,
          decoration: InputDecoration(labelText: widget.b.t('addressLabel')),
        ),
        SwitchListTile(
          title: Text(widget.b.t('notificationsOn')),
          value: notifications,
          onChanged: busy ? null : (v) => setState(() => notifications = v),
        ),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: label,
          decoration: InputDecoration(labelText: widget.b.t('placeLabel')),
          items: ['home', 'work', 'other']
              .map(
                (v) => DropdownMenuItem(value: v, child: Text(widget.b.t(v))),
              )
              .toList(),
          onChanged: busy ? null : (v) => setState(() => label = v!),
        ),
        const SizedBox(height: 20),
        Text(widget.b.t('pickPoint')),
        const SizedBox(height: 12),
        AbsorbPointer(
          absorbing: busy,
          child: SizedBox(
            height: 300,
            child: LocationPicker(
              s: Strings(widget.b.language),
              latitude: lat,
              longitude: lng,
              tilesEnabled: widget.tilesEnabled,
              onPick: (point) => setState(() {
                lat = point.latitude;
                lng = point.longitude;
                confirmed = false;
              }),
            ),
          ),
        ),
        if (lat != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}',
            ),
          ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(widget.b.t('confirmPoint')),
          value: confirmed,
          onChanged: lat == null || busy
              ? null
              : (v) => setState(() => confirmed = v == true),
        ),
        TextField(
          controller: radius,
          enabled: !busy,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: widget.b.t('radius')),
        ),
        ApiErrorBox(error),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  if (!confirmed ||
                      lat == null ||
                      int.tryParse(radius.text) == null) {
                    setState(() => error = widget.b.t('place'));
                    return;
                  }
                  setState(() {
                    busy = true;
                    error = null;
                  });
                  try {
                    if (widget.place != null) {
                      await widget.api.patchPlace(widget.place!.id, {
                        'label': label,
                        'name': name.text.trim().isEmpty
                            ? null
                            : name.text.trim(),
                        'address_text': address.text.trim().isEmpty
                            ? null
                            : address.text.trim(),
                        'location': {'lat': lat!, 'lng': lng!},
                        'radius_m': int.parse(radius.text),
                        'notifications_enabled': notifications,
                      });
                    } else {
                      await widget.api.createPlace(
                        label: label,
                        latitude: lat!,
                        longitude: lng!,
                        radius: int.parse(radius.text),
                        name: name.text.trim(),
                        address: address.text.trim(),
                        notificationsEnabled: notifications,
                      );
                    }
                    if (context.mounted) Navigator.pop(context, true);
                  } catch (e) {
                    if (mounted) setState(() => error = widget.b.error(e));
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(widget.b.t(busy ? 'loading' : 'save')),
        ),
      ],
    ),
  );
}

class ExportPage extends StatefulWidget {
  final QogamApi api;
  final BackendStrings b;
  const ExportPage({super.key, required this.api, required this.b});
  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  String? data, error;
  bool busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
      data = null;
    });
    try {
      final value = await widget.api.exportMe();
      if (mounted) data = const JsonEncoder.withIndent('  ').convert(value);
    } catch (e) {
      if (mounted) error = widget.b.error(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.b.t('export'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(widget.b.t('exportBody')),
        const SizedBox(height: 16),
        if (busy) const Center(child: CircularProgressIndicator()),
        ApiErrorBox(error),
        if (error != null && !busy)
          FilledButton(onPressed: load, child: Text(widget.b.t('retry'))),
        if (data != null) ...[
          Builder(
            builder: (buttonContext) => FilledButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        final box =
                            buttonContext.findRenderObject() as RenderBox;
                        await SharePlus.instance.share(
                          ShareParams(
                            files: [
                              XFile.fromData(
                                Uint8List.fromList(utf8.encode(data!)),
                                mimeType: 'application/json',
                              ),
                            ],
                            fileNameOverrides: const ['qogam-export.json'],
                            sharePositionOrigin:
                                box.localToGlobal(Offset.zero) & box.size,
                          ),
                        );
                      } catch (e) {
                        if (mounted) error = widget.b.error(e);
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              icon: const Icon(Icons.ios_share),
              label: Text(widget.b.t('shareExport')),
            ),
          ),
          const SizedBox(height: 16),
          SelectableText(
            data!,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ],
    ),
  );
}

class DevicePage extends StatefulWidget {
  final QogamApi api;
  final BackendStrings b;
  const DevicePage({super.key, required this.api, required this.b});
  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  final token = TextEditingController();
  late String platform = Theme.of(context).platform == TargetPlatform.iOS
      ? 'ios'
      : 'android';
  bool busy = false;
  String? error;
  @override
  void dispose() {
    token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.b.t('device'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(widget.b.t('deviceBody')),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: platform,
          decoration: InputDecoration(labelText: widget.b.t('platform')),
          items: const [
            DropdownMenuItem(value: 'android', child: Text('Android')),
            DropdownMenuItem(value: 'ios', child: Text('iOS')),
          ],
          onChanged: busy ? null : (v) => setState(() => platform = v!),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: token,
          enabled: !busy,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: 512,
          obscureText: true,
          decoration: InputDecoration(labelText: widget.b.t('tokenLabel')),
        ),
        ApiErrorBox(error),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() {
                    busy = true;
                    error = null;
                  });
                  try {
                    await widget.api.putDevice(
                      platform: platform,
                      token: token.text.trim(),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(widget.b.t('deviceSaved'))),
                      );
                      Navigator.pop(context);
                    }
                  } catch (e) {
                    if (mounted) setState(() => error = widget.b.error(e));
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(widget.b.t(busy ? 'loading' : 'register')),
        ),
        TextButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() {
                    busy = true;
                    error = null;
                  });
                  try {
                    await widget.api.deleteDevice(token.text.trim());
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (mounted) setState(() => error = widget.b.error(e));
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(widget.b.t('unbindDevice')),
        ),
      ],
    ),
  );
}

class ConsentsPage extends StatefulWidget {
  final QogamApi api;
  final BackendStrings b;
  const ConsentsPage({super.key, required this.api, required this.b});
  @override
  State<ConsentsPage> createState() => _ConsentsPageState();
}

class _ConsentsPageState extends State<ConsentsPage> {
  List<ApiConsent> values = [];
  ApiMeta? meta;
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final m = await widget.api.meta();
      final v = await widget.api.consents();
      if (mounted) {
        setState(() {
          meta = m;
          values = v;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = widget.b.error(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> update(ApiConsent consent, bool granted) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final v = await widget.api.putConsent(
        consent.purpose,
        granted: granted,
        version: meta!.consentVersion,
      );
      await widget.api.getMe();
      if (mounted) setState(() => values = v);
    } catch (e) {
      if (mounted) setState(() => error = widget.b.error(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.b.t('consentsTitle'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (busy) const LinearProgressIndicator(),
        ApiErrorBox(error),
        if (error != null)
          TextButton(
            onPressed: busy ? null : load,
            child: Text(widget.b.t('retry')),
          ),
        if (meta != null)
          Text('${widget.b.t('consentVersion')}: ${meta!.consentVersion}'),
        Text(widget.b.t('requiredConsentNote')),
        for (final consent in values)
          Panel(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(widget.b.t(consent.purpose)),
                  subtitle: Text(consent.version ?? '—'),
                  value: consent.granted,
                  onChanged: busy || consent.required
                      ? null
                      : (v) => update(consent, v),
                ),
                if (consent.required &&
                    (!consent.granted ||
                        consent.version != meta?.consentVersion))
                  FilledButton(
                    onPressed: busy ? null : () => update(consent, true),
                    child: Text(widget.b.t('acceptCurrentConsent')),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}
