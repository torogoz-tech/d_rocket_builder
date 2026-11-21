import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('generic serializer templates interpolate field and type names', () {
    final String source =
        File('lib/src/serializer/generator.dart').readAsStringSync();

    expect(source, isNot(contains(r'encode\$typeParamName')));
    expect(source, isNot(contains(r'decode\$typeParamName')));
    expect(source, isNot(contains(r"json['\$jsonKey']")));
    expect(source, contains('genericToJsonEntries'));
    expect(source, contains('final String genericToJsonBody'));
    expect(source, contains('T Function(Object?) decode'));
    expect(source, contains('Object? Function(T) encode'));
    expect(
      source,
      isNot(contains(
        r"decode$typeParamName(json['$jsonKey'] as Map<String, dynamic>)",
      )),
    );
    expect(
      source,
      isNot(contains(r'decode$typeParamName($expr as Map<String, dynamic>)')),
    );
  });

  test('default collection literals preserve the declared field type', () {
    final String source =
        File('lib/src/serializer/generator.dart').readAsStringSync();

    expect(source, contains('_readDefaultValueCode(jsonKeyAnnotation, type)'));
    expect(source, contains('_literalToCode(value.literalValue, fieldType)'));
    expect(source, contains('typeArguments.first'));
  });
}
