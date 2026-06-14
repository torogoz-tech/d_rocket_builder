import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:d_rocket/d_rocket.dart';
import 'package:d_rocket_builder/src/rest/emitter.dart';
import 'package:d_rocket_builder/src/rest/parser.dart';
import 'package:source_gen/source_gen.dart';

/// Generador principal para `@RestClient`: produce un `_$ClassName`
/// que implementa la clase abstracta anotada.
///
/// Movido desde `d_rest_build/lib/client_builder.dart` ( del
/// roadmap de d_rocket). El codegen ahora vive en
/// `d_rocket_builder` y produce código que importa de
/// `package:d_rocket/d_rocket.dart` (que reexporta `@RestClient`,
/// `@Route`, `@HttpGet`, etc. — absorbido de `d_rest` 0.1.0).
class RestClientGenerator extends GeneratorForAnnotation<RestClient> {
  const RestClientGenerator();

  @override
  Future<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) async {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@RestClient can only be applied to classes.',
        element: element,
      );
    }

    final ParsedClient parsed = ClientParser.parseClass(element);
    return emitClient(parsed);
  }
}
