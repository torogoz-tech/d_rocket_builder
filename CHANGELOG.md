# Changelog

All notable changes to `d_rocket_builder` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-06-12 — First stable release

The first stable release of `d_rocket_builder`. The codegen
output is now considered stable: re-running the generator
on an unchanged source file produces a byte-identical
`*.g.dart`, and the public API of the generated registry
(`initializeD()`) is frozen within the `1.x` series.

This release ships the codegen pipeline that supports
[`d_rocket` 1.0.0](../d_rocket/CHANGELOG.md). It includes
the four builder phases, two custom lint rules, the
migration scaffolder CLI, and the closure-sugar translator.

### Added

- **`d_rocket:rocket_serializer` builder** — emits per-class
  `fromJson` and `toJson` for every `@Serializable()`-annotated
  class, plus a central `register<X>Serializer` call in
  `d_rocket_registry.g.dart`. Supports:
  - `JsonNaming` policies (`none`, `snakeCase`, `camelCase`,
    `kebabCase`, `pascalCase`).
  - `UnknownKeyPolicy` (`ignore` default, `strict`,
    `capture`).
  - `@JsonKey(name: ..., ignore: ..., requiredKey: ...,
    defaultValue: ..., converter: ..., useEnumIndex: ...,
    unknownEnumValue: ...)` per-field overrides.
  - `Format` (class, not enum): `Format.trim()`,
    `Format.uppercase()`, `Format.lowercase()`,
    `Format.date('yyyy-MM-dd' | 'iso8601')`,
    `Format.custom(name)`, `Format.customWith(type)`.
  - `@SerializableUnion` for sealed sum types with
    discriminator dispatch.

- **`d_rocket:rocket_rest_client` builder** — emits per-
  interface `RestClient` implementations with the full
  interceptor chain, retry / backoff, rate limiting, and
  circuit breaker wired in. Supports:
  - `@HttpGet` / `@HttpPost` / `@HttpPut` / `@HttpPatch` /
    `@HttpDelete` / `@HttpHead`.
  - Parameter binding: `@Path`, `@Query`, `@Header`, `@Body`,
    `@Field`, `@Part`, `@RawBody`.
  - Streaming `Stream<T>` return types.
  - `CancelToken` for cancellable requests.
  - `MockHttpClient` integration for tests.

- **`d_rocket:rocket_table` builder** — emits per-class
  `fromRow` (row materialiser) and `setId` (back-propagation
  hook) closures for every `@RocketTable`-annotated entity.
  Inspects each field's Dart type and `@Column(nullable: ...)`
  flag to decide whether the cast is `T?` (nullable columns)
  or `T? ?? <default>` (non-nullable columns with a
  defensive default). Also generates `BazSchema` constants
  (table name, column names) for the SQL provider.

- **`d_rocket:rocket_closure` builder** *(optional)* —
  emits closure-sugar `where` / `select` / `orderBy` /
  `groupBy` extensions for prototyping over `Iterable<T>`.
  Translation: closure calls to LINQ operators are rewritten
  to use the same `Expr` tree as the type-safe version, so
  the query can be pushed to SQL in the future without
  rewriting the call sites.

- **`d_rocket:rocket_migration` CLI** — `dart run
  d_rocket:rocket_migration add <name>` scaffolds a new
  migration with the right id, class name, and pre-filled
  `up()` / `down()` bodies. `dart run d_rocket:rocket_migration
  doctor` validates that the migration history is contiguous
  (no gaps).

- **Custom lint rules** (via `package:custom_lint_builder`):
  - `d_rocket_n_plus_one` — flags LINQ queries that
    trigger N+1 round-trips. Promotes `include_<T>()` and
    pre-fetch.
  - `d_rocket_closure` — flags LINQ operators used on raw
    `Iterable<T>` without an `Expr` (these evaluate in-memory
    only and can't be pushed to SQL).

- **Central `d_rocket_registry.g.dart`** — the single
  generated file that imports every `*.d_rocket_*.g.dart` in
  the project and registers them all in one `initializeD()`
  call.

### Migration from `d_serializer_builder` / `d_rest_builder` 0.x

- `d_serializer_builder` 0.4.0 was absorbed into
  `d_rocket_builder 1.0`. Replace
  `package:d_serializer_builder/d_serializer_builder.dart`
  with `package:d_rocket_builder/d_rocket_builder.dart`.
  The `@Serializable()` annotation is unchanged; the
  generated file suffix changed from
  `*.d_serializer.g.dart` to `*.d_rocket_serializer.g.dart`.

- `d_rest_builder` 0.1.0 was absorbed into
  `d_rocket_builder 1.0`. The `@RestClient` annotation is
  unchanged; the generated file suffix changed from
  `*.d_rest_client.g.dart` to
  `*.d_rocket_rest_client.g.dart`.

### License

© Torogoz Tech. Released under the MIT License.
