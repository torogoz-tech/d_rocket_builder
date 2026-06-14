/// Helpers for discovering `@RestClient` classes in a
/// `LibraryElement`.
///
/// Consumed by [RecordRegistryBuilder] (in
/// `d_rocket_builder/lib/src/record_registry_builder.dart`) to detect
/// which classes in the consumer's `lib/**.dart` files are
/// `@RestClient` and therefore need a `register<X>RestClient()` call
/// emitted into the central `initializeD()`.
///
/// The detection is structural: it inspects the annotation's
/// `enclosingElement.displayName` and the URI of its declaring
/// library, so it correctly distinguishes `@RestClient` from
/// `package:d_rocket` versus any user-defined class with the same
/// name. The legacy `package:d_rest` annotation is also accepted so
/// a consumer can migrate incrementally.
library d_rocket_builder.rest.registry;

import 'package:analyzer/dart/element/element.dart';

/// Returns `true` if [cls] is annotated with `@RestClient` from
/// `package:d_rocket` (or the legacy `package:d_rest`).
bool hasRestClientAnnotation(ClassElement cls) {
  for (final ElementAnnotation annotation in cls.metadata.annotations) {
    final String? displayName = annotation.element?.displayName;
    if (displayName != 'RestClient') continue;
    final Element? annotationElement = annotation.element;
    if (annotationElement == null) continue;
    final LibraryElement? lib = annotationElement.library;
    if (lib == null) continue;
    final String path = lib.uri.path;
    if (path.contains('d_rocket') || path.contains('d_rest')) {
      return true;
    }
  }
  return false;
}

/// Returns the class names (sorted, deduplicated) of every
/// `@RestClient` class declared in the given [library].
List<String> collectRestClientClassNames(LibraryElement library) {
  final Set<String> names = <String>{};
  for (final ClassElement cls in library.classes) {
    if (!hasRestClientAnnotation(cls)) continue;
    if (!cls.isAbstract) continue;
    final String name = cls.displayName;
    if (name.isEmpty) continue;
    names.add(name);
  }
  final List<String> sorted = names.toList()..sort();
  return sorted;
}
