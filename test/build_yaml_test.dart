// Smoke test that verifies the `d_rocket_builder` `build.yaml` is
// well-formed and declares the four builders expected by the
// d_rocket consumer:
//
//   1. `d_rocket_builder:record`            — PartBuilder, `.g.dart`
//   2. `d_rocket_builder:serializer`        — PartBuilder, `.d_rocket_serializer.g.dart`
//   3. `d_rocket_builder:rest_client`       — PartBuilder, `.d_rocket_rest_client.g.dart`
//   4. `d_rocket_builder:record_registry`   — LibraryBuilder, `d_rocket_registry.g.dart`
//
// We do NOT invoke `build_runner` here (that would require a
// `package:build_config` dependency and a full project to build
// against). Instead we read the `build.yaml` as a text file and
// assert on the relevant substrings. This catches accidental
// regressions like the HANDOFF.md §6 bug (collision between
// `d_rocket_builder:serializer` and `source_gen:combining_builder`)
// at the unit-test level.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  final File buildYaml = File('build.yaml').absolute;

  setUpAll(() {
    if (!buildYaml.existsSync()) {
      fail('Expected build.yaml at ${buildYaml.path}, but it does not exist.');
    }
  });

  group('d_rocket_builder/build.yaml', () {
    test('declares all four builders', () {
      final String content = buildYaml.readAsStringSync();
      expect(content, contains('d_rocket_builder:record:'));
      expect(content, contains('d_rocket_builder:serializer:'));
      expect(content, contains('d_rocket_builder:rest_client:'));
      expect(content, contains('d_rocket_builder:record_registry:'));
    });

    test('record builder uses the default .g.dart suffix', () {
      final String content = buildYaml.readAsStringSync();
      final String block = _extractBlock(content, 'record');
      expect(block, contains('".dart": [".g.dart"]'),
          reason: 'record builder must use the default .g.dart suffix');
    });

    test('serializer builder uses the non-default '
        '.d_rocket_serializer.g.dart suffix (HANDOFF §6 fix)', () {
      final String content = buildYaml.readAsStringSync();
      final String block = _extractBlock(content, 'serializer');
      expect(block, contains('.d_rocket_serializer.g.dart'),
          reason: 'serializer builder must use the non-default suffix');
      expect(
        block,
        isNot(contains('".dart": [".g.dart"]')),
        reason: 'serializer must NOT use the default .g.dart suffix',
      );
    });

    test('rest_client builder uses the non-default '
        '.d_rocket_rest_client.g.dart suffix (HANDOFF §6 fix)', () {
      final String content = buildYaml.readAsStringSync();
      final String block = _extractBlock(content, 'rest_client');
      expect(block, contains('.d_rocket_rest_client.g.dart'),
          reason: 'rest_client builder must use the non-default suffix');
      expect(
        block,
        isNot(contains('".dart": [".g.dart"]')),
        reason: 'rest_client must NOT use the default .g.dart suffix',
      );
    });

    test('record_registry writes to d_rocket_registry.g.dart', () {
      final String content = buildYaml.readAsStringSync();
      final String block = _extractBlock(content, 'record_registry');
      expect(block, contains('d_rocket_registry.g.dart'));
    });
  });
}

/// Extracts the YAML block starting at the `:<name>:` declaration
/// of the builder (e.g. `d_rocket_builder:record:`) and ending
/// at the next top-level `d_rocket_builder:*:` declaration (or
/// the end of the file). This is enough for substring-based
/// assertions.
String _extractBlock(String content, String builderShortName) {
  final int startIdx = content.indexOf('d_rocket_builder:$builderShortName:');
  if (startIdx < 0) {
    fail('builder block `d_rocket_builder:$builderShortName:` not found');
  }
  // Find the next top-level `d_rocket_builder:*:` declaration
  // after the start of this block.
  final RegExp nextBlock =
      RegExp(r'\n  d_rocket_builder:[\w_]+:', multiLine: true);
  int endIdx = content.length;
  for (final RegExpMatch m in nextBlock.allMatches(content, startIdx + 1)) {
    endIdx = m.start;
    break;
  }
  return content.substring(startIdx, endIdx);
}
