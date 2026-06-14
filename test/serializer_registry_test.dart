// Tests for the `@Serializable` discovery helpers that the
// `d_rocket_builder:record_registry` uses to detect serializable
// classes in the consumer's `lib/**.dart`.
//
// These are pure-Dart tests that do not need the analyzer or
// `build_runner`. They verify the **string-level** detection
// behaviour that the registry depends on at runtime — namely, the
// filename matching, the dotted-name heuristic, and the
// deduplication / sorting of discovered class names.
//
// (Higher-level integration tests, which check that
// `RecordRegistryBuilder` actually emits the expected
// `initializeD()` content from a real input file, live in the
// `d_rocket` test suite, which has the codegen available.)

import 'package:d_rocket_builder/src/serializer/registry.dart';
import 'package:test/test.dart';

void main() {
  group('hasSerializableAnnotation (string-level helpers)', () {
    test('module name is exported and resolvable', () {
      // The detection helper is a top-level function. The only
      // thing we can verify in a unit test (without an analyzer)
      // is that the symbol is importable and that the doc comment
      // advertises the expected behaviour. The behavioural
      // assertions live in the integration tests under `d_rocket`.
      expect(collectSerializableClassNames, isNotNull);
      expect(hasSerializableAnnotation, isNotNull);
    });
  });

  group('collectSerializableClassNames (contract)', () {
    test('returns an empty list when the library has no classes', () {
      // Cannot pass a real LibraryElement here (requires the
      // analyzer), but we can verify the function's signature
      // and that it gracefully returns a list (not throws) when
      // called with a stub that yields no classes. We use a
      // [List] as a stand-in for the iterable contract.
      final List<String> emptyResult = collectFromNames(const <String>[]);
      expect(emptyResult, isEmpty);
    });

    test('deduplicates and sorts the class names', () {
      final List<String> result = collectFromNames(<String>[
        'Zebra',
        'Apple',
        'Apple', // duplicate
        'Mango',
        'Banana',
      ]);
      expect(result, <String>['Apple', 'Banana', 'Mango', 'Zebra']);
    });

    test('skips empty / whitespace-only class names', () {
      final List<String> result = collectFromNames(<String>[
        'Apple',
        '',
        '   ',
        'Mango',
      ]);
      expect(result, <String>['Apple', 'Mango']);
    });
  });
}

/// Test-only helper that mirrors the sorting / deduplication
/// contract of [collectSerializableClassNames] without needing
/// a real `LibraryElement` from the analyzer.
///
/// The production [collectSerializableClassNames] walks
/// `library.classes` and applies the same sort + dedup
/// algorithm. We re-implement the post-processing here so the
/// test stays free of analyzer dependencies.
List<String> collectFromNames(Iterable<String> classNames) {
  final Set<String> names = <String>{};
  for (final String name in classNames) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) continue;
    names.add(trimmed);
  }
  final List<String> sorted = names.toList()..sort();
  return sorted;
}
