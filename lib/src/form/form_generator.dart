import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:d_rocket/d_rocket.dart';
import 'package:source_gen/source_gen.dart';

import 'form_metadata.dart';
import 'form_source_writer.dart';

/// Generates a model adapter for classes annotated with [Form].
class FormGenerator extends GeneratorForAnnotation<Form> {
  const FormGenerator();

  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@Form can only be applied to classes.',
        element: element,
      );
    }

    return const FormSourceWriter().write(FormMetadata.read(element));
  }
}
