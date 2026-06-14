import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';

/// Modelos de datos que representan una clase `@RestClient` parseada.
///
/// Movido desde `d_rest_build/lib/parser.dart` ( del roadmap
/// de d_rocket). El codegen ahora vive en `d_rocket_builder` y
/// produce código que importa de `package:d_rocket/d_rocket.dart`
/// (que reexporta `@RestClient`, `@Route`, `@HttpGet`, `@Body`,
/// etc. — absorbido de `d_rest` 0.1.0 en esta misma fase).
class ParsedClient {
  final String className;
  final String baseUrl;
  final String classPath;
  final Map<String, String> classHeaders;
  final Duration? classTimeout;
  final List<ParsedMethod> methods;

  ParsedClient({
    required this.className,
    required this.baseUrl,
    required this.classPath,
    required this.classHeaders,
    required this.classTimeout,
    required this.methods,
  });
}

class ParsedMethod {
  final String name;
  final String verb; // 'GET', 'POST', ...
  final String path;
  final Map<String, String> methodHeaders;
  final ParsedReturnType returnType;
  final List<ParsedParameter> parameters;
  final Duration? timeout;

  ParsedMethod({
    required this.name,
    required this.verb,
    required this.path,
    required this.methodHeaders,
    required this.returnType,
    required this.parameters,
    required this.timeout,
  });
}

enum ParamKind { body, query, path, header, field, part, rawBody, implicit }

class ParsedParameter {
  final String name;
  final String? annotationName;
  final ParamKind kind;
  final String dartType;
  final bool isRequired;
  final bool isNullable;
  final bool isNamed;

  ParsedParameter({
    required this.name,
    required this.annotationName,
    required this.kind,
    required this.dartType,
    required this.isRequired,
    required this.isNullable,
    required this.isNamed,
  });
}

class ParsedReturnType {
  final String dartType;
  final bool isVoid;
  final bool isDynamic;
  final bool isList;
  final bool isMap;
  final String? innerType;
  final String? mapKeyType;
  final String? mapValueType;

  ParsedReturnType({
    required this.dartType,
    required this.isVoid,
    required this.isDynamic,
    required this.isList,
    required this.isMap,
    this.innerType,
    this.mapKeyType,
    this.mapValueType,
  });
}

class ClientParser {
  static const Set<String> _verbAnnotationNames = <String>{
    'HttpGet',
    'HttpPost',
    'HttpPut',
    'HttpPatch',
    'HttpDelete',
    'HttpHead',
    'HttpOptions',
  };

  static const Map<String, String> _verbToString = <String, String>{
    'HttpGet': 'GET',
    'HttpPost': 'POST',
    'HttpPut': 'PUT',
    'HttpPatch': 'PATCH',
    'HttpDelete': 'DELETE',
    'HttpHead': 'HEAD',
    'HttpOptions': 'OPTIONS',
  };

  static ParsedClient parseClass(ClassElement classElement) {
    if (!classElement.isAbstract) {
      throw InvalidGenerationSourceError(
        '@RestClient can only be applied to abstract classes.',
        element: classElement,
      );
    }

    final DartObject? restClient =
        _findAnnotationByName(classElement, 'RestClient');
    if (restClient == null) {
      throw InvalidGenerationSourceError(
        'Missing @RestClient annotation.',
        element: classElement,
      );
    }

    final String baseUrl = _readStringOrEmpty(restClient, 'baseUrl');
    final Map<String, String> classHeaders =
        _readStringMap(restClient, 'headers');
    final Duration? classTimeout = _readDuration(restClient, 'timeout');

    String classPath = '';
    String? classBaseUrlOverride;
    final DartObject? route = _findAnnotationByName(classElement, 'Route');
    if (route != null) {
      classPath = _readStringOrEmpty(route, 'path');
      final String? override = _readString(route, 'baseUrl');
      if (override != null) classBaseUrlOverride = override;
    }

    final String finalBaseUrl = classBaseUrlOverride ?? baseUrl;

    final List<ParsedMethod> methods = <ParsedMethod>[];
    for (final MethodElement method in classElement.methods) {
      if (!method.isAbstract) continue;
      if (method.isStatic) continue;
      final String? methodName = method.name;
      if (methodName == null) continue;
      if (methodName.startsWith('_')) continue;
      final ParsedMethod? parsed = _parseMethod(method, classPath);
      if (parsed != null) methods.add(parsed);
    }

    return ParsedClient(
      className: classElement.name ?? '',
      baseUrl: finalBaseUrl,
      classPath: classPath,
      classHeaders: classHeaders,
      classTimeout: classTimeout,
      methods: methods,
    );
  }

  static ParsedMethod? _parseMethod(MethodElement method, String classPath) {
    final List<ElementAnnotation> verbAnnotations = <ElementAnnotation>[];
    for (final ElementAnnotation m in method.metadata.annotations) {
      final String? annName = m.element?.displayName;
      if (annName != null && _verbAnnotationNames.contains(annName)) {
        verbAnnotations.add(m);
      }
    }

    if (verbAnnotations.isEmpty) return null;
    if (verbAnnotations.length > 1) {
      throw InvalidGenerationSourceError(
        'Method "${method.name}" has multiple HTTP verb annotations.',
        element: method,
      );
    }

    final ElementAnnotation verbMeta = verbAnnotations.first;
    final String? verbName = verbMeta.element?.displayName;
    if (verbName == null) return null;
    final String verbString = _verbToString[verbName] ?? verbName;
    final DartObject? verbValueOpt = verbMeta.computeConstantValue();
    if (verbValueOpt == null) return null;
    final DartObject verbValue = verbValueOpt;

    // The `path` field is defined on the `HttpVerb`
    // base class. `DartObject.getField('path')`
    // sometimes returns null on inherited fields
    // when the annotation is a subclass instance
    // (e.g. `HttpGet`). As fallbacks:
    //   1. Try the well-known positional field
    //      names analyzer uses for inherited
    //      positional args.
    //   2. Parse the `path: '...'` token out of
    //      the annotation's `toString()` form,
    //      which is `ClassName(path: /value, headers: {...})`
    //      for a const annotation. (1.0.7's regex
    //      expected `ClassName('/value')` with
    //      quotes, which is the wrong shape for
    //      analyzer's toString.)
    String verbPath = _readStringOrEmpty(verbValue, 'path');
    if (verbPath.isEmpty) {
      // Try common positional field names.
      for (final String name in <String>['path', 'positional_0', '_path']) {
        final DartObject? v = verbValue.getField(name);
        if (v != null && !v.isNull) {
          final String? s = v.toStringValue();
          if (s != null && s.isNotEmpty) {
            verbPath = s;
            break;
          }
        }
      }
    }
    if (verbPath.isEmpty) {
      // Parse `path: <value>` out of the
      // annotation's toString. The format is
      //   HttpGet(path: /items/{id}, headers: {})
      // — value is unquoted, ends at `,` or `)`.
      final String repr = verbValue.toString();
      final RegExpMatch? m = RegExp(
              r"path\s*:\s*(?:'([^']*)'|/([^,)]+))")
          .firstMatch(repr);
      if (m != null) {
        verbPath = m.group(1) ?? m.group(2) ?? '';
      }
    }
    final Map<String, String> methodHeaders =
        _readStringMap(verbValue, 'headers');

    // Detectar retorno: el método retorna Future<T> o FutureOr<T> o nada.
    final DartType returnType = method.returnType;
    final ParsedReturnType parsedReturn = _unwrapFuture(returnType);

    final List<ParsedParameter> params = <ParsedParameter>[];
    for (final FormalParameterElement p in method.formalParameters) {
      params.add(_parseParameter(p));
    }

    return ParsedMethod(
      name: method.name ?? '',
      verb: verbString,
      path: verbPath,
      methodHeaders: methodHeaders,
      returnType: parsedReturn,
      parameters: params,
      timeout: null,
    );
  }

  static ParsedParameter _parseParameter(FormalParameterElement p) {
    ParamKind kind = ParamKind.implicit;
    String? annName;

    for (final ElementAnnotation meta in p.metadata.annotations) {
      final String? name = meta.element?.displayName;
      switch (name) {
        case 'Body':
          kind = ParamKind.body;
          break;
        case 'Query':
          kind = ParamKind.query;
          annName = _readString(meta.computeConstantValue(), 'name');
          break;
        case 'Path':
          kind = ParamKind.path;
          annName = _readString(meta.computeConstantValue(), 'name');
          break;
        case 'Header':
          kind = ParamKind.header;
          annName = _readString(meta.computeConstantValue(), 'name');
          break;
        case 'Field':
          kind = ParamKind.field;
          annName = _readString(meta.computeConstantValue(), 'name');
          break;
        case 'Part':
          kind = ParamKind.part;
          annName = _readString(meta.computeConstantValue(), 'name');
          break;
        case 'RawBody':
          kind = ParamKind.rawBody;
          break;
        default:
          // Otras anotaciones (ej. @Format) se ignoran aquí.
          break;
      }
    }

    return ParsedParameter(
      name: p.name ?? '',
      annotationName: annName,
      kind: kind,
      dartType: p.type.getDisplayString(),
      isRequired: p.isRequired,
      isNullable: p.type.nullabilitySuffix == NullabilitySuffix.question,
      isNamed: p.isNamed,
    );
  }

  static ParsedReturnType _unwrapFuture(DartType returnType) {
    if (returnType is VoidType) {
      return ParsedReturnType(
        dartType: 'void',
        isVoid: true,
        isDynamic: false,
        isList: false,
        isMap: false,
      );
    }
    if (returnType is InterfaceType) {
      final String? name = returnType.element.name;
      if (name == 'Future' || name == 'FutureOr') {
        if (returnType.typeArguments.isEmpty) {
          return ParsedReturnType(
            dartType: 'dynamic',
            isVoid: false,
            isDynamic: true,
            isList: false,
            isMap: false,
          );
        }
        return _describeType(returnType.typeArguments.first);
      }
    }
    return _describeType(returnType);
  }

  static ParsedReturnType _describeType(DartType type) {
    final String display = type.getDisplayString();
    final bool isDynamic = _isDynamicType(type);
    if (type is InterfaceType) {
      final String? name = type.element.name;
      if (name == 'List') {
        final String? inner = type.typeArguments.isNotEmpty
            ? type.typeArguments.first.getDisplayString()
            : null;
        return ParsedReturnType(
          dartType: display,
          isVoid: false,
          isDynamic: false,
          isList: true,
          isMap: false,
          innerType: inner,
        );
      }
      if (name == 'Map') {
        final String? k = type.typeArguments.length >= 1
            ? type.typeArguments[0].getDisplayString()
            : null;
        final String? v = type.typeArguments.length >= 2
            ? type.typeArguments[1].getDisplayString()
            : null;
        return ParsedReturnType(
          dartType: display,
          isVoid: false,
          isDynamic: false,
          isList: false,
          isMap: true,
          mapKeyType: k,
          mapValueType: v,
        );
      }
    }
    return ParsedReturnType(
      dartType: display,
      isVoid: false,
      isDynamic: isDynamic,
      isList: false,
      isMap: false,
    );
  }

  /// `DartType.isDynamic` existed in analyzer 6.x but was removed in 8.x.
  /// Infer "dynamic" by checking the display string.
  static bool _isDynamicType(DartType type) {
    final String display = type.getDisplayString();
    return display == 'dynamic';
  }

  // ---------- annotation helpers ----------

  static DartObject? _findAnnotationByName(Element element, String name) {
    for (final ElementAnnotation meta in element.metadata.annotations) {
      if (meta.element?.displayName == name) {
        return meta.computeConstantValue();
      }
    }
    return null;
  }

  static String? _readString(DartObject? obj, String field) {
    if (obj == null) return null;
    final DartObject? value = obj.getField(field);
    if (value == null || value.isNull) return null;
    return value.toStringValue();
  }

  static String _readStringOrEmpty(DartObject obj, String field) {
    return _readString(obj, field) ?? '';
  }

  static Map<String, String> _readStringMap(DartObject obj, String field) {
    final Map<String, String> result = <String, String>{};
    final DartObject? mapObj = obj.getField(field);
    if (mapObj == null || mapObj.isNull) return result;
    final Map<DartObject?, DartObject?>? raw = mapObj.toMapValue();
    if (raw == null) return result;
    for (final MapEntry<DartObject?, DartObject?> entry in raw.entries) {
      final String? k = entry.key?.toStringValue();
      final String? v = entry.value?.toStringValue();
      if (k != null && v != null) result[k] = v;
    }
    return result;
  }

  static Duration? _readDuration(DartObject obj, String field) {
    final DartObject? value = obj.getField(field);
    if (value == null || value.isNull) return null;
    final DartObject? micros = value.getField('_microseconds');
    if (micros == null) return null;
    final int? i = micros.toIntValue();
    if (i == null) return null;
    return Duration(microseconds: i);
  }
}
