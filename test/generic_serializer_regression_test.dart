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
  });
}
