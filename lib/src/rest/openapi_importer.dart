import 'openapi_document.dart';
import 'openapi_endpoint.dart';

/// Reads the endpoint surface of an OpenAPI 3.x document.
class OpenApiImporter {
  const OpenApiImporter();

  List<OpenApiEndpoint> endpoints(OpenApiDocument document) {
    final Object? rawPaths = document.value['paths'];
    if (rawPaths is! Map<String, Object?>) return const <OpenApiEndpoint>[];
    final List<OpenApiEndpoint> result = <OpenApiEndpoint>[];
    for (final MapEntry<String, Object?> path in rawPaths.entries) {
      final Object? rawItem = path.value;
      if (rawItem is! Map<String, Object?>) continue;
      for (final MapEntry<String, Object?> operation in rawItem.entries) {
        if (!_methods.contains(operation.key.toLowerCase())) continue;
        final String? operationId = operation.value is Map<String, Object?>
            ? (operation.value! as Map<String, Object?>)['operationId']
                as String?
            : null;
        result.add(
          OpenApiEndpoint(
            path: path.key,
            method: operation.key.toUpperCase(),
            operationId: operationId,
          ),
        );
      }
    }
    return List<OpenApiEndpoint>.unmodifiable(result);
  }
}

const Set<String> _methods = <String>{
  'get',
  'post',
  'put',
  'patch',
  'delete',
  'head',
  'options',
  'trace',
};
