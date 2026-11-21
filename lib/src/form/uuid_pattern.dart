import 'package:d_rocket/d_rocket.dart';

/// Builds the canonical UUID regular expression for a version policy.
String uuidPattern([UuidVersion? version]) {
  final String versionPattern =
      version == null ? '[1-8]' : '${version.index + 1}';
  return '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-'
      '$versionPattern[0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-'
      '[0-9a-fA-F]{12}\$';
}
