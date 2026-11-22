import 'openapi_document.dart';
import 'parser.dart';

/// Exports parsed `@RestClient` metadata as an OpenAPI 3.1 document.
class OpenApiExporter {
  const OpenApiExporter();

  OpenApiDocument export(
    ParsedClient client, {
    Map<String, Map<String, Object?>> schemas =
        const <String, Map<String, Object?>>{},
  }) {
    final Map<String, Object?> paths = <String, Object?>{};
    final Map<String, Object?> registeredSchemas = <String, Object?>{
      ...schemas
    };
    for (final ParsedMethod method in client.methods) {
      _registerSchema(registeredSchemas, method.returnType.dartType);
      final Map<String, Object?> operation = <String, Object?>{
        'operationId': method.name,
        'responses': <String, Object?>{
          '200': <String, Object?>{
            'description': 'Successful response',
            'content': <String, Object?>{
              'application/json': <String, Object?>{
                'schema': _schemaFor(method.returnType),
              },
            },
          },
        },
      };
      final List<Object?> parameters = <Object?>[];
      for (final ParsedParameter parameter in method.parameters) {
        if (!_isParameter(parameter.kind)) continue;
        parameters.add(<String, Object?>{
          'name': parameter.annotationName ?? parameter.name,
          'in': _parameterLocation(parameter.kind),
          'required': parameter.isRequired && !parameter.isNullable,
          'schema': _schemaForType(parameter.dartType),
        });
      }
      if (parameters.isNotEmpty) operation['parameters'] = parameters;
      final ParsedParameter? body = method.parameters
          .where(
              (ParsedParameter parameter) => parameter.kind == ParamKind.body)
          .cast<ParsedParameter?>()
          .firstWhere((ParsedParameter? parameter) => parameter != null,
              orElse: () => null);
      if (body != null) {
        _registerSchema(registeredSchemas, body.dartType);
        operation['requestBody'] = <String, Object?>{
          'required': body.isRequired && !body.isNullable,
          'content': <String, Object?>{
            'application/json': <String, Object?>{
              'schema': _schemaForType(body.dartType),
            },
          },
        };
      }
      final List<ParsedParameter> parts = method.parameters
          .where(
              (ParsedParameter parameter) => parameter.kind == ParamKind.part)
          .toList();
      final List<ParsedParameter> fields = method.parameters
          .where(
              (ParsedParameter parameter) => parameter.kind == ParamKind.field)
          .toList();
      if (parts.isNotEmpty || fields.isNotEmpty) {
        final bool multipart = parts.isNotEmpty;
        final List<ParsedParameter> formParameters = multipart ? parts : fields;
        operation['requestBody'] = <String, Object?>{
          'required': formParameters.any(
            (ParsedParameter parameter) =>
                parameter.isRequired && !parameter.isNullable,
          ),
          'content': <String, Object?>{
            multipart
                ? 'multipart/form-data'
                : 'application/x-www-form-urlencoded': <String, Object?>{
              'schema': <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  for (final ParsedParameter parameter in formParameters)
                    (parameter.annotationName ?? parameter.name):
                        multipart && parameter.dartType == 'List<int>'
                            ? <String, Object?>{
                                'type': 'string',
                                'format': 'binary',
                              }
                            : _schemaForType(parameter.dartType),
                },
              },
            },
          },
        };
      }
      final String path = _normalizePath(client.classPath + method.path);
      final Map<String, Object?> pathItem =
          (paths[path] as Map<String, Object?>?) ?? <String, Object?>{};
      pathItem[method.verb.toLowerCase()] = operation;
      paths[path] = pathItem;
    }
    return OpenApiDocument(<String, Object?>{
      'openapi': '3.1.0',
      'info': <String, Object?>{
        'title': client.className,
        'version': '1.0.0',
      },
      'servers': <Object?>[
        <String, Object?>{'url': client.baseUrl},
      ],
      'paths': paths,
      'components': <String, Object?>{'schemas': registeredSchemas},
    });
  }
}

void _registerSchema(Map<String, Object?> schemas, String type) {
  final String normalized = type.replaceAll('?', '');
  if (normalized.isEmpty ||
      normalized == 'dynamic' ||
      normalized == 'Object' ||
      normalized == 'String' ||
      normalized == 'int' ||
      normalized == 'double' ||
      normalized == 'num' ||
      normalized == 'bool' ||
      normalized == 'void' ||
      normalized.startsWith('List<')) {
    return;
  }
  schemas.putIfAbsent(normalized, () => <String, Object?>{'type': 'object'});
}

bool _isParameter(ParamKind kind) =>
    kind == ParamKind.path ||
    kind == ParamKind.query ||
    kind == ParamKind.header;

String _parameterLocation(ParamKind kind) {
  switch (kind) {
    case ParamKind.path:
      return 'path';
    case ParamKind.query:
      return 'query';
    case ParamKind.header:
      return 'header';
    default:
      throw ArgumentError.value(kind, 'kind', 'Not an OpenAPI parameter.');
  }
}

Map<String, Object?> _schemaFor(ParsedReturnType type) {
  if (type.isVoid) return <String, Object?>{'type': 'null'};
  if (type.isList) {
    return <String, Object?>{
      'type': 'array',
      'items': _schemaForType(type.innerType ?? 'dynamic'),
    };
  }
  return _schemaForType(type.dartType);
}

Map<String, Object?> _schemaForType(String type) {
  final String normalized = type.replaceAll('?', '');
  if (normalized == 'String') return <String, Object?>{'type': 'string'};
  if (normalized == 'int') return <String, Object?>{'type': 'integer'};
  if (normalized == 'double' || normalized == 'num') {
    return <String, Object?>{'type': 'number'};
  }
  if (normalized == 'bool') return <String, Object?>{'type': 'boolean'};
  if (normalized == 'dynamic' || normalized == 'Object') {
    return <String, Object?>{};
  }
  if (normalized.startsWith('List<') && normalized.endsWith('>')) {
    return <String, Object?>{
      'type': 'array',
      'items': _schemaForType(normalized.substring(5, normalized.length - 1)),
    };
  }
  return <String, Object?>{
    r'$ref': '#/components/schemas/$normalized',
  };
}

String _normalizePath(String path) {
  if (path.isEmpty) return '/';
  return path.startsWith('/') ? path : '/$path';
}
