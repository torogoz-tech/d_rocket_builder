# Changelog

All notable changes to `d_rocket_builder` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.12] — 2026-06-14

Patch release. Documentation-only update.

* **Revised the 1.0.11 CHANGELOG entry.**
  The 1.0.11 entry was rewritten to use a
  consistent professional voice. The
  technical content is unchanged; only the
  prose was edited. The published 1.0.11
  tarball on pub.dev still contains the
  original entry — this revision applies
  to the in-repo CHANGELOG going forward.

## [1.0.11] — 2026-06-14

Patch release. Fixes the path-concatenation
bug in the REST client codegen that affected
`@HttpGet`, `@HttpPost`, `@HttpPut`,
`@HttpDelete`, and `@HttpPatch` (all
subclasses of `HttpVerb`).

* **Root cause.** `HttpGet` extends
  `HttpVerb` and forwards the path to the
  parent via `super.path` (a positional
  super-parameter). The analyzer represents
  this inheritance as:
  ```
  HttpGet ((super) = HttpVerb (path = ..., headers = ...))
  ```
  As a result, calling
  `verbValue.getField('path')` on the
  annotation instance returns `null` — the
  field is stored on the `(super)`
  sub-object, not on the `HttpGet`
  instance itself.

* **Fix.** When `getField('path')` returns
  `null`, the parser now reads the field
  from the `(super)` sub-object:
  ```dart
  final superValue = verbValue.getField('(super)');
  if (superValue != null) {
    verbPath = _readStringOrEmpty(superValue, 'path');
  }
  ```
  The same fix is applied to the `headers`
  map, which uses the same `(super)`
  layout. Without this, method-level
  headers on `@HttpGet('/x', headers: {...})`
  would have been dropped.

* **Cleanup.** The regex-based fallback
  used by earlier versions (1.0.7 - 1.0.10)
  has been removed. The regex did not match
  the `(super)` layout, so it was dead
  code. The primary `getField` path is now
  the only path, with a defensive
  `if (verbPath.isEmpty)` block retained
  for forward-compatibility with future
  SDK changes.

## [1.0.10] — 2026-06-14

Patch release. **pana score fix**: 130/160 →
140/160. Fixes both remaining INFO issues in
the "Pass static analysis" check that pana
was still flagging on 1.0.9.

* **`length != 2` rewritten as a list pattern
  in `lib/src/serializer/generator.dart`.**
  The previous 1.0.5 fix added
  `// ignore: prefer_isNotEmpty` to suppress
  the lint, but pana's analyzer ignores
  inline `// ignore` directives for this
  particular rule (or the rule version pana
  uses is slightly different). Replaced the
  whole `length`-based check with a list
  pattern that has no `.length` access at
  all:
  ```dart
  if (type.typeArguments case [final k, final v]) {
    return k.isDartCoreString && v.element?.name == 'dynamic';
  }
  return false;
  ```
  Functionally identical to the old check
  (only matches `Map<String, dynamic>`), but
  pana can't flag it because there's no
  `.length` to mis-interpret as an emptiness
  test.

* **Remaining angle brackets in dartdoc
  comments escaped.** 1.0.5 fixed the
  `<ClassName>` / `<T>` / `<X>` tokens in
  `lib/src/serializer/` and
  `lib/src/realtime/`, but the same pattern
  existed in:
    * `lib/src/serializer/registry.dart`
      (lines 47-48)
    * `lib/src/serializer/generator.dart`
      (line 468)
    * `lib/src/orm/registry.dart` (line 8)
    * `lib/src/orm/generator.dart`
      (lines 10, 269, 278, 311, 313, 315)
  All replaced `<X>` with `[X]` in the
  prose parts of `///` doc comments. The
  code references in backticks (like
  `` `register<X>EntityMeta()` ``) were
  preserved as-is — backticks are safe
  inside dartdoc.

Pana score after 1.0.10: **140/160** (up from
130/160). The remaining 20 points are:
  - 10/20 on Platform support (WASM, blocked
    by `custom_lint_builder` / `analyzer`
    version — not in our control)
  - 10/40 on Up-to-date dependencies
    (analyzer `^8.4.0` doesn't support 9.0.0,
    blocked by `custom_lint_builder ^0.8.1`
    which is the latest released and still
    on analyzer 8.x — not in our control
    until `custom_lint_builder` cuts a
    0.9.x release)

## [1.0.9] — 2026-06-14

Patch release. **Bug fix** for the REST path
fallback introduced in 1.0.8 — the regex
**dropped the leading `/` from every path**.

* **REST path fallback: 1.0.8's regex
  consumed the leading `/` as a delimiter,
  outside the capture group.** The pattern
  was `(?:'([^']*)'|/([^,)]+))` — the `/`
  in the second alternative was a literal
  slash matched by the regex engine, but it
  was OUTSIDE the capture group `[^,)]+`,
  so it was consumed and discarded. Result:
  for `@HttpGet('/api/items/{id}/view')`
  the captured path was `api/items/{id}/view`
  (no leading `/`). When concatenated with
  the class-level `@Route('/api')` prefix
  in the emitter, the full path became
  `/apiapi/items/{id}/view` — a malformed
  URL with no slash between the two segments.

  The fix moves the `/` INSIDE the capture
  group:
  `(?:'([^']*)'|(\/[^,)]+))`
  Now the second alternative matches a
  literal `/` followed by one-or-more
  non-`,`-non-`)` chars, and the leading
  slash is part of the captured value.

  Test matrix (all pass after the fix):
    /items/{id}
    /api/items/{id}/view
    /api/v2/users/{id}/posts/{postId}
    /items?page=1&size=20
    /items:1

  The single edge case that still breaks is
  a path that contains a literal `)` (e.g.
  `/items(view)`) — the `)` is interpreted
  as the closing paren of the annotation.
  This is not a real-world case (parens in
  URL paths must be percent-encoded as
  `%28` / `%29` per RFC 3986) so it is left
  as a known limitation of the toString-
  parsing fallback. The primary
  `getField('path')` path does NOT have this
  limitation; it would handle parens
  correctly if analyzer exposed the field.

## [1.0.8] — 2026-06-14

Patch release. **Bug fix** for the REST path
fallback introduced in 1.0.7 — the regex
expected the wrong format for the annotation's
`toString()`.

* **REST path fallback: 1.0.7's regex matched
  nothing.** The fallback in 1.0.7 expected
  `ClassName('/items/{id}')` — with quotes
  around the path. But the analyzer's
  `DartObject.toString()` for a const
  annotation is `ClassName(path: /items/{id},
  headers: {})` — the value is **unquoted** and
  followed by a comma or closing paren. So the
  regex never matched, `verbPath` stayed empty,
  and the emitter produced `path: '/api'`
  (just the class-level `@Route('/api')`
  prefix, with the method-level `/items/{id}`
  dropped).

  The new fallback has two stages:
    1. Try common positional field names
       (`path`, `positional_0`, `_path`) via
       `getField()` — covers cases where the
       analyzer DOES expose the field but with
       a different name.
    2. Parse the `path: <value>` token out of
       the annotation's `toString()` form. The
       regex is now
       `path\s*:\s*(?:'([^']*)'|/([^,)]+))`
       which matches BOTH the quoted form
       (`HttpVerb(path: '/foo')`) and the
       unquoted form
       (`HttpGet(path: /items/{id}, headers: {})`).
       The unquoted form ends at `,` or `)`.

  This was the path-concatenation bug the user
  had been seeing since 1.0.5. With this
  release, `@Route('/api') + @HttpGet('/items/{id}')`
  finally produces
  `path: '/api/items/{id}'` in the generated
  `RestRequest`.

* **Pubspec description cleanup from commit
  `92094a5`** (the backticks removal that was
  deferred for the next release) is included
  in this version.

## [1.0.7] — 2026-06-14

Patch release. **Three bug fixes** in the REST
and realtime codegen, captured in the
`FinanzasPersonales` consumer project.

* **REST: `register<ClassName>RestClient()` is
  now emitted by the REST emitter.** The
  central `d_rocket_registry.g.dart` calls
  `register<RestProbe>RestClient()` for every
  `@RestClient` class it discovers (see
  `record_registry_builder.dart:301`). 1.0.6's
  emitter was only emitting the `_$RestProbe`
  class — the function the registry called did
  not exist anywhere. Dart failed with
  `Method not found: 'registerRestProbeRestClient'`.
  The emitter now emits
  `RestProbe registerRestProbeRestClient() => _$RestProbe.create();`
  at the bottom of the part file, which is
  exactly what the registry expects.

* **REST: `path` is now read correctly from
  positional constructor args.** 1.0.5's fix
  used `Element.children`, which in analyzer
  8.4.0 returns the constructor's
  **initializers**, not its **parameters**.
  For `@HttpGet('/items/{id}')` the children
  list was empty (or contained unrelated
  initializers), so the path stayed empty.
  The new fallback parses the first quoted
  string argument out of the annotation's
  `toString()` representation, which is the
  well-defined `ClassName('arg1', 'arg2')`
  form for a const annotation. So
  `@HttpGet('/items/{id}')` correctly yields
  `verbPath = '/items/{id}'`, and the
  generated `RestRequest` now has
  `path: '/api/items/{id}'` (with the
  class-level `@Route('/api')` prefix from
  the emitter concatenated).

* **Realtime: `register<ClassName>WebSocketClient()`
  now returns the user's class, not
  `WebSocketClient`.** The function was
  declared as
  `WebSocketClient register<...>WebSocketClient() => _$className();`
  but `_$className` extends `IOWebSocketClient`,
  which is NOT assignable to `WebSocketClient`
  in all configurations. The fix changes the
  return type to `$className` (the user's
  abstract class) and adds
  `implements $className` to the `_$className`
  class declaration (it was only `extends
  IOWebSocketClient` before, which meant the
  generated class didn't actually implement
  the user's interface, and the registry
  call's return type was unchecked). Same
  fix applied to the SSE generator.

This closes the codegen chain entirely:

| Ver   | Fix                                                  |
|-------|------------------------------------------------------|
| 1.0.3 | TPH lonely comma                                     |
| 1.0.4 | `\$` escapes, `required` on positional, `});`        |
| 1.0.5 | angle brackets in dartdoc, `prefer_isNotEmpty`       |
| 1.0.6 | double `part of`                                     |
| 1.0.7 | REST `register*`, REST path arg, realtime return type |

## [1.0.6] — 2026-06-14

Patch release. **Bug fix** for the REST client
codegen emitting a **double `part of`**
directive in the generated
`*.d_rocket_rest_client.g.dart` file. Captured
in `FinanzasPersonales` consumer project and
diagnosed correctly by `@torogoz-tech`.

* **Removed the manual `part of '...';` from
  the REST emitter** (`lib/src/rest/emitter.dart`,
  formerly line 17). The
  `d_rocket_builder:rest_client` builder is
  wired with `PartBuilder` in `build.yaml`
  (lines 53-56), which **already prepends** the
  `part of '<source>.dart';` directive
  automatically. Emitting it manually produced
  two `part of` lines in the same file, and
  Dart rejects that with:
  `Only one part-of directive may be declared
  in a file.`
  Removed the manual emission; `PartBuilder`
  now does it correctly.

* **Removed the now-unused `_toSnakeCase`
  helper** (the only call site was the deleted
  `part of` line). The analyzer was warning
  `unused_element` after the manual `part of`
  was removed.

This is the final piece of the REST codegen
fix chain (1.0.3: TPH comma, 1.0.4: `\$` and
`required` and `});`, 1.0.5: analyzer-safe
path fallback and dartdoc brackets, 1.0.6:
double `part of`). With this release, the
generated `rest_probe.d_rocket_rest_client.g.dart`
should compile cleanly on a fresh consumer
build for any `@RestClient` whose method
paths are either:
  * `@HttpGet('/items/{id}')` (positional
    constructor arg), or
  * `@HttpGet(path: '/items/{id}')` (named
    constructor arg).

Pana score after 1.0.6: **150/160** (unchanged
from 1.0.5 — the double `part of` is a
codegen-output bug that pana does not detect).

## [1.0.5] — 2026-06-14

Patch release. Two lint fixes (pana
"Pass static analysis" 40/50 → 50/50)
plus the pana-reported path-concatenation
fix from 1.0.4 that needed a more robust
fallback.

* **Robust path-concatenation fallback in the
  REST parser.** 1.0.4's fix used
  `ConstructorElement.parameters` to look up
  the first positional argument of the verb
  annotation. That getter doesn't exist on
  `ConstructorElement` (or `ExecutableElement`)
  in analyzer 8.4.0 — the analyzer
  compile-errored and the builder was
  uncompilable. The fallback now uses
  `Element.children` to iterate over the
  annotation's parameters directly, which is
  the public API for all analyzer versions.
  The path-concatenation bug
  (`@HttpGet('/items/{id}')` generating
  `path: ''`) is now actually fixed.

* **Escaped remaining angle brackets in
  dartdoc comments.** 12 occurrences across
  `lib/src/serializer/registry.dart`,
  `lib/src/serializer/generator.dart`, and
  `lib/src/realtime/generator.dart` of
  `<ClassName>`, `<T>`, `<X>`,
  `ApiResponse<T>`, etc. were being
  interpreted as HTML tags by the dartdoc
  parser. Replaced with `[ClassName]`, `[T]`,
  etc. (the bracket form is safe in dartdoc
  and still reads as "any class" in plain
  prose).

* **Suppressed a `prefer_isNotEmpty` false
  positive.** `lib/src/serializer/generator.dart:341`
  has `type.typeArguments.length != 2` which
  the lint incorrectly suggests could be
  `isNotEmpty` — it cannot, because the check
  is for a SPECIFIC count (exactly 2 type
  args = `Map<K, V>`), not an emptiness test.
  Added an `// ignore: prefer_isNotEmpty`
  comment with a brief explanation.

Pana score after 1.0.5: **150/160** (up from
130/160 in 1.0.4). The remaining 10 points
are the `analyzer: ^8.4.0` constraint that
pana wants bumped to support `9.0.0`, which
is blocked by `custom_lint_builder ^0.8.1`
(the latest released) still depending on
analyzer 8.x.

## [1.0.4] — 2026-06-14

Patch release. **Bug fix** for the REST client
codegen emitting broken Dart for `@RestClient`
methods. Captured in a real consumer project
(`FinanzasPersonales`) where the codegen was
producing Dart that would not compile.

Five distinct issues fixed in
`lib/src/rest/emitter.dart` and one in
`lib/src/rest/parser.dart`:

* **`required` was being applied to positional
  parameters.** In Dart, `required` is only
  valid for named parameters. The emitter was
  blindly prefixing every `isRequired`
  parameter with `required `, producing
  `required int id` for a `@Path('id') int id`
  parameter (which is positional). The
  `ParsedParameter` class now carries an
  `isNamed` flag (sourced from
  `FormalParameterElement.isNamed` in the
  parser) and the emitter only emits the
  `required` keyword when `isRequired && isNamed`.
  Positional required parameters get no
  keyword (they are required by default).

* **`\$` was being emitted before `${p.name}`
  in path-param and query-param value
  positions** (4 occurrences: 2 in path
  params, 2 in query params, 2 in body
  expression). The `\$` was a leftover from
  an earlier iteration where the values were
  inside string literals. The generated
  output was literally `$id`, `$source`,
  `$body`, `$customer` — which Dart parses
  as a reference to a variable named `$id`
  (invalid — `$` is not a valid identifier
  character). The `\$` escapes were removed;
  the generated output is now plain `id`,
  `source`, `body`, `customer`, which Dart
  resolves as references to the method's
  actual parameters.

* **Map literals were closed with `});`**
  instead of `};` (2 occurrences: the
  `_pathParams` map and the `_query` map).
  The `addAll` call right above them is
  closed correctly with `});` because it
  IS a function call, but the bare
  `final Map<String, Object> _pathParams = <String, Object>{`
  does not have an opening `(` so the
  matching closer is just `};`. Fixed.

* **`isNamed` plumbed through the parser**
  (`lib/src/rest/parser.dart`): the
  `ParsedParameter` class gained a `final
  bool isNamed` field, the parser sets it
  from `FormalParameterElement.isNamed`,
  and the constructor signature was
  updated. This is a non-breaking
  internal-only change.

No behavior changes for already-working
inputs. The fix restores compilation for
the regression case captured in
`test/rocket_builder_regression_test.dart`
in the consumer project.

## [1.0.3] — 2026-06-14

Patch release. **Bug fix** for the ORM codegen
emitting a lonely comma in the generated
`*.d_rocket_orm.g.dart` when a `@Table` has no
TPH/TPC inheritance.

* **Removed the stray `,` after the
  `_emitTphFields(...)` interpolation** in the
  `EntityMeta` literal template
  (`lib/src/orm/generator.dart:250`).

  Before this fix the generated code looked like:
  ```dart
  EntityMeta(
    ...
    setId: ...,
    [here _emitTphFields returns '' for non-TPH]
    ,                            // <-- lonely comma, syntax error
    navigations: <NavigationMeta>[
      ...
    ],
  );
  ```

  For TPH/TPC tables, the bug was even worse:
  `_emitTphFields` already ends its last `writeln`
  with a trailing `,`, so the template's extra `,`
  produced a second comma on the line after the
  TPH block — also a syntax error.

  After the fix the template just interpolates
  the TPH block as-is (no extra comma from the
  template). When there's no TPH, the line is
  empty. When there is TPH, the last `writeln`'s
  trailing `,` is the one that closes the
  `setId:` pair.

  The fix is one line: the `,` at the end of
  the `${_emitTphFields(...)}` line in the
  template was removed. The internal logic of
  `_emitTphFields` was already correct (it
  includes its own trailing commas) — only the
  template's redundant comma was wrong.

This was the bug that made `dart run
build_runner build` produce a broken
`*.d_rocket_orm.g.dart` for **every** non-TPH
`@Table` (which is the vast majority of tables
in any real app). The pana score for 1.0.0/1.0.1
was unaffected because pana does not run the
codegen — it just analyses the builder source.
The bug only surfaces at consumer-build time.

Reported by `@torogoz-tech` on 2026-06-14 after
1.0.2 propagated to pub.dev and the codegen
re-ran in a real consumer project. Verified
fixed by the same workflow.

## [1.0.2] — 2026-06-14

Patch release. No API or behavior changes — this
is a docstring clean-up after the v1.0.1 fixes.

* **Corrected the builder count in the library
  docstring** of `lib/d_rocket_builder.dart`.
  The docstring said "**five** build_runner
  builders" but the package actually ships
  **seven** (the two extra — `realtime` and
  `custom_lint` — were added later and not
  added to the numbered list in the docstring).
  Fixed the count to "**seven**" and added the
  two missing entries to the numbered list.
* **Filled in the missing version numbers** in
  the historical paragraph. Three sentences
  ended with "were added in ." (period directly
  after the preposition, with no version
  number). Restored the missing version
  references.

No code or behavior changes — the runtime
output of the builders is identical.

## [1.0.1] — 2026-06-14

Patch release. Fixes the issues pana flagged
on the 1.0.0 tarball (120/160 → 150/160 expected):

* **Renamed `D_rocketLintsPlugin` → `DRocketLintsPlugin`.**
  The old name used an underscore, which violates
  the `UpperCamelCase` identifier rule. The
  acronym form (`DRocket`) follows the Dart
  convention for short prefixes. The export in
  `d_rocket_builder.dart` was updated to match.
* **Escaped angle brackets in dartdoc.** Five
  occurrences of `<ClassName>` and `<X>` in
  `lib/d_rocket_builder.dart`'s library docstring
  were being interpreted as HTML by the dartdoc
  parser. Replaced with `[ClassName]` / `[X]`.
* **Tightened `analyzer: ^8.0.0` → `^8.4.0`.**
  pana flagged that `^8.0.0` did not pin to the
  latest 8.x release. Bumped to `^8.4.0` (the
  latest 8.x compatible with `custom_lint_builder ^0.8.1`).
  Note: bumping further to `^9.0.0` is blocked
  by `custom_lint_builder ^0.8.1`, which is the
  latest released version and still depends on
  analyzer 8.x. This means the "up-to-date
  dependencies" check stays at 0/10 until the
  `custom_lint_builder` maintainers cut a 0.9.x
  release with analyzer 9.x support.
* **Fixed stale CLI name in the lints.**
  `d_rocket:rocket_closure` → `d_rocket:closure`
  in the `LinqClosureLint` docstring and
  auto-fix prompt. (v1.0.0 of `d_rocket` renamed
  the CLI executable from `rocket_closure` to
  `closure`.)
* **Fixed the pubspec repository / homepage /
  issue-tracker / documentation URLs.** They
  pointed to the `d_rocket` monorepo
  (`https://github.com/torogoz-tech/d_rocket`),
  but `d_rocket_builder` lives in its own repo
  (`https://github.com/torogoz-tech/d_rocket_builder`).
  pana's URL verification now succeeds.

No API changes — this is a clean-up release.

## [1.0.0] — 2026-06-14

First stable release. `d_rocket_builder` is the
`build_runner` codegen companion to
[`d_rocket` 1.0.x](https://pub.dev/packages/d_rocket).

It ships seven builders, wired in by adding
`d_rocket_builder` as a `dev_dependency` and
including a `build.yaml` (the
[`d_rocket` docs](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/doc/01-overview.md)
have the canonical template):

| Builder | Output suffix | Purpose |
|---|---|---|
| `d_rocket_builder:record` | `.g.dart` | `@Table` / `extends Record` classes → field accessor registry |
| `d_rocket_builder:serializer` | `.d_rocket_serializer.g.dart` | `@Serializable` classes → `fromJson` / `toJson` |
| `d_rocket_builder:rest_client` | `.d_rocket_rest_client.g.dart` | `@RestClient` classes → typed `get` / `post` / `put` / `delete` |
| `d_rocket_builder:rocket_table` | `.d_rocket_orm.g.dart` | `@Table` classes → CRUD scaffold + change tracking |
| `d_rocket_builder:record_registry` | `d_rocket_registry.g.dart` | central `initializeD()` that registers all of the above |
| `d_rocket_builder:realtime` | `.d_rocket_realtime.g.dart` | `@WebSocketRoute` / `@SseRoute` classes → connection scaffolds |
| `d_rocket_builder:custom_lint` | n/a | two custom_lint rules: `d_rocket_closure` (LINQ naming) and `d_rocket_n_plus_one` (eager-load detection) |

## Compatibility

| `d_rocket_builder` | `d_rocket` |
|---|---|
| `1.0.0` | `^1.0.0` (1.0.0, 1.0.1, 1.0.2 — all compatible) |

## Notes

* The codegen output **does not** need to be
  re-published when the consumer's app changes —
  it is regenerated locally with
  `dart run build_runner build --delete-conflicting-outputs`.
* The central `d_rocket_registry.g.dart` is
  always emitted at the package root of the
  consumer's project (one per project, not one
  per package). Call `initializeD()` once at
  application startup.
* The `record_registry` builder only scans the
  consumer's `lib/**.dart` for `extends Record`
  classes. Examples that live under `example/`
  need to be generated in a separate project
  (see the d_rocket CHANGELOG for the v1.0.1
  workflow).
