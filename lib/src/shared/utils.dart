// String-case conversion utilities used by the serializer codegen.
//
// These helpers were originally in `d_builder/lib/src/shared/utils.dart`.
// They are intentionally pure functions of the input string with no
// dependency on the analyzer so that they can be tested in isolation.

/// Convert any input to `snake_case`.
///
/// - `HelloWorld` → `hello_world`
/// - `helloWorld` → `hello_world`
/// - `hello_world` → `hello_world`
/// - `HTTPClient` → `h_t_t_p_client` (intentional, see edge case below)
///
/// The naive "lowercase + insert `_` before every uppercase" approach
/// is sufficient for the emitter's filename derivation. If you ever
/// need smarter behaviour (treating `IOError` as one word), this
/// helper is the single place to change.
String toSnakeCase(String input) {
  final chars = input.split('');
  final result = <String>[];
  for (var i = 0; i < chars.length; i++) {
    final c = chars[i];
    if (c == c.toUpperCase() && c != c.toLowerCase()) {
      if (i > 0) result.add('_');
      result.add(c.toLowerCase());
    } else {
      result.add(c);
    }
  }
  return result.join();
}

/// Capitalize the first letter of [s] and lowercase the rest. Used by
/// `toCamelCase` and `toPascalCase` to normalise each "word" after
/// splitting on `_` / `-`.
String _capWord(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1).toLowerCase();
}

/// Split a string into words on the standard separators. Used by
/// the camelCase and PascalCase converters. CamelCase boundaries
/// (lower→upper transitions) are also treated as separators so that
/// `userProfile` becomes `['user', 'Profile']` rather than
/// `['userProfile']`.
List<String> _splitWords(String input) {
  if (input.isEmpty) return <String>[];
  // Insert a separator between any lower→upper, upper→upper-lower, or
  // digit→letter boundary, then split on `_` / `-`.
  final StringBuffer buf = StringBuffer();
  for (int i = 0; i < input.length; i++) {
    final String c = input[i];
    final bool prevIsLower = i > 0 &&
        input[i - 1] != input[i - 1].toUpperCase() &&
        input[i - 1] != '_' &&
        input[i - 1] != '-';
    final bool currIsUpper = c == c.toUpperCase() && c != c.toLowerCase();
    if (i > 0 && currIsUpper && prevIsLower) {
      buf.write(' ');
    }
    if (i > 0 && c == c.toLowerCase() && c != c.toUpperCase()) {
      final bool prevIsUpper = i > 0 &&
          input[i - 1] == input[i - 1].toUpperCase() &&
          input[i - 1] != input[i - 1].toLowerCase();
      // Only insert if the previous upper is not part of a known
      // acronym (heuristic: preceded by two consecutive upper).
      if (prevIsUpper && i >= 2) {
        final bool prevPrevIsUpper = input[i - 2] == input[i - 2].toUpperCase() &&
            input[i - 2] != input[i - 2].toLowerCase();
        if (prevPrevIsUpper) {
          buf.write(' ');
        }
      }
    }
    buf.write(c);
  }
  return buf
      .toString()
      .split(RegExp(r'[_\-\s]+'))
      .where((String w) => w.isNotEmpty)
      .toList();
}

/// Convert any input to `camelCase`.
///
/// - `user_profile` → `userProfile`
/// - `UserProfile`  → `userProfile`
/// - `userProfile`  → `userProfile` (idempotent)
/// - `user-profile` → `userProfile`
String toCamelCase(String input) {
  final List<String> words = _splitWords(input);
  if (words.isEmpty) return '';
  final StringBuffer out = StringBuffer(words.first.toLowerCase());
  for (int i = 1; i < words.length; i++) {
    out.write(_capWord(words[i]));
  }
  return out.toString();
}

/// Convert any input to `kebab-case`.
///
/// - `userProfile`  → `user-profile`
/// - `user_profile` → `user-profile`
/// - `UserProfile`  → `user-profile`
String toKebabCase(String input) {
  return toSnakeCase(input).replaceAll('_', '-');
}

/// Convert any input to `PascalCase`.
///
/// - `user_profile` → `UserProfile`
/// - `userProfile`  → `UserProfile`
/// - `UserProfile`  → `UserProfile` (idempotent)
/// - `user-profile` → `UserProfile`
String toPascalCase(String input) {
  final List<String> words = _splitWords(input);
  if (words.isEmpty) return '';
  final StringBuffer out = StringBuffer();
  for (final String w in words) {
    out.write(_capWord(w));
  }
  return out.toString();
}

/// Returns the JSON key for [fieldName] according to the chosen
/// [naming] strategy. This is the single source of truth used by
/// `SerializableGenerator` so that the strategy behaviour is
/// unit-testable without invoking the analyzer.
String jsonKeyFor(String fieldName, String naming) {
  switch (naming) {
    case 'snakeCase':
      return toSnakeCase(fieldName);
    case 'camelCase':
      return toCamelCase(fieldName);
    case 'kebabCase':
      return toKebabCase(fieldName);
    case 'pascalCase':
      return toPascalCase(fieldName);
    case 'none':
    default:
      return fieldName;
  }
}
