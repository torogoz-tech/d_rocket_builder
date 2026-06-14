/// .f — `d_rocket_n_plus_one`:
///
/// A `custom_lint` rule that fires when a
/// `NavigationRegistry.get<T>(...)` call appears
/// inside a `for` / `forEach` loop body. This is
/// the classic N+1 query pattern: the framework
/// re-fetches the navigation for every loop
/// iteration instead of batching.
///
/// **Fix**: load the entity list with
/// `.include_<T>(name, targetMeta)` first, then
/// the navigation is already populated when the
/// loop body runs.
///
/// **Example** (linted):
/// ```dart
/// for (final order in orders) {
///   print(order.customer.name);  // ← lint fires
/// }
/// ```
///
/// **Fix**:
/// ```dart
/// final orders = await db.set<Order>()
///     .include_<Customer>()
///     .toListWithIncludesAsync_();
/// for (final order in orders) {
///   print(order.customer.name);  // ✅ no lint
/// }
/// ```
library d_rocket_builder.lints.n_plus_one_lint;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// .f: detects `NavigationRegistry.get<...>(...)`
/// inside a `for` / `forEach` loop body. The classic
/// N+1 query pattern.
class NPlusOneLint extends LintRule {
  NPlusOneLint() : super(code: _code);

  static final LintCode _code = LintCode(
    name: 'd_rocket_n_plus_one',
    problemMessage: 'Navigation access inside a loop can cause N+1 queries. '
        'Use .include_<T>() first to batch the fetch.',
    correctionMessage:
        "Add .include_<TargetEntity>() "
        'before the loop, then call .toListWithIncludesAsync_() instead '
        'of .toListAsync_().',
  );

  @override
  List<String> get filesToAnalyze => const <String>['**/*.dart'];

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    // Walk the unit looking for `for`/`forEach` loops
    // whose body contains a `NavigationRegistry.get(...)`
    // call.
    final _NPlusOneVisitor visitor = _NPlusOneVisitor(reporter, _code);
    resolver.source.contents.data; // ensure source is loaded
    context.registry.addForStatement((node) {
      node.accept(visitor);
    });
    context.registry.addForEachParts((node) {
      node.accept(visitor);
    });
  }
}

class _NPlusOneVisitor extends RecursiveAstVisitor<void> {
  _NPlusOneVisitor(this.reporter, this.code);

  final DiagnosticReporter reporter;
  final LintCode code;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Detect `NavigationRegistry.get<T>(...)` calls.
    final target = node.target;
    if (target is SimpleIdentifier &&
        target.name == 'NavigationRegistry' &&
        node.methodName.name == 'get') {
      reporter.atNode(node, code);
    }
    super.visitMethodInvocation(node);
  }
}
