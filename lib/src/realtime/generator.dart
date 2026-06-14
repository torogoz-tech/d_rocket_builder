//: codegen for `@WebSocketClient`
// and `@SseClient`. Emits a `_$<ClassName>` that
// extends [IOWebSocketClient] or [HttpSseClient]
// with the URL + headers pre-filled from the
// annotation. The user can then override the
// generated class with their own business
// logic (typed events, etc.) in a separate
// file.

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:d_rocket/d_rocket.dart';
import 'package:source_gen/source_gen.dart';

///: generator for `@WebSocketClient`.
/// Produces a `_$<ClassName>` that extends
/// [IOWebSocketClient] with the URL + headers
/// baked in.
class WebSocketClientGenerator
    extends GeneratorForAnnotation<WebSocketClient> {
  const WebSocketClientGenerator();

  @override
  Future<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) async {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@WebSocketClient can only be applied to classes.',
        element: element,
      );
    }
    final String className = element.displayName;
    final String url = annotation.read('url').stringValue;
    final Map<String, String> headers = <String, String>{};
    for (final MapEntry<dynamic, dynamic> entry
        in annotation.read('headers').mapValue.entries) {
      final String? k = entry.key.toStringValue() as String?;
      final String? v = entry.value.toStringValue() as String?;
      if (k != null && v != null) {
        headers[k] = v;
      }
    }
    final String headersLiteral = _headersLiteral(headers);
    return '''
class _\$\$$className extends IOWebSocketClient {
  _\$\$$className() : super();

  ///  (codegen): the URL baked
  /// into the annotation.
  static const String url = ${_q(url)};

  ///  (codegen): the default
  /// headers baked into the annotation.
  static const Map<String, String> headers = $headersLiteral;

  ///  (codegen): connect with the
  /// baked URL + headers.
  Future<void> connectWithDefaults() =>
      connect(Uri.parse(url), headers: headers);
}

WebSocketClient register${className}WebSocketClient() =>
    _\$\$$className();
''';
  }
}

///: generator for `@SseClient`.
/// Produces a `_$<ClassName>` that extends
/// [HttpSseClient] with the URL + headers baked in.
class SseClientGenerator extends GeneratorForAnnotation<SseClient> {
  const SseClientGenerator();

  @override
  Future<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) async {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@SseClient can only be applied to classes.',
        element: element,
      );
    }
    final String className = element.displayName;
    final String url = annotation.read('url').stringValue;
    final Map<String, String> headers = <String, String>{};
    for (final MapEntry<dynamic, dynamic> entry
        in annotation.read('headers').mapValue.entries) {
      final String? k = entry.key.toStringValue() as String?;
      final String? v = entry.value.toStringValue() as String?;
      if (k != null && v != null) {
        headers[k] = v;
      }
    }
    final String headersLiteral = _headersLiteral(headers);
    return '''
class _\$\$$className extends HttpSseClient {
  _\$\$$className() : super();

  ///  (codegen): the URL baked
  /// into the annotation.
  static const String url = ${_q(url)};

  ///  (codegen): the default
  /// headers baked into the annotation.
  static const Map<String, String> headers = $headersLiteral;

  ///  (codegen): stream of [SseEvent]s
  /// from the baked URL.
  Stream<SseEvent> connectWithDefaults() =>
      connect(Uri.parse(url), headers: headers);
}

SseClient register${className}SseClient() =>
    _\$\$$className();
''';
  }
}

String _q(String s) => "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";

String _headersLiteral(Map<String, String> headers) {
  if (headers.isEmpty) return 'const <String, String>{}';
  final List<String> entries = <String>[
    for (final MapEntry<String, String> e in headers.entries)
      '  ${_q(e.key)}: ${_q(e.value)},',
  ];
  return 'const <String, String>{\n${entries.join('\n')}\n}';
}
