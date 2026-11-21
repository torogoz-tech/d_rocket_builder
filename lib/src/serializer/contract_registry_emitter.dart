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
      output
        ..writeln(
          '  _m$importIndex.register${type.className}Serializer<${argument.displayName}>(',
        )
        ..writeln(
          '    decode: (Object? value) => ${_decode(argument, 'value')},',
        )
        ..writeln('    encode: Serializer.encodeDynamic,')
        ..writeln('  );');
    }
    return output.toString();
  }

  static String _decode(ContractType type, String expression) {
    if (type.className == 'List' && type.typeArguments.length == 1) {
      final ContractType item = type.typeArguments.single;
      return '(($expression as List<dynamic>)'
          '.map((item) => ${_decode(item, 'item')}).toList())';
    }
    if (type.className == 'Set' && type.typeArguments.length == 1) {
      final ContractType item = type.typeArguments.single;
      return '(($expression as List<dynamic>)'
          '.map((item) => ${_decode(item, 'item')}).toSet())';
    }
    if (type.className == 'Map' && type.typeArguments.length == 2) {
      return 'Serializer.fromDynamic<${type.displayName}>($expression)';
    }
    return 'Serializer.fromDynamic<${type.displayName}>($expression)';
  }
}
