import 'backend.dart';
import 'api_contract.g.dart';

/// Complete, generated OpenAPI inventory; uses the app's authenticated transport.
class ApiOperation {
  final Json definition;
  const ApiOperation(this.definition);
  String get id => definition['id'];
  String get method => definition['method'];
  String get path => definition['path'];
  bool get authenticated => definition['authenticated'];
  bool get multipart => definition['multipart'];
  List<int> get statuses => (definition['statuses'] as List).cast<int>();
  Json? get bodySchema => definition['body'] as Json?;
  Json? get responseSchema => definition['response'] as Json?;
  List<Json> get parameters => (definition['parameters'] as List).cast<Json>();
  bool get staff =>
      path.startsWith('/v1/staff/') ||
      path.startsWith('/v1/admin/') ||
      path.contains('/auth/mfa/');
}

class ApiContract {
  static final operations = (generatedContract['operations'] as List)
      .map((j) => ApiOperation(j as Json))
      .toList(growable: false);
  static Json get schemas => generatedContract['schemas'] as Json;
  static String get version => generatedContract['version'];
  static ApiOperation operation(String method, String path) =>
      operations.singleWhere((o) => o.method == method && o.path == path);
  static Json resolve(Json schema) => schema.containsKey(r'$ref')
      ? resolve(schemas[(schema[r'$ref'] as String).split('/').last] as Json)
      : schema;
  static Json nonNull(Json schema) {
    final resolved = resolve(schema);
    final variants = resolved['anyOf'] as List?;
    if (variants != null) {
      return nonNull(variants.firstWhere((j) => j['type'] != 'null') as Json);
    }
    return resolved;
  }

  static List<String> validate(Json schema, dynamic value, [String path = '']) {
    final s = resolve(schema);
    if (s['oneOf'] is List || s['anyOf'] is List) {
      final variants = (s['oneOf'] ?? s['anyOf']) as List;
      final discriminator = s['discriminator'] as Json?;
      if (discriminator != null && value is Map) {
        final mapping = discriminator['mapping'] as Json;
        final ref = mapping[value[discriminator['propertyName']]];
        if (ref == null) return ['$path.${discriminator['propertyName']}'];
        return validate({r'$ref': ref}, value, path);
      }
      if (variants.any((v) => validate(v as Json, value, path).isEmpty)) {
        return [];
      }
      return [path];
    }
    if (s.containsKey('const') && value != s['const']) return [path];
    if (s['enum'] is List && !(s['enum'] as List).contains(value)) {
      return [path];
    }
    switch (s['type']) {
      case 'null':
        return value == null ? [] : [path];
      case 'object':
        if (value is! Map) return [path];
        final errors = <String>[];
        final properties = s['properties'] as Json? ?? {};
        for (final field in s['required'] as List? ?? []) {
          if (!value.containsKey(field)) errors.add('$path.$field');
        }
        for (final entry in value.entries) {
          final childPath = path.isEmpty
              ? '${entry.key}'
              : '$path.${entry.key}';
          if (properties.containsKey(entry.key)) {
            errors.addAll(
              validate(properties[entry.key] as Json, entry.value, childPath),
            );
          } else if (s['additionalProperties'] is Map) {
            errors.addAll(
              validate(
                s['additionalProperties'] as Json,
                entry.value,
                childPath,
              ),
            );
          } else if (s['additionalProperties'] != true) {
            errors.add(childPath);
          }
        }
        return errors;
      case 'array':
        if (value is! List) return [path];
        if (value.length < (s['minItems'] ?? 0) ||
            value.length > (s['maxItems'] ?? double.infinity)) {
          return [path];
        }
        return [
          for (int i = 0; i < value.length; i++)
            ...validate(s['items'] as Json, value[i], '$path.$i'),
        ];
      case 'string':
        if (value is! String) return [path];
        if (value.runes.length < (s['minLength'] ?? 0) ||
            value.runes.length > (s['maxLength'] ?? double.infinity)) {
          return [path];
        }
        if (s['pattern'] != null && !RegExp(s['pattern']).hasMatch(value)) {
          return [path];
        }
        if (s['format'] == 'uuid' &&
            !RegExp(
              r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
            ).hasMatch(value)) {
          return [path];
        }
        if (s['format'] == 'date-time' && DateTime.tryParse(value) == null) {
          return [path];
        }
      case 'integer':
      case 'number':
        if (value is! num ||
            !value.isFinite ||
            (s['type'] == 'integer' && value is! int)) {
          return [path];
        }
        if (value < (s['minimum'] ?? -double.infinity) ||
            value > (s['maximum'] ?? double.infinity)) {
          return [path];
        }
      case 'boolean':
        if (value is! bool) return [path];
    }
    return [];
  }
}

class ContractApi {
  final QogamApi api;
  const ContractApi(this.api);
  Future<dynamic> call(
    ApiOperation operation, {
    Json path = const {},
    Json query = const {},
    Json? body,
    Map<String, String> headers = const {},
    ApiUpload? upload,
  }) async {
    final errors = <String>[];
    var url = operation.path;
    for (final parameter in operation.parameters) {
      final name = parameter['name'] as String;
      final source = switch (parameter['in']) {
        'path' => path,
        'query' => query,
        _ => headers,
      };
      if (!source.containsKey(name)) {
        if (parameter['required'] == true) errors.add(name);
      } else {
        errors.addAll(
          ApiContract.validate(parameter['schema'] as Json, source[name], name),
        );
      }
      if (parameter['in'] == 'path' && source.containsKey(name)) {
        if (['', '.', '..'].contains('${source[name]}')) errors.add(name);
        url = url.replaceAll('{$name}', Uri.encodeComponent('${source[name]}'));
      }
    }
    final allowedQuery = operation.parameters
        .where((p) => p['in'] == 'query')
        .map((p) => p['name']);
    errors.addAll(query.keys.where((key) => !allowedQuery.contains(key)));
    if (operation.multipart) {
      if (upload == null) {
        errors.add('file');
      } else {
        errors.addAll(
          ApiContract.validate(operation.bodySchema!, {
            'file': upload.filename,
            'client_media_id': upload.clientMediaId,
            'kind': upload.kind,
          }, 'body'),
        );
        if (upload.bytes.isEmpty || upload.bytes.length > 10 * 1024 * 1024) {
          errors.add('file');
        }
      }
    } else if (operation.bodySchema != null) {
      errors.addAll(
        ApiContract.validate(operation.bodySchema!, body ?? {}, 'body'),
      );
    } else if (body != null && body.isNotEmpty) {
      errors.add('body');
    }
    if (body?['description'] is String &&
        (operation.path == '/v1/reports' ||
            operation.path.endsWith('/requests') ||
            operation.method == 'PATCH' &&
                operation.path == '/v1/me/reports/{report_id}')) {
      final length = (body!['description'] as String).trim().runes.length;
      if (length < 10 || length > 2000) errors.add('description');
    }
    if (url.contains('{') || errors.isNotEmpty) {
      throw ApiException(
        422,
        'http',
        code: 'client.validation',
        fields: errors,
      );
    }
    return api.request(
      operation.method,
      url,
      body: operation.multipart ? null : body,
      query: {
        for (final e in query.entries)
          e.key: e.value == null ? null : '${e.value}',
      },
      authenticated:
          operation.authenticated ||
          (api.user != null && operation.method == 'GET'),
      headers: headers,
      upload: upload,
    );
  }
}
