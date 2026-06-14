/// The generator that walks `extends Record` classes and emits a
/// registration snippet into a `part` file.
///
/// **No annotation required.** The generator discovers any class
/// that `extends Record` (in `package:d_rocket/d_rocket.dart`) and
/// emits, per class:
///
/// - A `_<ClassName>Init` class whose constructor registers the
///   field accessors with d_rocket's internal registry.
/// - A `final _$_<ClassName>Init` lazy top-level initializer.
/// - A public `void register<ClassName>Record()` function that
///   forces evaluation of the initializer (called by the central
///   `d_rocket_registry.g.dart` `initializeD()`).
///
/// The central registry is produced by the companion
/// [RecordRegistryBuilder] (a `LibraryBuilder`).
library d_rocket_builder.record_generator;

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

/// Lowercases the first character of [s].
///
/// Used to derive a `lowerCamelCase` identifier from a
/// `UpperCamelCase` class name (e.g. `Author` -> `author`)
/// without touching the rest of the word.
String _lcFirst(String s) =>
    s.isEmpty ? s : '${s[0].toLowerCase()}${s.substring(1)}';

/// Generates registration snippets for `Record` subclasses.
///
/// Discovers classes by `extends Record` (no annotation needed).
class RecordGenerator extends Generator {
  @override
  String? generate(LibraryReader library, BuildStep buildStep) {
    final out = StringBuffer();
    bool any = false;

    for (final cls in library.classes) {
      if (!_extendsRecord(cls)) continue;

      final className = cls.displayName;
      final fields = cls.fields
          .where((f) => !f.isStatic && !f.isPrivate)
          .toList();

      if (fields.isEmpty) continue;
      any = true;

      // Build the field assignment statements. Using a sequence of
      // statements (instead of a map literal) avoids the dart
      // formatter adding trailing commas that double-up with our
      // explicit comma separators.
      final assignments = StringBuffer();
      for (final f in fields) {
        final name = f.displayName;
        if (assignments.isNotEmpty) assignments.write('\n      ');
        assignments.write("fields['$name'] = (a) => a.$name;");
      }

      out.write('''
class _\$${className}Init {
  _\$${className}Init() {
    final fields = <String, Object? Function($className)>{};
      $assignments
    Record.register<$className>(fields);
  }
}

final _${_lcFirst(className)}Init = _\$${className}Init();

/// Registers the [${className}] field accessors with d_rocket's
/// internal registry. Called by `d_rocket_registry.g.dart`'s
/// `initializeD()` at application startup.
void register${className}Record() {
  _${_lcFirst(className)}Init;
}

''');
    }

    if (!any) return null;
    return out.toString();
  }

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
}
