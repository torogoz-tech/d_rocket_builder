import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:d_rocket/d_rocket.dart';
import 'package:source_gen/source_gen.dart';

import '../shared/utils.dart';

/// Annotation name for `SerializableUnion`.
const _serializableUnionName = 'SerializableUnion';

/// Field name expected on classes that use `UnknownKeyPolicy.capture`.
const _extraFieldName = 'extra';

/// Generates the `*.d_rocket_serializer.g.dart` and union registration
/// code for a class annotated with `@Serializable`.
///
/// Each builder instance is reused for every annotated element in a
/// build, so instance state (the discriminator tracker) is safe to
/// keep around for the duration of one build.
///
/// Originally lived in `d_builder/lib/src/serializer/generator.dart`
/// ( of the d_rocket roadmap). Moved here as part of
/// ("absorb d_serializer") — the runtime (`Serializer`,
/// `@Serializable`, etc.) is now in `package:d_rocket` and the
/// codegen lives in `package:d_rocket_builder`.
class SerializableGenerator extends GeneratorForAnnotation<Serializable> {
  /// Tracks discriminator values seen in this build session so we can
  /// fail loudly when two subtypes of the same union declare the
  /// same `discriminator` for the same `typeField`.
  final Map<String, _DiscriminatorSite> _seenDiscriminators =
      <String, _DiscriminatorSite>{};

  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@Serializable can only be applied to classes',
        element: element,
      );
    }

    final _ClassMetadata meta = _readClassMetadata(element, annotation);
    _validateDiscriminatorUniqueness(element, meta);

    final List<FieldElement> fields = element.fields
        .where((FieldElement f) => !f.isStatic && !f.isPrivate)
        .toList();

    final FieldElement? extraField = meta.unknownKeyPolicy ==
            UnknownKeyPolicy.capture
        ? _findExtraField(element, fields)
        : null;

    final _GenerationPlan plan = _buildPlan(meta, fields, extraField);

    return _renderSource(meta, plan, element);
  }

  // ---------------------------------------------------------------------------
  // Metadata extraction
  // ---------------------------------------------------------------------------

  _ClassMetadata _readClassMetadata(
    ClassElement element,
    ConstantReader annotation,
  ) {
    final String? rename = _readOptionalString(annotation, 'rename');
    final String? discriminator =
        _readOptionalString(annotation, 'discriminator');
    final String? typeField = _readOptionalString(annotation, 'typeField');

    final bool strictBool = _readOptionalBool(annotation, 'strict') ?? false;
    final UnknownKeyPolicy unknownKeyPolicy =
        _readUnknownKeyPolicy(annotation, strictBool);
    final JsonNaming naming = _readNaming(annotation);

    // Generics: capture the type parameters declared on the class.
    // We store the display string of each parameter (e.g. `T`, `T?`,
    // `T extends SomeBase`). The codegen uses these to:
    //   1. Add `<T>` to the generated `FromJson` / `ToJson` signatures.
    //   2. Add decoder/encoder function parameters for fields whose
    //      type mentions a type parameter.
    //   3. Recurse into collection element types (e.g. `List<T>`).
    final List<String> typeParameters = <String>[];
    for (final TypeParameterElement tp in element.typeParameters) {
      // `name` is `String?` in the analyzer 8.x API. In practice it is
      // never null for a type parameter declared on a class, so we
      // safely unwrap with a fallback to a synthetic name to keep the
      // codegen robust.
      typeParameters.add(tp.name ?? '_T${typeParameters.length}');
    }

    return _ClassMetadata(
      className: element.displayName,
      rename: rename,
      discriminator: discriminator,
      typeField: typeField,
      unknownKeyPolicy: unknownKeyPolicy,
      naming: naming,
      resolvedDiscriminator:
          discriminator ?? rename ?? element.displayName,
      typeParameters: typeParameters,
    );
  }

  // ---------------------------------------------------------------------------
  // Plan construction (D3 refactor: the main entry was over 130 lines)
  // ---------------------------------------------------------------------------

  _GenerationPlan _buildPlan(
    _ClassMetadata meta,
    List<FieldElement> fields,
    FieldElement? extraField,
  ) {
    final Set<String> typeParameterNames = <String>{
      ...meta.typeParameters,
    };
    final List<String> toJsonEntries = <String>[];
    final List<String> fromJsonParams = <String>[];
    final List<String> fromJsonGuards = <String>[];
    final List<String> knownKeys = <String>[];

    // Discriminator handling.
    if (meta.typeField != null && meta.typeField!.isNotEmpty) {
      knownKeys.add(meta.typeField!);
      fromJsonGuards.add(
        "if (json['${meta.typeField}'] != '${meta.resolvedDiscriminator}') "
        "{ throw ArgumentError('Invalid discriminator for ${meta.className} "
        "at ${meta.typeField}: expected ${meta.resolvedDiscriminator}'); }",
      );
      toJsonEntries.add("'${meta.typeField}': '${meta.resolvedDiscriminator}',");
    }

    // Per-field processing.
    for (final FieldElement field in fields) {
      if (identical(field, extraField)) {
        // The `extra` field is not read from the JSON via the normal
        // path: its value is computed by the capture guard below.
        // We still want it to appear in the constructor call, so the
        // processing happens in `_handleUnknownKeys`.
        knownKeys.add(_extraFieldName);
        continue;
      }
      _processField(
        meta,
        field,
        knownKeys,
        toJsonEntries,
        fromJsonParams,
        fromJsonGuards,
        typeParameterNames,
      );
    }

    // The extra field, if any, is read from a local variable
    // populated by the capture guard.
    if (extraField != null) {
      fromJsonParams.add('$_extraFieldName: _$_extraFieldName,');
    }

    // Unknown-key policy: strict (throw) or capture (populate extra).
    switch (meta.unknownKeyPolicy) {
      case UnknownKeyPolicy.strict:
        _appendStrictGuard(meta.className, knownKeys, fromJsonGuards);
        break;
      case UnknownKeyPolicy.capture:
        _appendCaptureGuard(
          meta.className,
          knownKeys,
          fromJsonGuards,
        );
        break;
      case UnknownKeyPolicy.ignore:
        // No additional code.
        break;
    }

    return _GenerationPlan(
      toJsonEntries: toJsonEntries,
      fromJsonParams: fromJsonParams,
      fromJsonGuards: fromJsonGuards,
    );
  }

  void _processField(
    _ClassMetadata meta,
    FieldElement field,
    List<String> knownKeys,
    List<String> toJsonEntries,
    List<String> fromJsonParams,
    List<String> fromJsonGuards,
    Set<String> typeParameterNames,
  ) {
    final String fieldName = field.displayName;
    final DartType type = field.type;
    final String typeStr = type.toString();
    final String defaultJsonKey = jsonKeyFor(fieldName, _namingAsString(meta.naming));
    final List<_FormatSpec> formats = _getFormatAnnotations(field);

    final ConstantReader? jsonKeyAnnotation = _getJsonKeyAnnotation(field);
    if (jsonKeyAnnotation == null) {
      knownKeys.add(defaultJsonKey);
      _addFieldSerialization(
        meta.className,
        fieldName,
        defaultJsonKey,
        typeStr,
        type,
        toJsonEntries,
        fromJsonParams,
        false,
        null,
        null,
        null,
        formats,
        typeParameterNames,
      );
      return;
    }

    final ConstantReader ignoreValue = jsonKeyAnnotation.read('ignore');
    if (ignoreValue.isBool && ignoreValue.boolValue == true) {
      return;
    }

    String actualJsonKey = defaultJsonKey;
    final ConstantReader nameValue = jsonKeyAnnotation.read('name');
    if (nameValue.isString && nameValue.stringValue.isNotEmpty) {
      actualJsonKey = nameValue.stringValue;
    }

    final bool useEnumIndex =
        _readOptionalBool(jsonKeyAnnotation, 'useEnumIndex') ?? false;
    final String? defaultValueCode = _readDefaultValueCode(jsonKeyAnnotation);
    final String? converter =
        _readOptionalString(jsonKeyAnnotation, 'converter');
    final bool requiredKey =
        _readOptionalBool(jsonKeyAnnotation, 'requiredKey') ?? false;
    final String? unknownEnumValue =
        _readOptionalString(jsonKeyAnnotation, 'unknownEnumValue');

    knownKeys.add(actualJsonKey);
    if (requiredKey) {
      fromJsonGuards.add(
        "if (!json.containsKey('$actualJsonKey') || "
        "json['$actualJsonKey'] == null) "
        "{ throw ArgumentError('Missing required field "
        "${meta.className}.$fieldName ($actualJsonKey)'); }",
      );
    }

    _addFieldSerialization(
      meta.className,
      fieldName,
      actualJsonKey,
      typeStr,
      type,
      toJsonEntries,
      fromJsonParams,
      useEnumIndex,
      defaultValueCode,
      converter,
      unknownEnumValue,
      formats,
      typeParameterNames,
    );
  }

  // ---------------------------------------------------------------------------
  // Unknown-key policy helpers
  // ---------------------------------------------------------------------------

  void _appendStrictGuard(
    String className,
    List<String> knownKeys,
    List<String> fromJsonGuards,
  ) {
    final String keys = knownKeys.map((String item) => "'$item'").join(', ');
    fromJsonGuards.add(
      "const Set<String> _allowedKeys = <String>{$keys}; "
      "for (final String key in json.keys) "
      "{ if (!_allowedKeys.contains(key)) "
      "{ throw ArgumentError('Unknown field for $className: \$key'); } }",
    );
  }

  void _appendCaptureGuard(
    String className,
    List<String> knownKeys,
    List<String> fromJsonGuards,
  ) {
    final String keys = knownKeys.map((String item) => "'$item'").join(', ');
    fromJsonGuards.add(
      "final Map<String, dynamic> _$_extraFieldName = <String, dynamic>{}; "
      "const Set<String> _allowedKeys = <String>{$keys}; "
      "for (final MapEntry<String, dynamic> e in json.entries) "
      "{ if (!_allowedKeys.contains(e.key)) { _$_extraFieldName[e.key] = e.value; } }",
    );
  }

  /// Finds the user-declared `Map<String, dynamic> extra;` field used by
  /// `UnknownKeyPolicy.capture`. Throws a build error if it is missing
  /// or has the wrong type.
  FieldElement? _findExtraField(
    ClassElement element,
    List<FieldElement> fields,
  ) {
    FieldElement? found;
    for (final FieldElement f in fields) {
      if (f.displayName != _extraFieldName) continue;
      found = f;
      break;
    }
    if (found == null) {
      throw InvalidGenerationSourceError(
        'UnknownKeyPolicy.capture on ${element.displayName} requires a '
        '`Map<String, dynamic> extra;` (or `Map<String, dynamic>? extra;`) '
        'field on the class.',
        element: element,
      );
    }
    if (!_isMapStringDynamic(found.type)) {
      throw InvalidGenerationSourceError(
        'The `extra` field on ${element.displayName} must be of type '
        '`Map<String, dynamic>` (or `Map<String, dynamic>?`). '
        'Got `${found.type}` instead.',
        element: found,
      );
    }
    return found;
  }

  bool _isMapStringDynamic(DartType type) {
    if (type is! InterfaceType) return false;
    if (!type.isDartCoreMap) return false;
    if (type.typeArguments.length != 2) return false;
    final DartType k = type.typeArguments[0];
    final DartType v = type.typeArguments[1];
    return k.isDartCoreString && v.element?.name == 'dynamic';
  }

  // ---------------------------------------------------------------------------
  // D8: discriminator uniqueness validation
  // ---------------------------------------------------------------------------

  void _validateDiscriminatorUniqueness(
    ClassElement element,
    _ClassMetadata meta,
  ) {
    if (meta.typeField == null || meta.typeField!.isEmpty) return;
    if (meta.discriminator == null) return; // Falls back to className.

    final String key =
        '${meta.resolvedDiscriminator}|${meta.typeField}|${meta.discriminator}';
    final _DiscriminatorSite? existing = _seenDiscriminators[key];
    if (existing != null) {
      throw InvalidGenerationSourceError(
        'Duplicate discriminator value for union: '
        '`typeField="${meta.typeField}", discriminator="${meta.discriminator}"` '
        'is already used by ${existing.className}.',
        element: element,
      );
    }
    _seenDiscriminators[key] = _DiscriminatorSite(
      className: meta.className,
      typeField: meta.typeField!,
      discriminator: meta.discriminator!,
    );
  }

  // ---------------------------------------------------------------------------
  // Source rendering
  // ---------------------------------------------------------------------------

  String _renderSource(
    _ClassMetadata meta,
    _GenerationPlan plan,
    ClassElement element,
  ) {
    final String toJsonBody =
        'return <String, dynamic>{\n${plan.toJsonEntries.join('\n')}\n};';
    final String fromJsonBody =
        'return ${meta.className}(\n${plan.fromJsonParams.join('\n')}\n);';
    final String guards = plan.fromJsonGuards.isEmpty
        ? ''
        : '${plan.fromJsonGuards.join('\n  ')}\n  ';

    final String unionRegistration = _renderRegisterFunction(
      meta,
      element: element,
    );

    // Generic-class codegen: when the class declares type parameters
    // (e.g. `class ApiResponse<T>`) we need to:
    //   1. Add `<T>` to the fromJson/toJson signatures.
    //   2. Accept decoder/encoder function parameters for each type
    //      parameter (e.g. `T Function(Map<String, dynamic>) decodeT`).
    //   3. Inject these calls in field expressions. The recursion
    //      into collection element types is already handled by
    //      `_toJsonExpr` / `_fromJsonExpr`, but those need to know
    //      that a given type argument should be handled via the
    //      decoder/encoder rather than via a sibling `FromJson`
    //      function. We achieve this by passing a `typeParameterNames`
    //      set to those helpers.
    final String typeArgs =
        meta.isGeneric ? '<${meta.typeParameters.join(', ')}>' : '';
    final String decodeParams = meta.isGeneric
        ? ',\n  ${meta.typeParameters.map((String t) => '$t Function(Map<String, dynamic>) decode$t').join(',\n  ')}'
        : '';
    final String encodeParams = meta.isGeneric
        ? ',\n  ${meta.typeParameters.map((String t) => 'Map<String, dynamic> Function($t) encode$t').join(',\n  ')}'
        : '';

    // Generic classes cannot have a `toJson()` extension because
    // the type parameter is erased at runtime: the generated method
    // would not know which encoder to use for fields of type `T`.
    // Users have to call the static `${meta.className}ToJson` function
    // and pass encoder functions for each type parameter explicitly.
    final String toJsonExtension = meta.isGeneric
        ? '// Generic classes do not get a `toJson()` extension; use the\n'
            '// static `${meta.className}ToJson<T>(value, encodeT: ...)` function.'
        : '''

extension ${meta.className}Serializer on ${meta.className} {
  Map<String, dynamic> toJson() {
    $toJsonBody
  }
}''';

    return '''
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: non_constant_identifier_names

${meta.className}$typeArgs ${meta.className}FromJson$typeArgs(Map<String, dynamic> json$decodeParams) {
  $guards$fromJsonBody
}

Map<String, dynamic> ${meta.className}ToJson$typeArgs(${meta.className}$typeArgs value$encodeParams) {
  return value.toJson();
}
$unionRegistration
$toJsonExtension
''';
  }

  String _renderRegisterFunction(
    _ClassMetadata meta, {
    required ClassElement element,
  }) {
    // Generic classes can't be auto-registered: type parameters are
    // erased at runtime, so `Serializer.register<ApiResponse<T>>` is
    // meaningless. Users have to register each concrete instantiation
    // (e.g. `ApiResponse<User>`, `ApiResponse<Post>`) themselves.
    if (meta.isGeneric) {
      return '''
/// Registers encoders/decoders for [${meta.className}]. You must
/// provide a `decode<T>` and `encode<T>` for every type parameter
/// that this class uses, and call this for every concrete
/// instantiation:
///
/// ```dart
/// registerApiResponseSerializer<User>(
///   decode: UserFromJson,
///   encode: UserToJson,
/// );
/// ```
void register${meta.className}Serializer<T>({
  required T Function(Map<String, dynamic>) decode,
  required Map<String, dynamic> Function(T) encode,
}) {
  Serializer.register<${meta.className}<T>>(
    fromJson: (Map<String, dynamic> json) =>
        ${meta.className}FromJson<T>(json, decode),
    toJson: (${meta.className}<T> value) =>
        ${meta.className}ToJson<T>(value, encode),
  );
}''';
    }

    final ConstantReader? unionAnnotation =
        _findSerializableUnionAnnotation(element);
    if (unionAnnotation == null) {
      return '''
void register${meta.className}Serializer() {
  Serializer.register<${meta.className}>(
    fromJson: ${meta.className}FromJson,
    toJson: ${meta.className}ToJson,
  );
}''';
    }

    final String typeField =
        _readOptionalString(unionAnnotation, 'typeField') ?? 'type';

    return '''
void register${meta.className}Serializer() {
  Serializer.register<${meta.className}>(
    fromJson: ${meta.className}FromJson,
    toJson: ${meta.className}ToJson,
  );
  Serializer.registerUnion<${meta.className}>(
    typeField: '$typeField',
    discriminator: '${meta.resolvedDiscriminator}',
    fromJson: ${meta.className}FromJson,
  );
}''';
  }

  // ---------------------------------------------------------------------------
  // Field expression generation
  // ---------------------------------------------------------------------------

  void _addFieldSerialization(
    String className,
    String fieldName,
    String jsonKey,
    String typeStr,
    DartType type,
    List<String> toJsonEntries,
    List<String> fromJsonParams,
    bool useEnumIndex,
    String? defaultValueCode,
    String? converter,
    String? unknownEnumValue,
    List<_FormatSpec> formats,
    Set<String> typeParameterNames,
  ) {
    _validateFormatCompatibility(className, fieldName, typeStr, formats);
    final bool hasDateFormat = _hasDateFormat(formats);

    // Generic field: the field's declared type is one of the class's
    // type parameters (e.g. `T` in `class ApiResponse<T> { T data; }`).
    // We delegate the (de)serialisation to the decoder/encoder function
    // parameters that the renderer injected into the generated function
    // signature.
    final String? typeParamName = _typeParameterName(type, typeParameterNames);

    // Forward-declared so both the generic-type branch below and the
    // type-dispatch branch further down can populate them.
    String toExpr;
    String fromExpr;

    if (converter != null && converter.isNotEmpty) {
      final bool nullable = type.nullabilitySuffix.name != 'none';
      if (nullable) {
        toExpr =
            "$fieldName == null ? null : ${converter}ToJson($fieldName as ${_nonNullableType(typeStr)})";
      } else {
        toExpr = "${converter}ToJson($fieldName)";
      }

      fromExpr = nullable
          ? "json['$jsonKey'] == null ? null : ${converter}FromJson(json['$jsonKey'])"
          : "${converter}FromJson(json['$jsonKey'])";
      if (defaultValueCode != null) {
        fromExpr = "json['$jsonKey'] == null ? $defaultValueCode : $fromExpr";
      }
      toExpr = _applyFormattersToJsonExpr(toExpr, typeStr, formats);
      fromExpr = _applyFormattersFromJsonExpr(fromExpr, typeStr, formats);
      fromJsonParams.add('$fieldName: $fromExpr,');
      toJsonEntries.add("'$jsonKey': $toExpr,");
      return;
    }

    // Bare type parameter: `<T>`. Uses the injected decoder/encoder
    // function. Nullable generics are supported by delegating the
    // null check to Dart's type system: when the type is `T?` the
    // generated code first checks for `null` and then calls the
    // decoder/encoder.
    if (typeParamName != null) {
      final bool nullable = typeStr.endsWith('?');
      toExpr = nullable
          ? "$fieldName == null ? null : encode\$typeParamName($fieldName)"
          : 'encode$typeParamName($fieldName)';
      fromExpr = nullable
          ? "json['$jsonKey'] == null ? null : decode\$typeParamName(json['\$jsonKey'] as Map<String, dynamic>)"
          : "decode$typeParamName(json['\$jsonKey'] as Map<String, dynamic>)";
      if (defaultValueCode != null) {
        fromExpr = "json['$jsonKey'] == null ? $defaultValueCode : $fromExpr";
      }
      toJsonEntries.add("'$jsonKey': $toExpr,");
      fromJsonParams.add('$fieldName: $fromExpr,');
      return;
    }

    if (type.isDartCoreList) {
      final DartType typeArg = (type as InterfaceType).typeArguments.first;
      final String toJsonInner = _toJsonExpr(
        'e',
        typeArg.toString(),
        typeArg,
        useEnumIndex: false,
        unknownEnumValue: null,
        typeParameterNames: typeParameterNames,
      );
      final String fromJsonInner = _fromJsonExpr(
        'e',
        typeArg.toString(),
        typeArg,
        useEnumIndex: false,
        unknownEnumValue: null,
        typeParameterNames: typeParameterNames,
      );
      toExpr = '($fieldName as List).map((e) => $toJsonInner).toList()';
      fromExpr =
          "(json['$jsonKey'] as List).map((e) => $fromJsonInner).toList()";
    } else if (type.isDartCoreSet) {
      final DartType typeArg = (type as InterfaceType).typeArguments.first;
      final String toJsonInner = _toJsonExpr(
        'e',
        typeArg.toString(),
        typeArg,
        useEnumIndex: false,
        unknownEnumValue: null,
        typeParameterNames: typeParameterNames,
      );
      final String fromJsonInner = _fromJsonExpr(
        'e',
        typeArg.toString(),
        typeArg,
        useEnumIndex: false,
        unknownEnumValue: null,
        typeParameterNames: typeParameterNames,
      );
      toExpr = '($fieldName as Set).map((e) => $toJsonInner).toList()';
      fromExpr =
          "((json['$jsonKey'] as List).map((e) => $fromJsonInner)).toSet()";
    } else if (type.isDartCoreMap) {
      final DartType valueType = (type as InterfaceType).typeArguments.last;
      final String toJsonInner = _toJsonExpr(
        'v',
        valueType.toString(),
        valueType,
        useEnumIndex: false,
        unknownEnumValue: null,
        typeParameterNames: typeParameterNames,
      );
      final String fromJsonInner = _fromJsonExpr(
        'v',
        valueType.toString(),
        valueType,
        useEnumIndex: false,
        unknownEnumValue: null,
        typeParameterNames: typeParameterNames,
      );
      toExpr =
          '($fieldName as Map).map((k, v) => MapEntry(k.toString(), $toJsonInner))';
      fromExpr =
          "(json['$jsonKey'] as Map).map((k, v) => MapEntry(k.toString(), $fromJsonInner))";
    } else if (type.element?.name == 'DateTime') {
      if (hasDateFormat) {
        toExpr = fieldName;
        fromExpr = "json['$jsonKey']";
      } else if (typeStr.endsWith('?')) {
        toExpr =
            "$fieldName == null ? null : ($fieldName as DateTime).toIso8601String()";
        fromExpr =
            "json['$jsonKey'] == null ? null : DateTime.parse(json['$jsonKey'] as String)";
      } else {
        toExpr = '$fieldName.toIso8601String()';
        fromExpr = "DateTime.parse(json['$jsonKey'] as String)";
      }
    } else if (type.element?.name == 'Uri') {
      if (typeStr.endsWith('?')) {
        toExpr = "$fieldName == null ? null : ($fieldName as Uri).toString()";
        fromExpr =
            "json['$jsonKey'] == null ? null : Uri.parse(json['$jsonKey'] as String)";
      } else {
        toExpr = '$fieldName.toString()';
        fromExpr = "Uri.parse(json['$jsonKey'] as String)";
      }
    } else if (type.element?.name == 'BigInt') {
      if (typeStr.endsWith('?')) {
        toExpr =
            "$fieldName == null ? null : ($fieldName as BigInt).toString()";
        fromExpr =
            "json['$jsonKey'] == null ? null : BigInt.parse(json['$jsonKey'] as String)";
      } else {
        toExpr = '$fieldName.toString()';
        fromExpr = "BigInt.parse(json['$jsonKey'] as String)";
      }
    } else if (type.element?.name == 'Duration') {
      if (typeStr.endsWith('?')) {
        toExpr =
            "$fieldName == null ? null : ($fieldName as Duration).inMicroseconds";
        fromExpr =
            "json['$jsonKey'] == null ? null : Duration(microseconds: (json['$jsonKey'] as num).toInt())";
      } else {
        toExpr = '$fieldName.inMicroseconds';
        fromExpr =
            "Duration(microseconds: (json['$jsonKey'] as num).toInt())";
      }
    } else if (type.element?.kind == ElementKind.ENUM) {
      toExpr = _enumToJsonExpr(fieldName, typeStr, useEnumIndex);
      fromExpr = _enumFromJsonExpr(
        "json['$jsonKey']",
        typeStr,
        useEnumIndex,
        unknownEnumValue,
        nullable: typeStr.endsWith('?'),
      );
    } else if (type.isDartCoreInt) {
      toExpr = fieldName;
      fromExpr = "(json['$jsonKey'] as num).toInt()";
    } else if (type.isDartCoreDouble) {
      toExpr = fieldName;
      fromExpr = "(json['$jsonKey'] as num).toDouble()";
    } else if (type.isDartCoreString || type.isDartCoreBool) {
      toExpr = fieldName;
      fromExpr = "json['$jsonKey'] as $typeStr";
    } else if (type.element?.name == 'dynamic') {
      toExpr = fieldName;
      fromExpr = "json['$jsonKey']";
    } else {
      toExpr = 'Serializer.encodeDynamic($fieldName)';
      fromExpr = "Serializer.fromDynamic<$typeStr>(json['$jsonKey'])";
    }

    if (defaultValueCode != null) {
      fromExpr = "json['$jsonKey'] == null ? $defaultValueCode : $fromExpr";
    }

    toExpr = _applyFormattersToJsonExpr(toExpr, typeStr, formats);
    fromExpr = _applyFormattersFromJsonExpr(fromExpr, typeStr, formats);

    toJsonEntries.add("'$jsonKey': $toExpr,");
    fromJsonParams.add('$fieldName: $fromExpr,');
  }

  bool _hasDateFormat(List<_FormatSpec> formats) {
    for (final _FormatSpec format in formats) {
      if (format.kind == 'date') {
        return true;
      }
    }
    return false;
  }

  String _enumToJsonExpr(String fieldName, String typeStr, bool useEnumIndex) {
    if (typeStr.endsWith('?')) {
      final String cleanType = _nonNullableType(typeStr);
      if (useEnumIndex) {
        return "$fieldName == null ? null : ($fieldName as $cleanType).index";
      }
      return "$fieldName == null ? null : ($fieldName as $cleanType).name";
    }
    return useEnumIndex ? '$fieldName.index' : '$fieldName.name';
  }

  String _enumFromJsonExpr(
    String valueExpr,
    String typeStr,
    bool useEnumIndex,
    String? unknownEnumValue, {
    required bool nullable,
  }) {
    final String enumType = _nonNullableType(typeStr);
    final String unknownExpr = unknownEnumValue == null
        ? (nullable
            ? 'null'
            : "throw ArgumentError('Unknown enum value for $enumType')")
        : "$enumType.values.byName('$unknownEnumValue')";

    if (useEnumIndex) {
      final String parsed =
          "(() { final int _i = ($valueExpr as num).toInt(); if (_i < 0 || _i >= $enumType.values.length) return $unknownExpr; return $enumType.values[_i]; })()";
      return nullable ? "$valueExpr == null ? null : $parsed" : parsed;
    }

    final String parsed =
        "$enumType.values.firstWhere((e) => e.name == ($valueExpr as String), orElse: () => $unknownExpr)";
    return nullable ? "$valueExpr == null ? null : $parsed" : parsed;
  }

  // ---------------------------------------------------------------------------
  // Annotation readers
  // ---------------------------------------------------------------------------

  ConstantReader? _getJsonKeyAnnotation(FieldElement field) {
    for (final ElementAnnotation annotation in field.metadata.annotations) {
      if (annotation.element?.displayName == 'JsonKey') {
        return ConstantReader(annotation.computeConstantValue());
      }
    }
    return null;
  }

  List<_FormatSpec> _getFormatAnnotations(FieldElement field) {
    final List<_FormatSpec> formats = <_FormatSpec>[];
    for (final ElementAnnotation annotation in field.metadata.annotations) {
      if (annotation.element?.enclosingElement?.displayName != 'Format') {
        continue;
      }
      final ConstantReader reader =
          ConstantReader(annotation.computeConstantValue());
      final String? kind = _readOptionalString(reader, 'kind');
      if (kind == null || kind.isEmpty) {
        continue;
      }
      String? pattern = _readOptionalString(reader, 'pattern');
      if (kind == 'customWith') {
        pattern = _readOptionalTypeName(reader, 'formatterType');
      }
      if (kind == 'date' && (pattern == null || pattern.trim().isEmpty)) {
        throw InvalidGenerationSourceError(
          'Invalid @Format.date on ${field.enclosingElement.displayName}.${field.displayName}: pattern is required and cannot be empty.',
          element: field,
        );
      }
      if ((kind == 'custom' || kind == 'customWith') &&
          (pattern == null || pattern.trim().isEmpty)) {
        throw InvalidGenerationSourceError(
          'Invalid @Format.$kind on ${field.enclosingElement.displayName}.${field.displayName}: formatter name cannot be empty or whitespace.',
          element: field,
        );
      }
      formats.add(_FormatSpec(kind: kind, pattern: pattern));
    }
    return formats;
  }

  void _validateFormatCompatibility(
    String className,
    String fieldName,
    String typeStr,
    List<_FormatSpec> formats,
  ) {
    final String baseType = _nonNullableType(typeStr);
    for (final _FormatSpec format in formats) {
      switch (format.kind) {
        case 'trim':
        case 'uppercase':
        case 'lowercase':
          if (baseType != 'String') {
            throw InvalidGenerationSourceError(
              'Invalid @Format.${format.kind} on $className.$fieldName: only String/String? fields are supported.',
            );
          }
          break;
        case 'date':
          if (baseType != 'DateTime') {
            throw InvalidGenerationSourceError(
              'Invalid @Format.date on $className.$fieldName: only DateTime/DateTime? fields are supported.',
            );
          }
          if (format.pattern == null || format.pattern!.isEmpty) {
            throw InvalidGenerationSourceError(
              'Invalid @Format.date on $className.$fieldName: pattern is required.',
            );
          }
          break;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Formatter application (expression transformers)
  // ---------------------------------------------------------------------------

  String _applyFormattersToJsonExpr(
    String expr,
    String typeStr,
    List<_FormatSpec> formats,
  ) {
    if (formats.isEmpty) return expr;
    final bool nullable = typeStr.endsWith('?');
    final String baseType = _nonNullableType(typeStr);
    String formatted = expr;
    for (final _FormatSpec format in formats) {
      switch (format.kind) {
        case 'trim':
          if (baseType != 'String') continue;
          formatted = nullable
              ? '($formatted == null ? null : $formatted.trim())'
              : '($formatted).trim()';
          break;
        case 'uppercase':
          if (baseType != 'String') continue;
          formatted = nullable
              ? '($formatted == null ? null : $formatted.toUpperCase())'
              : '($formatted).toUpperCase()';
          break;
        case 'lowercase':
          if (baseType != 'String') continue;
          formatted = nullable
              ? '($formatted == null ? null : $formatted.toLowerCase())'
              : '($formatted).toLowerCase()';
          break;
        case 'date':
          if (baseType != 'DateTime' || format.pattern == null) continue;
          final String patternLiteral = _literalToCode(format.pattern);
          formatted = nullable
              ? '($formatted == null ? null : Serializer.formatDate($formatted, $patternLiteral))'
              : 'Serializer.formatDate(($formatted), $patternLiteral)';
          break;
        case 'custom':
        case 'customWith':
          if (format.pattern == null || format.pattern!.isEmpty) continue;
          final String formatterName = format.pattern!;
          formatted = nullable
              ? '($formatted == null ? null : ${formatterName}FormatToJson($formatted))'
              : '${formatterName}FormatToJson($formatted)';
          break;
      }
    }
    return formatted;
  }

  String _applyFormattersFromJsonExpr(
    String expr,
    String typeStr,
    List<_FormatSpec> formats,
  ) {
    if (formats.isEmpty) return expr;
    final bool nullable = typeStr.endsWith('?');
    final String baseType = _nonNullableType(typeStr);
    String formatted = expr;
    for (final _FormatSpec format in formats) {
      switch (format.kind) {
        case 'trim':
          if (baseType != 'String') continue;
          formatted = nullable
              ? '($formatted == null ? null : $formatted.trim())'
              : '($formatted).trim()';
          break;
        case 'uppercase':
          if (baseType != 'String') continue;
          formatted = nullable
              ? '($formatted == null ? null : $formatted.toUpperCase())'
              : '($formatted).toUpperCase()';
          break;
        case 'lowercase':
          if (baseType != 'String') continue;
          formatted = nullable
              ? '($formatted == null ? null : $formatted.toLowerCase())'
              : '($formatted).toLowerCase()';
          break;
        case 'date':
          if (baseType != 'DateTime' || format.pattern == null) continue;
          final String patternLiteral = _literalToCode(format.pattern);
          formatted = nullable
              ? '($formatted == null ? null : Serializer.parseDate($formatted, $patternLiteral))'
              : 'Serializer.parseDate(($formatted), $patternLiteral)';
          break;
        case 'custom':
        case 'customWith':
          if (format.pattern == null || format.pattern!.isEmpty) continue;
          final String formatterName = format.pattern!;
          formatted = nullable
              ? '($formatted == null ? null : ${formatterName}FormatFromJson($formatted))'
              : '${formatterName}FormatFromJson($formatted)';
          break;
      }
    }
    return formatted;
  }

  // ---------------------------------------------------------------------------
  // Collection element expressions
  // ---------------------------------------------------------------------------

  String _toJsonExpr(
    String expr,
    String typeStr,
    DartType type, {
    required bool useEnumIndex,
    required String? unknownEnumValue,
    required Set<String> typeParameterNames,
  }) {
    // Bare type parameter inside a collection: `List<T>`, `Map<String, T>`.
    final String? typeParamName = _typeParameterName(type, typeParameterNames);
    if (typeParamName != null) {
      return 'encode$typeParamName($expr)';
    }
    if (type is InterfaceType && type.isDartCoreList) {
      final DartType typeArg = type.typeArguments.first;
      return '($expr as List).map((e) => ${_toJsonExpr('e', typeArg.toString(), typeArg, useEnumIndex: false, unknownEnumValue: null, typeParameterNames: typeParameterNames)}).toList()';
    }
    if (type is InterfaceType && type.isDartCoreSet) {
      final DartType typeArg = type.typeArguments.first;
      return '($expr as Set).map((e) => ${_toJsonExpr('e', typeArg.toString(), typeArg, useEnumIndex: false, unknownEnumValue: null, typeParameterNames: typeParameterNames)}).toList()';
    }
    if (type is InterfaceType && type.isDartCoreMap) {
      final DartType valueType = type.typeArguments.last;
      return '($expr as Map).map((k, v) => MapEntry(k.toString(), ${_toJsonExpr('v', valueType.toString(), valueType, useEnumIndex: false, unknownEnumValue: null, typeParameterNames: typeParameterNames)}))';
    }
    if (type.element?.name == 'DateTime') return '$expr.toIso8601String()';
    if (type.element?.name == 'Uri') return '$expr.toString()';
    if (type.element?.name == 'BigInt') return '$expr.toString()';
    if (type.element?.name == 'Duration') return '$expr.inMicroseconds';
    if (type.element?.kind == ElementKind.ENUM) {
      return useEnumIndex ? '$expr.index' : '$expr.name';
    }
    if (type.isDartCoreInt ||
        type.isDartCoreDouble ||
        type.isDartCoreString ||
        type.isDartCoreBool ||
        type.element?.name == 'dynamic') {
      return expr;
    }
    return '$expr.toJson()';
  }

  String _fromJsonExpr(
    String expr,
    String typeStr,
    DartType type, {
    required bool useEnumIndex,
    required String? unknownEnumValue,
    required Set<String> typeParameterNames,
  }) {
    // Bare type parameter inside a collection: `List<T>`, `Map<String, T>`.
    final String? typeParamName = _typeParameterName(type, typeParameterNames);
    if (typeParamName != null) {
      return 'decode$typeParamName($expr as Map<String, dynamic>)';
    }
    if (type is InterfaceType && type.isDartCoreList) {
      final DartType typeArg = type.typeArguments.first;
      return '($expr as List).map((e) => ${_fromJsonExpr('e', typeArg.toString(), typeArg, useEnumIndex: false, unknownEnumValue: null, typeParameterNames: typeParameterNames)}).toList()';
    }
    if (type is InterfaceType && type.isDartCoreSet) {
      final DartType typeArg = type.typeArguments.first;
      return '($expr as List).map((e) => ${_fromJsonExpr('e', typeArg.toString(), typeArg, useEnumIndex: false, unknownEnumValue: null, typeParameterNames: typeParameterNames)}).toSet()';
    }
    if (type is InterfaceType && type.isDartCoreMap) {
      final DartType valueType = type.typeArguments.last;
      return '($expr as Map).map((k, v) => MapEntry(k.toString(), ${_fromJsonExpr('v', valueType.toString(), valueType, useEnumIndex: false, unknownEnumValue: null, typeParameterNames: typeParameterNames)}))';
    }
    if (type.element?.name == 'DateTime') {
      return 'DateTime.parse($expr as String)';
    }
    if (type.element?.name == 'Uri') return 'Uri.parse($expr as String)';
    if (type.element?.name == 'BigInt') return 'BigInt.parse($expr as String)';
    if (type.element?.name == 'Duration') {
      return 'Duration(microseconds: ($expr as num).toInt())';
    }
    if (type.element?.kind == ElementKind.ENUM) {
      return _enumFromJsonExpr(
        expr,
        typeStr,
        useEnumIndex,
        unknownEnumValue,
        nullable: typeStr.endsWith('?'),
      );
    }
    if (type.isDartCoreInt) return '($expr as num).toInt()';
    if (type.isDartCoreDouble) return '($expr as num).toDouble()';
    if (type.isDartCoreString ||
        type.isDartCoreBool ||
        type.element?.name == 'dynamic') {
      return '$expr as $typeStr';
    }
    return '${typeStr}FromJson($expr as Map<String, dynamic>)';
  }

  /// Returns the name of the type parameter that [type] resolves to,
  /// or `null` if [type] is not one of the class's type parameters.
  ///
  /// Recognises both `T` and `T?` (nullable generic).
  String? _typeParameterName(DartType type, Set<String> typeParameterNames) {
    final String base = _nonNullableType(type.toString());
    return typeParameterNames.contains(base) ? base : null;
  }

  // ---------------------------------------------------------------------------
  // Annotation read helpers
  // ---------------------------------------------------------------------------

  String _nonNullableType(String typeStr) =>
      typeStr.endsWith('?') ? typeStr.substring(0, typeStr.length - 1) : typeStr;

  String? _readOptionalString(ConstantReader reader, String field) {
    final ConstantReader? value = reader.peek(field);
    if (value == null || value.isNull || !value.isString) {
      return null;
    }
    return value.stringValue;
  }

  String? _readOptionalTypeName(ConstantReader reader, String field) {
    final ConstantReader? value = reader.peek(field);
    if (value == null || value.isNull || !value.isType) {
      return null;
    }
    // ignore: deprecated_member_use
    return value.typeValue.getDisplayString(withNullability: false);
  }

  bool? _readOptionalBool(ConstantReader reader, String field) {
    final ConstantReader? value = reader.peek(field);
    if (value == null || value.isNull || !value.isBool) {
      return null;
    }
    return value.boolValue;
  }

  UnknownKeyPolicy _readUnknownKeyPolicy(
    ConstantReader annotation,
    bool strictBool,
  ) {
    final ConstantReader? value = annotation.peek('unknownKeyPolicy');
    if (value != null && !value.isNull) {
      final String name = value.revive().accessor;
      if (name == 'UnknownKeyPolicy.strict') return UnknownKeyPolicy.strict;
      if (name == 'UnknownKeyPolicy.ignore') return UnknownKeyPolicy.ignore;
      if (name == 'UnknownKeyPolicy.capture') return UnknownKeyPolicy.capture;
    }
    if (strictBool) return UnknownKeyPolicy.strict;
    return UnknownKeyPolicy.ignore;
  }

  JsonNaming _readNaming(ConstantReader annotation) {
    final ConstantReader? value = annotation.peek('naming');
    if (value == null || value.isNull) return JsonNaming.none;
    final String name = value.revive().accessor;
    if (name == 'JsonNaming.snakeCase') return JsonNaming.snakeCase;
    if (name == 'JsonNaming.camelCase') return JsonNaming.camelCase;
    if (name == 'JsonNaming.kebabCase') return JsonNaming.kebabCase;
    if (name == 'JsonNaming.pascalCase') return JsonNaming.pascalCase;
    return JsonNaming.none;
  }

  String _namingAsString(JsonNaming naming) {
    switch (naming) {
      case JsonNaming.snakeCase:
        return 'snakeCase';
      case JsonNaming.camelCase:
        return 'camelCase';
      case JsonNaming.kebabCase:
        return 'kebabCase';
      case JsonNaming.pascalCase:
        return 'pascalCase';
      case JsonNaming.none:
        return 'none';
    }
  }

  String? _readDefaultValueCode(ConstantReader annotation) {
    final ConstantReader? value = annotation.peek('defaultValue');
    if (value == null || value.isNull) return null;
    return _literalToCode(value.literalValue);
  }

  String _literalToCode(Object? value) {
    if (value == null) return 'null';
    if (value is String) {
      final String escaped = value
          .replaceAll(r'\\', r'\\\\')
          .replaceAll("'", r"\'")
          .replaceAll('\n', r'\\n');
      return "'$escaped'";
    }
    if (value is bool || value is num) return value.toString();
    if (value is List) {
      return '<dynamic>[${value.map(_literalToCode).join(', ')}]';
    }
    if (value is Set) {
      return '<dynamic>{${value.map(_literalToCode).join(', ')}}';
    }
    if (value is Map) {
      final String items = value.entries
          .map((MapEntry<dynamic, dynamic> entry) =>
              '${_literalToCode(entry.key)}: ${_literalToCode(entry.value)}')
          .join(', ');
      return '<dynamic, dynamic>{$items}';
    }
    throw InvalidGenerationSourceError(
      'Unsupported defaultValue type: ${value.runtimeType}. Use literal values only.',
    );
  }
}

// ---------------------------------------------------------------------------
// Private data classes
// ---------------------------------------------------------------------------

class _ClassMetadata {
  const _ClassMetadata({
    required this.className,
    required this.rename,
    required this.discriminator,
    required this.typeField,
    required this.unknownKeyPolicy,
    required this.naming,
    required this.resolvedDiscriminator,
    required this.typeParameters,
  });

  final String className;
  final String? rename;
  final String? discriminator;
  final String? typeField;
  final UnknownKeyPolicy unknownKeyPolicy;
  final JsonNaming naming;
  final String resolvedDiscriminator;

  /// Names of the type parameters declared on the class (e.g.
  /// `['T']` for `class ApiResponse<T>`). Empty for non-generic
  /// classes.
  final List<String> typeParameters;

  /// Convenience predicate for the common `if (isGeneric)` checks
  /// throughout the renderer.
  bool get isGeneric => typeParameters.isNotEmpty;
}

class _GenerationPlan {
  const _GenerationPlan({
    required this.toJsonEntries,
    required this.fromJsonParams,
    required this.fromJsonGuards,
  });

  final List<String> toJsonEntries;
  final List<String> fromJsonParams;
  final List<String> fromJsonGuards;
}

class _FormatSpec {
  const _FormatSpec({required this.kind, required this.pattern});

  final String kind;
  final String? pattern;
}

class _DiscriminatorSite {
  const _DiscriminatorSite({
    required this.className,
    required this.typeField,
    required this.discriminator,
  });

  final String className;
  final String typeField;
  final String discriminator;
}

/// Find `@SerializableUnion` in the class hierarchy and return its
/// annotation, if present. Walks up supertypes so a concrete subtype
/// can be detected as part of a sealed union.
ConstantReader? _findSerializableUnionAnnotation(ClassElement element) {
  for (final ElementAnnotation annotation in element.metadata.annotations) {
    final constant = annotation.computeConstantValue();
    if (constant != null) {
      // ignore: deprecated_member_use
      final typeName = constant.type?.getDisplayString(withNullability: false);
      if (typeName == _serializableUnionName) {
        return ConstantReader(constant);
      }
    }
  }

  final supertype = element.supertype;
  if (supertype != null && supertype.element is ClassElement) {
    final result = _findSerializableUnionAnnotation(
      supertype.element as ClassElement,
    );
    if (result != null) return result;
  }

  return null;
}
