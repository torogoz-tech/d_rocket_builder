import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:test/test.dart';
import 'package:d_rocket_builder/d_rocket_builder.dart';

void main() {
  group('Fase 9.9.f — NPlusOneLint', () {
    test('NPlusOneLint is a LintRule', () {
      final rule = NPlusOneLint();
      expect(rule, isA<LintRule>());
    });

    test('LintCode is named d_rocket_n_plus_one', () {
      final rule = NPlusOneLint();
      expect(rule.code.name, 'd_rocket_n_plus_one');
    });

    test('correctionMessage mentions include_<T>', () {
      final rule = NPlusOneLint();
      expect(rule.code.correctionMessage, contains('include_<'));
    });

    test('filesToAnalyze matches all .dart files', () {
      final rule = NPlusOneLint();
      expect(rule.filesToAnalyze, contains('**/*.dart'));
    });
  });
}
