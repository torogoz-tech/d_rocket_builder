import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:d_rocket/d_rocket.dart';
import 'package:source_gen/source_gen.dart';

typedef FormFieldMetadata = ({
  FieldElement field,
  String? label,
  int order,
  FormInput input,
  List<String> binding,
  List<({String name, ConstantReader annotation})> validators,
});

/// Metadata extracted from one class annotated with [Form].
class FormMetadata {
  FormMetadata({required this.className, required this.fields});

  final String className;
  final List<FormFieldMetadata> fields;

  factory FormMetadata.read(ClassElement element) {
    if (element.isAbstract) {
      throw InvalidGenerationSourceError(
        '@Form cannot be applied to abstract class ${element.displayName}; '
        'the generated adapter must construct a concrete model.',
        element: element,
      );
    }

    final List<FormFieldMetadata> fields = element.fields
        .where((FieldElement field) => !field.isStatic && !field.isPrivate)
        .map((FieldElement field) {
      final ConstantReader? formField = _annotation(field, 'FormField');
      return (
        field: field,
        label: _readNullableString(formField, 'label'),
        order: _readInt(formField, 'order') ?? 0,
        input: _readInput(formField),
        binding: _readBinding(formField),
        validators: <({String name, ConstantReader annotation})>[
          for (final String name in <String>[
            'Required',
            'Email',
            'Length',
            'Pattern',
            'Range',
            'Uuid',
          ])
            if (_annotation(field, name) case final ConstantReader value)
              (name: name, annotation: value),
        ],
      );
    }).toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    if (fields.isEmpty) {
      throw InvalidGenerationSourceError(
        '@Form on ${element.displayName} requires at least one public '
        'instance field.',
        element: element,
      );
    }

    final Set<String> publicFields =
        fields.map((FormFieldMetadata item) => item.field.displayName).toSet();
    final Map<String, String> bindingOwners = <String, String>{};
    for (final FormFieldMetadata item in fields) {
      if (item.binding.toSet().length != item.binding.length ||
          item.binding.contains(item.field.displayName)) {
        throw InvalidGenerationSourceError(
          '@FormField binding on ${element.displayName}.${item.field.displayName} '
          'must contain unique target fields other than the source field.',
          element: item.field,
        );
      }
      for (final String target in item.binding) {
        if (!publicFields.contains(target)) {
          throw InvalidGenerationSourceError(
            'Composite form binding target "$target" does not exist on '
            '${element.displayName}.',
            element: item.field,
          );
        }
        final String? owner = bindingOwners[target];
        if (owner != null) {
          throw InvalidGenerationSourceError(
            'Composite form binding target "$target" is declared by both '
            '$owner and ${item.field.displayName}.',
            element: item.field,
          );
        }
        bindingOwners[target] = item.field.displayName;
      }
      final String baseType = item.field.type.toString().replaceAll('?', '');
      for (final ({String name, ConstantReader annotation}) validator
          in item.validators) {
        final bool stringValidator = <String>{
          'Email',
          'Length',
          'Pattern',
          'Uuid',
        }.contains(validator.name);
        final bool numericValidator = validator.name == 'Range';
        if (stringValidator && baseType != 'String') {
          throw InvalidGenerationSourceError(
            '@${validator.name} on ${element.displayName}.'
            '${item.field.displayName} requires String, found $baseType.',
            element: item.field,
          );
        }
        if (numericValidator &&
            baseType != 'int' &&
            baseType != 'double' &&
            baseType != 'num') {
          throw InvalidGenerationSourceError(
            '@Range on ${element.displayName}.${item.field.displayName} '
            'requires int, double or num, found $baseType.',
            element: item.field,
          );
        }
      }
    }

    ConstructorElement? constructor;
    for (final ConstructorElement candidate in element.constructors) {
      if (!candidate.isFactory &&
          (candidate.name == null ||
              candidate.name!.isEmpty ||
              candidate.name == 'new')) {
        constructor = candidate;
        break;
      }
    }
    if (constructor == null) {
      throw InvalidGenerationSourceError(
        '@Form on ${element.displayName} requires an unnamed generative '
        'constructor with named parameters for every public instance field.',
        element: element,
      );
    }

    for (final FormFieldMetadata item in fields) {
      final bool hasNamedParameter = constructor.formalParameters.any(
        (FormalParameterElement parameter) =>
            parameter.isNamed && parameter.name == item.field.displayName,
      );
      if (!hasNamedParameter) {
        throw InvalidGenerationSourceError(
          '${element.displayName}.${item.field.displayName} is annotated '
          'with @FormField but is not an unnamed constructor named parameter.',
          element: item.field,
        );
      }
    }

    return FormMetadata(className: element.displayName, fields: fields);
  }
}

ConstantReader? _annotation(Element element, String name) {
  for (final ElementAnnotation metadata in element.metadata.annotations) {
    final Uri? libraryUri = metadata.element?.library?.uri;
    if (metadata.element?.displayName != name ||
        libraryUri?.scheme != 'package' ||
        libraryUri!.pathSegments.isEmpty ||
        libraryUri.pathSegments.first != 'd_rocket') {
      continue;
    }
    return ConstantReader(metadata.computeConstantValue());
  }
  return null;
}

String? _readNullableString(ConstantReader? reader, String name) {
  if (reader == null) return null;
  final ConstantReader value = reader.read(name);
  return value.isString ? value.stringValue : null;
}

int? _readInt(ConstantReader? reader, String name) {
  if (reader == null) return null;
  final ConstantReader value = reader.read(name);
  return value.isInt ? value.intValue : null;
}

FormInput _readInput(ConstantReader? reader) {
  if (reader == null) return FormInput.text;
  final String value = reader.read('input').revive().accessor;
  return FormInput.values.firstWhere(
    (FormInput input) =>
        value == input.name || value.endsWith('.${input.name}'),
    orElse: () => FormInput.text,
  );
}

List<String> _readBinding(ConstantReader? reader) {
  if (reader == null) return const <String>[];
  final ConstantReader? binding = reader.peek('binding');
  if (binding == null || binding.isNull) return const <String>[];
  return binding
      .read('fields')
      .listValue
      .map((DartObject value) => ConstantReader(value).stringValue)
      .toList(growable: false);
}

String nullableType(DartType type) {
  final String display = type.toString();
  return type.nullabilitySuffix.name == 'none' ? '$display?' : display;
}
