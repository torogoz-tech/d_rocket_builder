/// Helpers for discovering `@Table` classes in a
/// `LibraryElement`.
///
/// Consumed by [RecordRegistryBuilder] (in
/// `d_rocket_builder/lib/src/record_registry_builder.dart`)
/// to detect which classes in the consumer's `lib/**.dart`
/// are `@Table` and therefore need a
/// `register[X]EntityMeta()` call emitted into the central
/// `initializeD()`.
library d_rocket_builder.orm.registry;

import 'package:analyzer/dart/element/element.dart';

/// Returns `true` if [cls] is annotated with `@Table`
/// from `package:d_rocket`.
bool hasRocketTableAnnotation(ClassElement cls) {
  for (final ElementAnnotation annotation in cls.metadata.annotations) {
    final String? displayName = annotation.element?.displayName;
    if (displayName != 'Table') continue;
    final Element? annotationElement = annotation.element;
    if (annotationElement == null) continue;
    final LibraryElement? lib = annotationElement.library;
    if (lib == null) continue;
    final String path = lib.uri.path;
    if (path.contains('d_rocket')) {
      return true;
    }
  }
  return false;
}

/// Returns the class names (sorted, deduplicated) of every
/// `@Table` class declared in the given [library].
///
/// Abstract classes are excluded (the codegen cannot emit
/// a `static EntityMeta` for an abstract type).
List<String> collectRocketTableClassNames(LibraryElement library) {
  final Set<String> names = <String>{};
  for (final ClassElement cls in library.classes) {
    if (!hasRocketTableAnnotation(cls)) continue;
    if (cls.isAbstract) continue;
    final String name = cls.displayName;
    if (name.isEmpty) continue;
    names.add(name);
  }
  final List<String> sorted = names.toList()..sort();
  return sorted;
}
