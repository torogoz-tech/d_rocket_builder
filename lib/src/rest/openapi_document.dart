/// Immutable OpenAPI document value used by the REST codegen tooling.
class OpenApiDocument {
  const OpenApiDocument(this.value);

  final Map<String, Object?> value;

  Map<String, Object?> toJson() => value;

  factory OpenApiDocument.fromJson(Map<String, Object?> json) {
    return OpenApiDocument(Map<String, Object?>.unmodifiable(json));
  }
}
