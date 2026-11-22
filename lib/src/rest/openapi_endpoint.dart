/// Normalized endpoint metadata read from an OpenAPI document.
class OpenApiEndpoint {
  const OpenApiEndpoint({
    required this.path,
    required this.method,
    required this.operationId,
  });

  final String path;
  final String method;
  final String? operationId;
}
