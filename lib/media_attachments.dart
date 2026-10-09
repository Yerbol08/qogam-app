import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'api_contract.dart';
import 'backend.dart';
import 'backend_pages.dart';
import 'backend_strings.dart';
import 'service_strings.dart';

class PendingPhoto {
  final XFile file;
  final String id = const Uuid().v4();
  Json? result;
  String? error;
  PendingPhoto(this.file);
}

class MediaAttachments extends StatefulWidget {
  final QogamApi api;
  final ServiceStrings strings;
  final List<String> ids;
  final ValueChanged<List<String>> onChanged;
  final ValueChanged<bool>? onBusyChanged;
  final Future<List<XFile>> Function(int)? pickPhotos;
  final bool enabled;
  final int limit;
  final String kind;
  const MediaAttachments({
    super.key,
    required this.api,
    required this.strings,
    required this.ids,
    required this.onChanged,
    this.onBusyChanged,
    this.pickPhotos,
    this.enabled = true,
    this.limit = 5,
    this.kind = 'photo',
  });
  @override
  State<MediaAttachments> createState() => _MediaAttachmentsState();
}

class _MediaAttachmentsState extends State<MediaAttachments> {
  late List<String> ids = [...widget.ids];
  final photos = <PendingPhoto>[];
  final details = <String, Json>{};
  bool busy = false;
  String? error;
  ServiceStrings get s => widget.strings;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    for (final id in ids) {
      try {
        final data =
            await ContractApi(widget.api).call(
                  ApiContract.operation('GET', '/v1/media/{media_id}'),
                  path: {'media_id': id},
                )
                as Json;
        if (mounted) setState(() => details[id] = data);
      } catch (e) {
        if (mounted) {
          setState(() => error = BackendStrings(s.language).error(e));
        }
      }
    }
  }

  void setBusy(bool value) {
    if (mounted) setState(() => busy = value);
    widget.onBusyChanged?.call(value);
  }

  @override
  void didUpdateWidget(MediaAttachments oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ids.join(',') != widget.ids.join(',')) ids = [...widget.ids];
  }

  Future<void> choose() async {
    if (busy) return;
    setBusy(true);
    setState(() => error = null);
    try {
      final available =
          widget.limit -
          ids.length -
          photos.where((p) => p.result == null).length;
      final files = widget.pickPhotos == null
          ? await ImagePicker().pickMultiImage(limit: available)
          : await widget.pickPhotos!(available);
      for (final file in files.take(
        widget.limit -
            ids.length -
            photos.where((p) => p.result == null).length,
      )) {
        final photo = PendingPhoto(file);
        if (mounted) setState(() => photos.add(photo));
        await upload(photo);
      }
    } catch (e) {
      if (mounted) setState(() => error = BackendStrings(s.language).error(e));
    } finally {
      setBusy(false);
    }
  }

  Future<void> upload(PendingPhoto photo) async {
    try {
      final result =
          await ContractApi(widget.api).call(
                ApiContract.operation('POST', '/v1/media'),
                upload: ApiUpload(
                  bytes: await photo.file.readAsBytes(),
                  filename: photo.file.name,
                  clientMediaId: photo.id,
                  kind: widget.kind,
                ),
              )
              as Json;
      if (!mounted) return;
      setState(() {
        photo.result = result;
        photo.error = null;
        details[result['media_id']] = result;
      });
      if (result['status'] != 'rejected') {
        ids = {...ids, result['media_id'] as String}.toList();
        widget.onChanged([...ids]);
      }
    } catch (e) {
      if (mounted) {
        setState(() => photo.error = BackendStrings(s.language).error(e));
      }
    }
  }

  Future<void> remove(String id) async {
    setBusy(true);
    setState(() => error = null);
    try {
      if (details[id]?['attached'] == false) {
        await ContractApi(widget.api).call(
          ApiContract.operation('DELETE', '/v1/media/{media_id}'),
          path: {'media_id': id},
        );
      }
      if (mounted) {
        setState(() {
          details.remove(id);
          photos.removeWhere((p) => p.result?['media_id'] == id);
        });
        ids = ids.where((value) => value != id).toList();
        widget.onChanged([...ids]);
      }
    } catch (e) {
      if (mounted) setState(() => error = BackendStrings(s.language).error(e));
    } finally {
      setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(s.t('photoLimit')),
      if (busy) const LinearProgressIndicator(),
      ApiErrorBox(error),
      for (final id in ids)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (details[id]?['preview_url'] != null ||
                  details[id]?['url'] != null)
                Image.network(
                  details[id]!['preview_url'] ?? details[id]!['url'],
                  height: 140,
                  errorBuilder: (_, e, stack) =>
                      const Icon(Icons.broken_image_outlined),
                ),
              Text(s.t(details[id]?['status'] ?? 'ready')),
              TextButton(
                onPressed: !widget.enabled || busy ? null : () => remove(id),
                child: Text(s.t('remove')),
              ),
            ],
          ),
        ),
      for (final photo in photos.where(
        (p) => p.error != null || p.result?['status'] == 'rejected',
      ))
        Column(
          children: [
            Text(photo.file.name),
            ApiErrorBox(photo.error),
            if (photo.result?['status'] == 'rejected') Text(s.t('rejected')),
            TextButton(
              onPressed: !widget.enabled || busy
                  ? null
                  : () async {
                      setBusy(true);
                      await upload(photo);
                      setBusy(false);
                    },
              child: Text(s.t('uploadRetry')),
            ),
            TextButton(
              onPressed: !widget.enabled || busy
                  ? null
                  : () => setState(() => photos.remove(photo)),
              child: Text(s.t('remove')),
            ),
          ],
        ),
      OutlinedButton.icon(
        onPressed:
            !widget.enabled ||
                busy ||
                ids.length + photos.where((p) => p.result == null).length >=
                    widget.limit
            ? null
            : choose,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: Text(s.t('addPhoto')),
      ),
    ],
  );
}
