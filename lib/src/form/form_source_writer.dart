import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:d_rocket/d_rocket.dart';
import 'package:source_gen/source_gen.dart';

import 'form_metadata.dart';
import 'uuid_pattern.dart';

/// Writes the generated adapter that binds model fields to [FormState].
class FormSourceWriter {
  const FormSourceWriter();

  String write(FormMetadata metadata) {
    final String adapterName = '${metadata.className}Form';
    final StringBuffer output = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln()
      ..writeln('class $adapterName {')
      ..writeln('  $adapterName({');

    for (final ({
      FieldElement field,
      String? label,
      int order,
      FormInput input,
      List<({String name, ConstantReader annotation})> validators
    }) item in metadata.fields) {
      output.writeln(
        '    ${nullableType(item.field.type)} initial${_pascal(item.field.displayName)},',
      );
    }

    output
      ..writeln(
          '    List<FormValidator<${metadata.className}>> validators = const <FormValidator<${metadata.className}>>[],')
      ..writeln(
          '    List<AsyncFormValidator<${metadata.className}>> asyncValidators = const <AsyncFormValidator<${metadata.className}>>[],')
      ..writeln('    Duration? asyncValidationDebounce,')
      ..writeln(
          '    FormValidationMode validationMode = FormValidationMode.onSubmit,')
      ..writeln('  }) : state = _createState(');

    for (final ({
      FieldElement field,
      String? label,
      int order,
      FormInput input,
      List<({String name, ConstantReader annotation})> validators
    }) item in metadata.fields) {
      output.writeln(
        '    initial${_pascal(item.field.displayName)},',
      );
    }
    output
      ..writeln('    validators,')
      ..writeln('    asyncValidators,')
      ..writeln('    asyncValidationDebounce,')
      ..writeln('    validationMode,')
      ..writeln('  );')
      ..writeln()
      ..writeln('  final FormState<${metadata.className}> state;');

    output
      ..writeln()
      ..writeln('  static const List<FormFieldDefinition> definitions = '
          '<FormFieldDefinition>[');
    for (final ({
      FieldElement field,
      String? label,
      int order,
      FormInput input,
      List<({String name, ConstantReader annotation})> validators
    }) item in metadata.fields) {
      output.writeln(
        "    FormFieldDefinition(name: '${item.field.displayName}', "
        "label: ${_nullableString(item.label)}, order: ${item.order}, "
        'input: FormInput.${item.input.name}),',
      );
    }
    output.writeln('  ];');

    for (final ({
      FieldElement field,
      String? label,
      int order,
      FormInput input,
      List<({String name, ConstantReader annotation})> validators
    }) item in metadata.fields) {
      output.writeln(
        '  FormFieldState<${item.field.type}> get ${item.field.displayName} => '
        "state.fields['${item.field.displayName}']! as FormFieldState<${item.field.type}>;",
      );
    }

    output
      ..writeln('  bool validate() => state.validate();')
      ..writeln('  Future<bool> validateAsync() => state.validateAsync();')
      ..writeln('  ${metadata.className} build() => state.build();')
      ..writeln(
          '  Future<${metadata.className}> buildAsync() => state.buildAsync();')
      ..writeln(
          '  void applyRestError(RestHttpException error) => state.applyRestError(error);')
      ..writeln()
      ..writeln('  void Function(TValue) bindComposite<TValue>(')
      ..writeln('    Map<String, Object?> Function(TValue value) mapper,')
      ..writeln('  ) => state.bindComposite(mapper);')
      ..writeln()
      ..writeln('  static FormState<${metadata.className}> _createState(');

    for (final ({
      FieldElement field,
      String? label,
      int order,
      FormInput input,
      List<({String name, ConstantReader annotation})> validators
    }) item in metadata.fields) {
      output.writeln(
        '    ${nullableType(item.field.type)} initial${_pascal(item.field.displayName)},',
      );
    }

    output
      ..writeln('    List<FormValidator<${metadata.className}>> validators,')
      ..writeln(
          '    List<AsyncFormValidator<${metadata.className}>> asyncValidators,')
      ..writeln('    Duration? asyncValidationDebounce,')
      ..writeln('    FormValidationMode validationMode,')
      ..writeln('  ) {')
      ..writeln('    final fields = <String, FormFieldState<Object?>>{');

    for (final ({
      FieldElement field,
      String? label,
      int order,
      FormInput input,
      List<({String name, ConstantReader annotation})> validators
    }) item in metadata.fields) {
      final String type = item.field.type.toString();
      output
        ..writeln("      '${item.field.displayName}': FormFieldState<$type>(")
        ..writeln(
            '        initialValue: initial${_pascal(item.field.displayName)},')
        ..writeln(_writeParser(item.input, item.field.type, item.field))
        ..writeln('        validators: <FormValidator<$type>>[');
      for (final ({String name, ConstantReader annotation}) validator
          in item.validators) {
        output.writeln(
          _writeValidator(validator.name, validator.annotation, type),
        );
      }
      output
        ..writeln('        ],')
        ..writeln('      ),');
    }

    output
      ..writeln('    };')
      ..writeln('    final form = FormState<${metadata.className}>(')
      ..writeln('      fields: fields,')
      ..writeln('      validators: validators,')
      ..writeln('      asyncValidators: asyncValidators,')
      ..writeln('      asyncValidationDebounce: asyncValidationDebounce,')
      ..writeln('      builder: () => ${metadata.className}(');

    for (final ({
      FieldElement field,
      String? label,
      int order,
      FormInput input,
      List<({String name, ConstantReader annotation})> validators
    }) item in metadata.fields) {
      final String type = item.field.type.toString();
      output.writeln(
        '        ${item.field.displayName}: fields[\'${item.field.displayName}\']!.value as $type,',
      );
    }

    output
      ..writeln('      ),')
      ..writeln('      validationMode: validationMode,')
      ..writeln('    );')
      ..writeln('    return form;')
      ..writeln('  }')
      ..writeln('}')
      ..writeln();

    return output.toString();
  }

  String _writeValidator(String name, ConstantReader annotation, String type) {
    switch (name) {
      case 'Required':
        return "          (value) => value == null || value.toString().trim().isEmpty ? FormError(code: '${_readString(annotation, 'code', 'required')}', message: '${_readString(annotation, 'message', 'Este campo es obligatorio')}') : null,";
      case 'Email':
        return "          (value) => value is String && !RegExp(r'^[^@\\s]+@[^@\\s]+\\.[^@\\s]+\$').hasMatch(value) ? FormError(code: '${_readString(annotation, 'code', 'email.invalid')}', message: '${_readString(annotation, 'message', 'El correo electrónico no es válido')}') : null,";
      case 'Length':
        final int? min = _readNullableInt(annotation, 'min');
        final int? max = _readNullableInt(annotation, 'max');
        return "          (value) => value is String && ${_lengthCondition(min, max)} ? FormError(code: '${_readString(annotation, 'code', 'length.invalid')}', message: '${_readString(annotation, 'message', 'La longitud no es válida')}') : null,";
      case 'Pattern':
        final String expression = _readString(annotation, 'expression', '.*');
        return "          (value) => value is String && !RegExp('$expression').hasMatch(value) ? FormError(code: '${_readString(annotation, 'code', 'pattern.invalid')}', message: '${_readString(annotation, 'message', 'El formato no es válido')}') : null,";
      case 'Uuid':
        final UuidVersion? version = _readUuidVersion(annotation);
        return "          (value) => value is String && !RegExp('${_escape(uuidPattern(version))}').hasMatch(value) ? FormError(code: '${_readString(annotation, 'code', 'uuid.invalid')}', message: '${_readString(annotation, 'message', 'El UUID no es válido')}') : null,";
      case 'Range':
        final num? min = _readNullableNum(annotation, 'min');
        final num? max = _readNullableNum(annotation, 'max');
        return "          (value) => value is num && ${_rangeCondition(min, max)} ? FormError(code: '${_readString(annotation, 'code', 'range.invalid')}', message: '${_readString(annotation, 'message', 'El valor está fuera de rango')}') : null,";
      default:
        throw StateError('Unsupported form validator: $name for $type');
    }
  }

  String _writeParser(FormInput input, DartType fieldType, FieldElement field) {
    final String type = fieldType.toString();
    final String baseType = type.replaceAll('?', '');
    final String nullValue = type.endsWith('?')
        ? 'raw == null ? null : '
        : "raw == null ? throw FormatException('Null value is not valid') : ";

    if (fieldType is InterfaceType && fieldType.element is EnumElement) {
      return '        parser: FormValueParser<$type>(parse: (raw) => '
          '$nullValue raw is $baseType ? raw : '
          "${baseType}.values.firstWhere((candidate) => "
          "candidate.name == raw.toString(), "
          "orElse: () => throw FormatException('Invalid $baseType'))),";
    }

    final List<({String kind, String? pattern})> formats = _readFormats(field);
    if (baseType == 'String' && formats.isNotEmpty) {
      return _writeStringFormatParser(type, nullValue, formats);
    }

    switch (input) {
      case FormInput.number:
        if (baseType == 'double') {
          return '        parser: FormValueParser<$type>(parse: (raw) => '
              '$nullValue raw is num ? raw.toDouble() : '
              'double.parse(raw.toString())),';
        }
        if (baseType == 'num') {
          return '        parser: FormValueParser<$type>(parse: (raw) => '
              '$nullValue raw is num ? raw : '
              'num.parse(raw.toString())),';
        }
        if (baseType == 'int') {
          return '        parser: FormValueParser<$type>(parse: (raw) => '
              '$nullValue raw is num ? raw.toInt() : '
              'int.parse(raw.toString())),';
        }
        return _writeIdentityParser(type, baseType);
      case FormInput.boolean:
        if (baseType != 'bool') return _writeIdentityParser(type, baseType);
        return '        parser: FormValueParser<$type>(parse: (raw) => '
            '$nullValue raw is bool ? raw : '
            'switch (raw.toString().toLowerCase()) '
            "{ 'true' => true, 'false' => false, _ => throw FormatException('Invalid boolean') }),";
      case FormInput.date:
        if (baseType != 'DateTime') return _writeIdentityParser(type, baseType);
        ({String kind, String? pattern})? dateFormat;
        for (final format in formats) {
          if (format.kind == 'date') {
            dateFormat = format;
            break;
          }
        }
        if (dateFormat != null && dateFormat.pattern != null) {
          return '        parser: FormValueParser<$type>(parse: (raw) => '
              '$nullValue Serializer.parseDate(raw.toString(), '
              "'${_escape(dateFormat.pattern!)}')),";
        }
        return '        parser: FormValueParser<$type>(parse: (raw) => '
            '$nullValue raw is DateTime ? raw : '
            'DateTime.parse(raw.toString())),';
      case FormInput.text:
      case FormInput.password:
      case FormInput.email:
        return '';
    }
  }

  String _writeStringFormatParser(
    String type,
    String nullValue,
    List<({String kind, String? pattern})> formats,
  ) {
    String expression = 'raw.toString()';
    for (final ({String kind, String? pattern}) format in formats) {
      switch (format.kind) {
        case 'trim':
          expression = '$expression.trim()';
        case 'uppercase':
          expression = '$expression.toUpperCase()';
        case 'lowercase':
          expression = '$expression.toLowerCase()';
        case 'custom':
          if (format.pattern != null && format.pattern!.isNotEmpty) {
            expression = '${format.pattern}FormatFromJson($expression)';
          }
      }
    }
    return '        parser: FormValueParser<$type>(parse: (raw) => '
        '$nullValue $expression),';
  }

  List<({String kind, String? pattern})> _readFormats(FieldElement field) {
    final List<({String kind, String? pattern})> formats =
        <({String kind, String? pattern})>[];
    for (final ElementAnnotation metadata in field.metadata.annotations) {
      final Element? annotationElement = metadata.element;
      final Uri? libraryUri = annotationElement?.library?.uri;
      final bool isFormat = annotationElement?.displayName == 'Format' ||
          annotationElement?.enclosingElement?.displayName == 'Format';
      if (!isFormat ||
          libraryUri?.scheme != 'package' ||
          libraryUri!.pathSegments.isEmpty ||
          libraryUri.pathSegments.first != 'd_rocket') {
        continue;
      }
      final ConstantReader reader =
          ConstantReader(metadata.computeConstantValue());
      final ConstantReader kindReader = reader.read('kind');
      if (!kindReader.isString || kindReader.stringValue.isEmpty) continue;
      final ConstantReader patternReader = reader.read('pattern');
      formats.add((
        kind: kindReader.stringValue,
        pattern: patternReader.isString ? patternReader.stringValue : null,
      ));
    }
    return formats;
  }

  String _writeIdentityParser(String type, String baseType) {
    final String nullValue = type.endsWith('?')
        ? 'raw == null ? null : '
        : "raw == null ? throw FormatException('Null value is not valid') : ";
    return '        parser: FormValueParser<$type>(parse: (raw) => '
        '$nullValue raw is $baseType ? raw : '
        "throw FormatException('Unsupported raw value for $baseType')),";
  }

  String _lengthCondition(int? min, int? max) {
    final List<String> conditions = <String>[];
    if (min != null) conditions.add('value.length < $min');
    if (max != null) conditions.add('value.length > $max');
    return conditions.isEmpty ? 'false' : '(${conditions.join(' || ')})';
  }

  String _rangeCondition(num? min, num? max) {
    final List<String> conditions = <String>[];
    if (min != null) conditions.add('(value as num) < $min');
    if (max != null) conditions.add('(value as num) > $max');
    return conditions.isEmpty ? 'false' : '(${conditions.join(' || ')})';
  }

  String _readString(ConstantReader reader, String name, String fallback) {
    final ConstantReader value = reader.read(name);
    return value.isString ? _escape(value.stringValue) : fallback;
  }

  int? _readNullableInt(ConstantReader reader, String name) {
    final ConstantReader value = reader.read(name);
    return value.isInt ? value.intValue : null;
  }

  UuidVersion? _readUuidVersion(ConstantReader reader) {
    final ConstantReader value = reader.read('version');
    if (value.isNull) return null;
    final String accessor = value.revive().accessor;
    for (final UuidVersion candidate in UuidVersion.values) {
      if (accessor == candidate.name ||
          accessor.endsWith('.${candidate.name}')) {
        return candidate;
      }
    }
    return null;
  }

  num? _readNullableNum(ConstantReader reader, String name) {
    final ConstantReader value = reader.read(name);
    if (value.isInt) return value.intValue;
    if (value.isDouble) return value.doubleValue;
    return null;
  }

  String _escape(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n');

  String _nullableString(String? value) =>
      value == null ? 'null' : "'${_escape(value)}'";

  String _pascal(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}
