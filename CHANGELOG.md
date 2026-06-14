# Changelog

All notable changes to `d_rocket_builder` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
