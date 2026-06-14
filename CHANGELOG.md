# Changelog

All notable changes to `d_rocket_builder` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
