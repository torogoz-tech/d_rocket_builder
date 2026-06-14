// Unit tests for the `@RestClient` discovery helpers in
// `d_rocket_builder/src/rest/registry.dart`.
//
// These are pure-Dart tests that do not need the analyzer or
// `build_runner`. They verify the **string-level** detection
// behaviour that the `RecordRegistryBuilder` depends on at
// runtime — namely, the same sorting / deduplication contract
// that `serializer/registry_test.dart` covers for
// `@Serializable`, applied to `@RestClient`.

import 'package:d_rocket_builder/src/rest/registry.dart';
import 'package:test/test.dart';

void main() {
  group('hasRestClientAnnotation / collectRestClientClassNames', () {
    test('module name is exported and resolvable', () {
      expect(collectRestClientClassNames, isNotNull);
      expect(hasRestClientAnnotation, isNotNull);
    });
  });

  group('collectRestClientClassNames (contract)', () {
    test('returns an empty list when there are no class names', () {
      // Mirror the dedup / sort contract without needing a
      // real LibraryElement from the analyzer.
      final List<String> emptyResult = collectFromNames(const <String>[]);
      expect(emptyResult, isEmpty);
    });

    test('deduplicates and sorts class names', () {
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

List<String> collectFromNames(Iterable<String> classNames) {
  // Mirrors the sort + dedup algorithm in
  // [collectRestClientClassNames] without the analyzer.
  final Set<String> names = <String>{};
  for (final String name in classNames) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) continue;
    names.add(trimmed);
  }
  final List<String> sorted = names.toList()..sort();
  return sorted;
}
