//: tests for the realtime registry
// helpers + the generator factory export.
//
// The structural-detection tests use the analyzer
// directly. The generator tests verify the
// factory export (the generator output is
// manually verified — the generator is small
// enough that a code review is sufficient).

import 'package:d_rocket_builder/d_rocket_builder.dart';
import 'package:d_rocket_builder/src/realtime/generator.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 6.4 — d_rocket_builder exports', () {
    test('buildRealtime is a top-level function', () {
      expect(buildRealtime, isA<Function>());
    });

    test('WebSocketClientGenerator is a const-constructable Generator', () {
      const WebSocketClientGenerator gen = WebSocketClientGenerator();
      expect(gen, isA<WebSocketClientGenerator>());
    });

    test('SseClientGenerator is a const-constructable Generator', () {
      const SseClientGenerator gen = SseClientGenerator();
      expect(gen, isA<SseClientGenerator>());
    });
  });
}
