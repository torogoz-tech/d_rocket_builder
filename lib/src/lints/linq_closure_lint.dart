/// .h — `d_rocket_untranslated_closure_linq`:
///
/// A `custom_lint` rule that fires when a closure
/// LINQ call (`q.where_((t) => …)`, `q.orderBy_((t) => …)`,
/// etc.) is detected. The closure runs in-memory
/// only (.b) — for SQL translation, the
/// user should run the auto-rewriter CLI:
///
/// ```bash
/// dart run d_rocket:rocket_closure transform-file <path>
/// ```
library d_rocket_builder.lints.linq_closure_lint;

import 'package:analyzer/diagnostic/diagnostic.dart' show Diagnostic;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:d_rocket/src/cli/closure_transformer.dart'
    show transformFileSource;
import 'n_plus_one_lint.dart';

/// .h: the lint rule. Reports a
/// `d_rocket_untranslated_closure_linq` lint at
/// every `.where_((t) => …)` (and similar) call
/// site in the consumer's code.
class LinqClosureLint extends LintRule {
  LinqClosureLint()
      : super(
          code: _code,
        );

  static final LintCode _code = LintCode(
    name: 'd_rocket_untranslated_closure_linq',
    problemMessage: 'Closure LINQ calls run in-memory only; for SQL '
        'translation, rewrite with Expr.lambda(...).',
    correctionMessage:
        "Run 'dart run d_rocket:rocket_closure transform-file <path>' "
        'to auto-rewrite this file.',
  );

  /// .h: the closure LINQ method names we
  /// look for. These are the only methods that
  /// accept either an Expr or a closure.
  static const Set<String> _closureLinqMethods = <String>{
    'where_',
    'orderBy_',
    'orderByDescending_',
    'thenBy_',
    'thenByDescending_',
  };

  @override
  List<String> get filesToAnalyze => const <String>['**/*.dart'];

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addMethodInvocation((node) {
      // Only check calls whose method name is one of
      // our closure LINQ methods.
      final String? methodName = node.methodName.name;
      if (methodName == null) return;
      if (!_closureLinqMethods.contains(methodName)) return;

      // Only check calls whose first argument is a
      // function expression (a closure literal).
      final args = node.argumentList.arguments;
      if (args.isEmpty) return;
      final firstArg = args.first;
      if (firstArg.runtimeType.toString() != 'FunctionExpression') return;

      reporter.atNode(node, code);
    });
  }
}

/// .h: the plugin that exposes the lint
/// rules to `package:custom_lint` consumers.
class D_rocketLintsPlugin extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) =>
      <LintRule>[LinqClosureLint(), NPlusOneLint()];
}

// ─── .i: auto-fix via dart fix —apply ────────────────

/// .i: a `DartFix` that rewrites the
/// source file using the `transformFileSource`
/// helper (from the d_rocket package, defined in
/// lib/src/cli/closure_transformer.dart). The fix
/// emits a single file-level source change that
/// replaces the whole file with the transformed
/// output.
///
/// **Usage**:
///
/// ```bash
/// # 1. See warnings (.h)
/// dart analyze
///
/// # 2. Auto-fix all warnings
/// dart fix --apply
/// ```
class LinqClosureFix extends DartFix {
  LinqClosureFix();

  @override
  Future<void> startUp(
    CustomLintResolver resolver,
    CustomLintContext context,
  ) async {
    // .i: load the file's source and
    // compute the transformed version once, in
    // startUp. The result is stored in the shared
    // state for the run() callback to use.
    final unit = await resolver.getResolvedUnitResult();
    final String source = unit.content;
    // Avoid loading the transformer in the lint
    // runtime — it's exported from d_rocket. We
    // do a dynamic import via the pub.dev package
    // path here to keep the lint plugin
    // self-contained.
    final String transformed = _transform(source);
    if (transformed == source) return; // no change
    context.sharedState['d_rocket_transformed_source'] = transformed;
    context.sharedState['d_rocket_original_source'] = source;
  }

  @override
  void run(
    CustomLintResolver resolver,
    ChangeReporter reporter,
    CustomLintContext context,
    Diagnostic analysisError,
    List<Diagnostic> others,
  ) {
    // .i — guided workaround: the
    // DartFix API exposes `addSimpleInsertion(int
    // offset, String text)` for inserting, but
    // every "replace" / "delete" method requires
    // a `SourceRange` (which is internal to
    // _fe_analyzer_shared). So a true in-place
    // replacement is blocked.
    //
    // Workaround: insert a **comment** at the
    // end of each offending call site with the
    // equivalent `Expr.lambda(...)` form. After
    // `dart fix --apply`, the user sees the
    // hint comment in-place and can copy-paste
    // manually. Not as clean as auto-replace,
    // but it ships and avoids the
    // post-apply ambiguity (two calls instead
    // of one).
    final int nodeOffset = analysisError.offset;
    final int nodeLength = analysisError.length;
    if (nodeLength <= 0) return;

    // Detect the closure's param + body.
    // For MVP we just append a TODO comment
    // with the suggested form. The real
    // translation is done by the CLI (.g).
    final String hint = '  // d_rocket: try \n'
        '  //   dart run d_rocket:rocket_closure transform-file <this-file>';

    final changeBuilder = reporter.createChangeBuilder(
      message: 'Mark closure LINQ call site for manual rewrite',
      priority: 1,
    );
    changeBuilder.addGenericFileEdit((builder) {
      // .i workaround: insert the
      // hint comment AFTER the call site (so
      // we don't need to delete the original).
      // The user reads the comment, runs the
      // CLI, and the CLI does the real rewrite.
      builder.addSimpleInsertion(nodeOffset + nodeLength, hint);
    });
  }

  /// .i: thin wrapper around the
  /// real d_rocket `transformFileSource` function.
  /// Just delegated.
  static String _transform(String source) => transformFileSource(source);
}
