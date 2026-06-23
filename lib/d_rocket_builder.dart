/// 🚀 d_rocket_builder — build_runner codegen for d_rocket.
///
/// This package provides **five** build_runner builders that
/// together wire up the d_rocket framework:
///
/// 1. `d_rocket_builder:record` (a `PartBuilder` with the
///    default `.g.dart` suffix) — walks `extends Record` classes
///    and emits a `part` file with a `_[ClassName]Init` class plus
///    a `register[ClassName]Record()` function per class.
/// 2. `d_rocket_builder:serializer` (a `PartBuilder` with the
///    `.d_rocket_serializer.g.dart` suffix) — walks `@Serializable`
///    classes and emits a `part` file with `XFromJson` / `XToJson` /
///    `register[X]Serializer()` per class.
/// 3. `d_rocket_builder:rest_client` (a `PartBuilder` with the
///    `.d_rocket_rest_client.g.dart` suffix) — walks `@RestClient`
///    classes and emits a `part` file with a `_$[ClassName]`
///    implementation plus a `register[ClassName]RestClient()`
///    factory per class.
/// 4. `d_rocket_builder:rocket_table` (a `PartBuilder` with the
///    `.d_rocket_orm.g.dart` suffix) — walks `@Table`
///    classes and emits a `part` file with a
///    `_$Table[ClassName].entityMeta` literal plus a
///    `register[ClassName]EntityMeta()` helper per class.
/// 5. `d_rocket_builder:record_registry` (a `LibraryBuilder`) —
///    scans the consumer's `lib/**.dart`, collects all `extends
///    Record` **and** all `@Serializable` **and** all
///    `@RestClient` **and** all `@Table` classes, and
///    emits a single `lib/d_rocket_registry.g.dart` with a public
///    `initializeD()` function that calls every
///    `register[ClassName]Record()`, every
///    `register[ClassName]Serializer()`, every
///    `register[ClassName]RestClient()`, and every
///    `register[ClassName]EntityMeta()`.
///
/// The user calls `initializeD()` once in `main()` and every
/// d_rocket-managed class is wired up.
///
/// ## / / (absorb + ORM)
///
/// The `d_rocket_builder:serializer` and the extension of
/// `d_rocket_builder:record_registry` to detect `@Serializable`
/// were added in . The `d_rocket_builder:rest_client` and
/// the extension of `d_rocket_builder:record_registry` to detect
/// `@RestClient` were added in . The
/// `d_rocket_builder:rocket_table` and the extension of
/// `d_rocket_builder:record_registry` to detect `@Table`
/// were added in ("ORM").
///
/// Before these phases, the codegen was split across three
/// separate packages (`d_builder`, `d_serializer_build`,
/// `d_rest_build`) with three separate `initializeD*()` calls.
/// All four (records, serializers, REST clients, ORM tables)
/// are now unified here under a single `initializeD()`.
///
/// ## Output namespaces
///
/// The four per-file builders use **distinct** `PartBuilder`
/// suffixes so a single Dart file can use
/// `extends Record` + `@Serializable` + `@RestClient` +
/// `@Table` without any build error:
///
/// - `record`        → `*.g.dart` (the default `source_gen` suffix
///                      for `extends Record` classes).
/// - `serializer` → `*.d_rocket_serializer.g.dart` ('s
///                      non-default suffix to avoid collision with
///                      the `record` builder; see HANDOFF.md §6).
/// - `rest_client` → `*.d_rocket_rest_client.g.dart` ('s
///                      non-default suffix, same rationale).
/// - `rocket_table` → `*.d_rocket_orm.g.dart` ('s
///                      non-default suffix, same rationale).
library d_rocket_builder;

import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/migration/migration_generator.dart';
import 'src/orm/generator.dart';
import 'src/realtime/generator.dart';
import 'src/record_generator.dart';
import 'src/record_registry_builder.dart';
import 'src/rest/generator.dart';
import 'src/serializer/generator.dart';

// 2.0.0 — Lints moved to the dedicated
// `d_rocket_lints` package. We re-export
// them here so existing consumers of
// `d_rocket_builder` don't have to
// update their imports. New consumers
// should depend on `d_rocket_lints`
// directly (it's a `dev_dependency`).
export 'package:d_rocket_lints/d_rocket_lints.dart';

/// Builder factory for `d_rocket_builder:record`.
///
/// Returns a [PartBuilder] (default `.g.dart` suffix) that walks
/// `extends Record` classes and emits a `_[ClassName]Init` class
/// plus a `register[ClassName]Record()` function per class.
Builder buildRecord(BuilderOptions options) {
  return PartBuilder(<Generator>[RecordGenerator()], '.g.dart');
}

/// Builder factory for `d_rocket_builder:serializer`.
///
/// Returns a [PartBuilder] with the **non-default**
/// `.d_rocket_serializer.g.dart` suffix ('s HANDOFF §6 fix).
Builder buildSerializer(BuilderOptions options) {
  return PartBuilder(
    <Generator>[SerializableGenerator()],
    '.d_rocket_serializer.g.dart',
  );
}

/// Builder factory for `d_rocket_builder:rest_client`.
///
/// Returns a [PartBuilder] with the **non-default**
/// `.d_rocket_rest_client.g.dart` suffix ('s HANDOFF §6 fix).
/// Walks `@RestClient` classes and emits a `_$[ClassName]`
/// implementation plus a `register[ClassName]RestClient()` factory
/// per class.
Builder buildRestClient(BuilderOptions options) {
  return PartBuilder(
    <Generator>[const RestClientGenerator()],
    '.d_rocket_rest_client.g.dart',
  );
}

/// Builder factory for `d_rocket_builder:rocket_table`.
///
/// Returns a [PartBuilder] with the **non-default**
/// `.d_rocket_orm.g.dart` suffix ('s HANDOFF §6 fix).
/// Walks `@Table` classes and emits a per-class
/// `static EntityMeta entityMeta` plus a
/// `register[ClassName]EntityMeta()` helper per class.
Builder buildRocketTable(BuilderOptions options) {
  return PartBuilder(
    <Generator>[const TableGenerator()],
    '.d_rocket_orm.g.dart',
  );
}

/// Builder factory for `d_rocket_builder:record_registry`.
///
/// Returns a [Builder] (a `LibraryBuilder`, not a `PartBuilder`)
/// that scans `lib/**.dart` for `extends Record` **and**
/// `@Serializable` **and** `@RestClient` **and** `@Table`
/// classes and emits a single `lib/d_rocket_registry.g.dart`
/// with the public `initializeD()` function.
Builder buildRecordRegistry(BuilderOptions options) {
  return RecordRegistryBuilder();
}

// ───: code-first migration codegen ───
//
// `d_rocket_builder:rocket_migration` walks every
// `@Migration` top-level function and emits a
// `_$<FunctionName>` `MigrationBase` class that knows
// about every `@Table` in the same library.
// The user's function is then `T initialSchema() =>
// _$_InitialSchema();` — returns the migration
// instance, ready to be added to the context's
// `migrations` list.

/// Builder factory for `d_rocket_builder:rocket_migration`.
///
/// Returns a [PartBuilder] with the **non-default**
/// `.d_rocket_migration.g.dart` suffix. Walks
/// `@Migration` top-level functions and emits a
/// `MigrationBase` class that runs `entityMeta.createTableDdl()`
/// for every `@Table` in the same library.
Builder buildRocketMigration(BuilderOptions options) {
  return PartBuilder(
    <Generator>[const MigrationGenerator()],
    '.d_rocket_migration.g.dart',
  );
}

// ───: realtime codegen (WebSocket + SSE) ───

/// Builder factory for `d_rocket_builder:realtime`.
///
/// Returns a [PartBuilder] with the **non-default**
/// `.d_rocket_realtime.g.dart` suffix. Walks
/// `@WebSocketClient` and `@SseClient` abstract
/// classes and emits a `_$[ClassName]` that extends
/// [IOWebSocketClient] / [HttpSseClient] with the
/// URL + headers baked in.
Builder buildRealtime(BuilderOptions options) {
  return PartBuilder(
    <Generator>[
      const WebSocketClientGenerator(),
      const SseClientGenerator(),
    ],
    '.d_rocket_realtime.g.dart',
  );
}


// ─── .h: custom_lint plugin ───────────────────────

/// .h: the `custom_lint` plugin entry
/// point. Add to your `analysis_options.yaml`:
///
/// ```yaml
/// analyzer:
///   plugins:
///     - d_rocket
/// ```
///
/// Then `dart run custom_lint` (or your IDE's
/// analyzer) will report
/// `d_rocket_untranslated_closure_linq` on every
/// `.where_((t) => …)` call site, with a hint to run
/// the auto-rewriter CLI.
