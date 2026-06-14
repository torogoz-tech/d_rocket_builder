import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:test/test.dart';
import 'package:d_rocket_builder/d_rocket_builder.dart';

void main() {
  group('Fase 9.8.i — LinqClosureFix', () {
    test('LinqClosureFix is a DartFix', () {
      final fix = LinqClosureFix();
      expect(fix, isA<DartFix>());
    });

    test('LinqClosureFix matches all .dart files', () {
      final fix = LinqClosureFix();
      expect(fix.filesToAnalyze, contains('**.dart'));
    });
  });
}
