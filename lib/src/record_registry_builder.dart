/// The registry builder that scans the consumer's `lib/**.dart`
/// and `example/**.dart` for `extends Record`, `@Serializable`,
/// `@RestClient` **and** `@Table` classes and emits one
/// `d_rocket_registry.g.dart` per package with a public
/// `initializeD()` function that registers every discovered class.
///
/// This is the **central entry point** of the d_rocket framework:
/// the user calls `initializeD()` once in `main()` and all
/// d_rocket-managed classes are wired up:
///
/// - `extends Record` classes → `register<X>Record()` (field accessor
///   registration, so the `Record` base class can produce a
///   debug-friendly `toString` and the LINQ `MemberAccess` evaluator
///   can read fields).
/// - `@Serializable` classes  → `register<X>Serializer()` (registers
///   the generated `XFromJson` / `XToJson` pair with the global
///   `Serializer` registry so it can dispatch on `T` at runtime).
/// - `@RestClient` classes    → `register<X>RestClient()` (adds a
///   factory `() => _$ClassName.create()` to the `RestClientRegistry`
///   so the user can resolve clients with `dRest.get<X>()`).
/// - `@Table` classes   → `register<X>EntityMeta()` (adds the
///   codegen-supplied `EntityMeta` to the global `EntityRegistry`
///   so `DbSet<T>` can build `INSERT` / `UPDATE` / `DELETE` SQL).
///
/// ## / / of the unification plan
///
/// The serializer detection was added in ("absorb
/// d_serializer"). The REST client detection was added in
/// ("absorb d_rest"). The `@Table` detection was
/// added in ("ORM"). Before these phases, the codegen was
/// split across three separate packages (`d_builder`,
/// `d_serializer_build`, `d_rest_build`) with three separate
/// `initializeD*()` calls. All four (records, serializers, REST
/// clients, ORM tables) are now merged into this single entry
/// point so the user only has to remember one call.
///
/// ## Why a `LibraryBuilder` and not a `PartBuilder`
///
/// The registry lives in its own top-level file (not as a
/// `part of`) so the user can `import 'd_rocket_registry.g.dart';`
/// and call `initializeD()` without `as` aliases. A `PartBuilder`
/// would force the user to add `part 'd_rocket_registry.g.dart';`
/// to every file — unusable for a single global entry point.
library d_rocket_builder.record_registry_builder;

import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';

import 'orm/registry.dart';
import 'realtime/registry.dart';
import 'rest/registry.dart';
import 'serializer/registry.dart';

/// Discovers every `extends Record` and every `@Serializable` class
/// in the consumer's `lib/**.dart` and emits one
/// `d_rocket_registry.g.dart` with the public `initializeD()`
/// function.
class RecordRegistryBuilder implements Builder {
  /// One output path: the registry lives in `lib/` so the
  /// generated file can use simple, local relative imports. All
  /// `extends Record` classes — in `lib/**` and in `lib/example/**`
  /// — are picked up and registered from there.
  @override
  Map<String, List<String>> get buildExtensions =>
      <String, List<String>>{
        r'$lib$': <String>['d_rocket_registry.g.dart'],
      };

  @override
  FutureOr<void> build(BuildStep buildStep) async {
    // The build_runner invokes this builder for the lib root only.
    final inputPath = buildStep.inputId.path;
    if (inputPath != r'lib/$lib$') return;

    // Per-source-file discoveries:
    //   records:        list of class names that `extends Record`
    //   serializable:   list of class names annotated with `@Serializable`
    //   restClients:    list of class names annotated with `@RestClient`
    //   ormTables:      list of class names annotated with `@Table`
    //   recordImports:  relative path → set of class names (records)
    //   serialImports:  relative path → set of class names (serializable)
    //   restImports:    relative path → set of class names (rest clients)
    //   ormImports:     relative path → set of class names (orm tables)
    //
    // We keep them as four separate maps because the generated
    // `initializeD()` emits per-class registration calls. The
    // (file → list) maps are later sorted for deterministic output.
    final Map<String, Set<String>> recordClassesByFile =
        <String, Set<String>>{};
    final Map<String, Set<String>> serializableClassesByFile =
        <String, Set<String>>{};
    final Map<String, Set<String>> restClientClassesByFile =
        <String, Set<String>>{};
    final Map<String, Set<String>> ormTableClassesByFile =
        <String, Set<String>>{};
    final Map<String, Set<String>> webSocketClientClassesByFile =
        <String, Set<String>>{};
    final Map<String, Set<String>> sseClientClassesByFile =
        <String, Set<String>>{};

    // Walk every `.dart` file under `lib/`, including nested
    // directories like `lib/example/`. (For a typical app, all
    // user code lives in `lib/` — including the runnable example
    // we keep at `lib/example/bookstore.dart` for ease of
    // registry wiring.)
    await for (final asset in buildStep.findAssets(Glob('lib/**.dart'))) {
      final libPath = asset.path;

      // Skip generated files (we must not recursively re-emit).
      if (libPath.endsWith('.g.dart')) continue;
      if (libPath.endsWith('.d_rocket_serializer.g.dart')) continue;
      if (libPath.endsWith('.d_rocket_rest_client.g.dart')) continue;
      if (libPath.endsWith('.d_rocket_orm.g.dart')) continue;
      if (libPath.endsWith('.d_rocket_realtime.g.dart')) continue;
      if (libPath.endsWith(r'd_rocket_registry.g.dart')) continue;

      // Resolve the library for this asset. If resolution fails
      // (e.g., a file has a parse error), skip it gracefully so
      // we don't crash the whole registry build.
      LibraryElement? lib;
      try {
        lib = await buildStep.resolver.libraryFor(asset);
      } catch (_) {
        continue;
      }
      // ignore: unnecessary_null_comparison
      if (lib == null) continue;

      for (final cls in lib.classes) {
        final String name = cls.displayName;
        if (name.isEmpty) continue;

        // Record detection: `extends Record` (from package:d_rocket).
        if (_extendsRecord(cls)) {
          recordClassesByFile
              .putIfAbsent(libPath, () => <String>{})
              .add(name);
        }

        // Serializer detection: `@Serializable` (from package:d_rocket
        // or its legacy alias package:d_serializer). Helper tolerates
        // either so a consumer can keep using the legacy package
        // during the migration period.
        if (hasSerializableAnnotation(cls)) {
          // Generic classes need explicit registration per
          // instantiation — skip them in the central registry.
          if (cls.typeParameters.isEmpty) {
            serializableClassesByFile
                .putIfAbsent(libPath, () => <String>{})
                .add(name);
          }
        }

        // REST client detection: `@RestClient` from
        // `package:d_rocket` (or its legacy alias
        // `package:d_rest`). Only abstract classes qualify
        // (concrete ones can't be `@RestClient` clients).
        if (hasRestClientAnnotation(cls) && cls.isAbstract) {
          restClientClassesByFile
              .putIfAbsent(libPath, () => <String>{})
              .add(name);
        }

        // ORM table detection: `@Table` from
        // `package:d_rocket`. The codegen cannot emit a
        // `static EntityMeta` for abstract types, so those
        // are skipped (mirrors the `record` codegen's own
        // abstract-class exclusion).
        if (hasRocketTableAnnotation(cls) && !cls.isAbstract) {
          ormTableClassesByFile
              .putIfAbsent(libPath, () => <String>{})
              .add(name);
        }

        // Realtime detection: `@WebSocketClient`
        // and `@SseClient` from `package:d_rocket`. Only
        // abstract classes qualify (the codegen emits the
        // concrete subclass).
        if (hasWebSocketClientAnnotation(cls) && cls.isAbstract) {
          webSocketClientClassesByFile
              .putIfAbsent(libPath, () => <String>{})
              .add(name);
        }
        if (hasSseClientAnnotation(cls) && cls.isAbstract) {
          sseClientClassesByFile
              .putIfAbsent(libPath, () => <String>{})
              .add(name);
        }
      }
    }

    // Deterministic output: sort file paths and the classes within.
    final List<String> allFiles = <String>{
      ...recordClassesByFile.keys,
      ...serializableClassesByFile.keys,
      ...restClientClassesByFile.keys,
      ...ormTableClassesByFile.keys,
      ...webSocketClientClassesByFile.keys,
      ...sseClientClassesByFile.keys,
    }.toList()
      ..sort();

    // ─── Emit the registry file ──────────────────────────────
    final StringBuffer out = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln('//')
      ..writeln('// Generated by d_rocket_builder:record_registry.')
      ..writeln('// Source: every `extends Record`, `@Serializable`,')
      ..writeln('// `@RestClient`, and `@Table` class in lib/**.dart.')
      ..writeln('//')
      ..writeln('// Call [initializeD] once at application startup:')
      ..writeln('//')
      ..writeln('//   import "d_rocket_registry.g.dart";')
      ..writeln('//   void main() {')
      ..writeln('//     initializeD();')
      ..writeln('//     runApp(const MyApp());')
      ..writeln('//   }')
      ..writeln()
      // Always import the d_rocket runtime, because the
      // `initializeD()` function calls `dRest.useDefaults()` to
      // bootstrap the REST layer . The runtime also
      // re-exports `Record`, `Serializer`, etc. so future
      // generated calls are also covered.
      ..writeln("import 'package:d_rocket/d_rocket.dart';");

    // Per-file imports (aliased so we can call the register fns
    // without polluting the user's namespace). Every file that
    // contains a managed class gets an import line.
    final List<String> importEntries = <String>[];
    for (final libPath in allFiles) {
      final importPath = _importPath(libPath);
      importEntries.add(importPath);
      out.writeln("import '$importPath' as _m${importEntries.length - 1};");
    }

    out
      ..writeln()
      ..writeln('bool _dRocketInitialized = false;')
      ..writeln()
      ..writeln('/// Initialize all d_rocket-managed classes in this')
      ..writeln('/// package. Call this once at application startup,')
      ..writeln('/// typically in `main()`.')
      ..writeln('///')
      ..writeln('/// Registers, in order:')
      ..writeln('/// 1. Field accessors for every `extends Record`')
      ..writeln('///    class (enables the debug-friendly `toString` and')
      ..writeln('///    the LINQ `MemberAccess` evaluator).')
      ..writeln('/// 2. `fromJson` / `toJson` pairs for every')
      ..writeln('///    `@Serializable` class (enables')
      ..writeln('///    `Serializer.fromJson<T>(...)` dispatch).')
      ..writeln('/// 3. `_<ClassName>.create` factories for every')
      ..writeln('///    `@RestClient` class (enables')
      ..writeln('///    `dRest.get<TodoApi>()` dispatch).')
      ..writeln('/// 4. `static EntityMeta entityMeta` for every')
      ..writeln('///    `@Table` class (enables')
      ..writeln('///    `DbSet<T>.add / SaveChanges()` SQL generation).')
      ..writeln('///')
      ..writeln('/// Idempotent: subsequent calls are no-ops.')
      ..writeln('void initializeD() {')
      ..writeln('  if (_dRocketInitialized) return;')
      ..writeln('  _dRocketInitialized = true;')
      ..writeln('  // Make sure the REST runtime is initialised before')
      ..writeln('  // any client factory tries to use it. Calling')
      ..writeln('  // `useDefaults` is a no-op if the consumer has')
      ..writeln('  // already configured `dRest` themselves.')
      ..writeln("  dRest.useDefaults();");

    // 1. Records first (so any `@Serializable` class that ALSO
    //    `extends Record` has its `Record` base class wired up
    //    before any serializer tries to construct an instance).
    for (int i = 0; i < importEntries.length; i++) {
      final libPath = allFiles[i];
      final Set<String>? records = recordClassesByFile[libPath];
      if (records == null || records.isEmpty) continue;
      for (final className in (records.toList()..sort())) {
        out.writeln('  _m$i.register${className}Record();');
      }
    }

    // 2. Serializers after.
    for (int i = 0; i < importEntries.length; i++) {
      final libPath = allFiles[i];
      final Set<String>? serializables = serializableClassesByFile[libPath];
      if (serializables == null || serializables.isEmpty) continue;
      for (final className in (serializables.toList()..sort())) {
        out.writeln('  _m$i.register${className}Serializer();');
      }
    }

    // 3. REST clients (so any `@Serializable` class that is
    //    also a body type for a `@RestClient` is registered
    //    before the client tries to decode the response).
    for (int i = 0; i < importEntries.length; i++) {
      final libPath = allFiles[i];
      final Set<String>? restClients = restClientClassesByFile[libPath];
      if (restClients == null || restClients.isEmpty) continue;
      for (final className in (restClients.toList()..sort())) {
        out.writeln('  _m$i.register${className}RestClient();');
      }
    }

    // 4. ORM tables last (so any `@Serializable` class that is
    //    also a `@Table` field type is registered before
    //    `DbSet<T>` reads its metadata).
    for (int i = 0; i < importEntries.length; i++) {
      final libPath = allFiles[i];
      final Set<String>? ormTables = ormTableClassesByFile[libPath];
      if (ormTables == null || ormTables.isEmpty) continue;
      for (final className in (ormTables.toList()..sort())) {
        out.writeln('  _m$i.register${className}EntityMeta();');
      }
    }

    // 5. WebSocket clients .
    for (int i = 0; i < importEntries.length; i++) {
      final libPath = allFiles[i];
      final Set<String>? webSocketClients =
          webSocketClientClassesByFile[libPath];
      if (webSocketClients == null || webSocketClients.isEmpty) continue;
      for (final className in (webSocketClients.toList()..sort())) {
        out.writeln('  _m$i.register${className}WebSocketClient();');
      }
    }

    // 6. SSE clients .
    for (int i = 0; i < importEntries.length; i++) {
      final libPath = allFiles[i];
      final Set<String>? sseClients = sseClientClassesByFile[libPath];
      if (sseClients == null || sseClients.isEmpty) continue;
      for (final className in (sseClients.toList()..sort())) {
        out.writeln('  _m$i.register${className}SseClient();');
      }
    }

    out.writeln('}');

    final AssetId output = AssetId(
      buildStep.inputId.package,
      'lib/d_rocket_registry.g.dart',
    );
    await buildStep.writeAsString(output, out.toString());
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns `true` if [cls] is a concrete subclass of `Record`
  /// (the base class in `package:d_rocket/d_rocket.dart`).
  bool _extendsRecord(ClassElement cls) {
    final superType = cls.supertype;
    if (superType == null) return false;
    final superElement = superType.element;
    if (superElement.displayName != 'Record') return false;
    // Confirm the base class is from d_rocket by checking the
    // source URI of the enclosing library. Avoids matching
    // user-defined classes also named "Record".
    final libSource = superElement.firstFragment.libraryFragment.source;
    final path = libSource.uri.path;
    if (!path.contains('d_rocket')) return false;
    return true;
  }

  /// Converts a library path into a relative import path **as seen
  /// from the registry file's location** (which is `lib/`).
  ///
  /// - `lib/foo/bar.dart`     → `foo/bar.dart`
  /// - `lib/example/baz.dart` → `example/baz.dart`
  String _importPath(String path) {
    if (path.startsWith('lib/')) {
      return path.substring(4);
    }
    return path;
  }
}
