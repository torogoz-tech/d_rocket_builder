import 'package:d_rocket/d_rocket.dart';
import 'package:d_rocket_builder/src/form/uuid_pattern.dart';
import 'package:test/test.dart';

void main() {
  test('general UUID pattern accepts every supported version', () {
    final RegExp pattern = RegExp(uuidPattern());

    for (int version = 1; version <= 8; version++) {
      expect(
        pattern.hasMatch('123e4567-e89b-${version}456-a456-426614174000'),
        isTrue,
        reason: 'UUID v$version should be accepted',
      );
    }
  });

  test('version-specific UUID pattern restricts the version nibble', () {
    final RegExp pattern = RegExp(uuidPattern(UuidVersion.v4));

    expect(pattern.hasMatch('123e4567-e89b-4456-a456-426614174000'), isTrue);
    expect(pattern.hasMatch('123e4567-e89b-7456-a456-426614174000'), isFalse);
  });

  test('UUID pattern validates canonical shape and variant', () {
    final RegExp pattern = RegExp(uuidPattern());

    expect(pattern.hasMatch('123e4567-e89b-4456-c456-426614174000'), isFalse);
    expect(pattern.hasMatch('123e4567e89b4456a456426614174000'), isFalse);
    expect(pattern.hasMatch('123e4567-e89b-9456-a456-426614174000'), isFalse);
    expect(pattern.hasMatch('123e4567-e89b-4456-a456-42661417400z'), isFalse);
  });
}
