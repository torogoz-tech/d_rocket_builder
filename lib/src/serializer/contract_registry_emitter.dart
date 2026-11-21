import 'contract_type.dart';

/// Emits concrete calls to generated generic serializer registration helpers.
class ContractRegistryEmitter {
  const ContractRegistryEmitter._();

  /// Emits registration statements for [types] using generated file aliases.
  static String emit(
    Iterable<ContractType> types, {
    required Map<String, int> importIndexes,
  }) {
    final StringBuffer output = StringBuffer();
    for (final ContractType type in types) {
      if (!type.isGenericInstance || type.typeArguments.length != 1) {
        continue;
      }
      final int? importIndex = importIndexes[type.libraryPath];
      if (importIndex == null) continue;
      final ContractType argument = type.typeArguments.single;
      final String argumentName = _typeName(argument, importIndexes);
      output
        ..writeln(
          '  _m$importIndex.register${type.className}Serializer<$argumentName>(',
        )
        ..writeln(
          '    decode: (Object? value) => ${_decodeWithImports(argument, 'value', importIndexes)},',
        )
        ..writeln('    encode: Serializer.encodeDynamic,')
        ..writeln('  );');
    }
    return output.toString();
  }

  static String _decodeWithImports(
    ContractType type,
    String expression,
    Map<String, int> importIndexes,
  ) {
    if (type.className == 'List' && type.typeArguments.length == 1) {
      final ContractType item = type.typeArguments.single;
      return '(($expression as List<dynamic>)'
          '.map((item) => ${_decodeWithImports(item, 'item', importIndexes)}).toList())';
    }
    if (type.className == 'Set' && type.typeArguments.length == 1) {
      final ContractType item = type.typeArguments.single;
      return '(($expression as List<dynamic>)'
          '.map((item) => ${_decodeWithImports(item, 'item', importIndexes)}).toSet())';
    }
    if (type.className == 'Map' && type.typeArguments.length == 2) {
      return 'Serializer.fromDynamic<${_typeName(type, importIndexes)}>($expression)';
    }
    return 'Serializer.fromDynamic<${_typeName(type, importIndexes)}>($expression)';
  }

  static String _typeName(
    ContractType type,
    Map<String, int> importIndexes,
  ) {
    final int? importIndex = importIndexes[type.libraryPath];
    final String prefix = importIndex == null ? '' : '_m$importIndex.';
    final String arguments = type.typeArguments.isEmpty
        ? ''
        : '<${type.typeArguments.map((ContractType item) => _typeName(item, importIndexes)).join(', ')}>';
    return '$prefix${type.className}$arguments${type.isNullable ? '?' : ''}';
  }
}
