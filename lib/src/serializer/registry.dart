/// Helpers for discovering `@Serializable` classes in a
/// `LibraryElement`.
///
/// This is consumed by [RecordRegistryBuilder] (in
/// `d_rocket_builder/lib/src/record_registry_builder.dart`) to detect
/// which classes in the consumer's `lib/**.dart` files are
/// `@Serializable` and therefore need a
/// `register[ClassName]Serializer()` call emitted into the central
/// `initializeD()`.
///
/// It is also used by the unit tests in `test/` to validate the
/// discovery logic in isolation.
library d_rocket_builder.serializer.registry;

import 'package:analyzer/dart/element/element.dart';

/// Returns `true` if [cls] is annotated with `@Serializable` from
/// `package:d_rocket/d_rocket.dart`.
///
/// The check is structural: it inspects the annotation's
/// `enclosingElement.displayName` and the URI of its declaring
/// library, so it correctly distinguishes `@Serializable` from
/// `package:d_rocket` versus any user-defined class with the same
/// name.
bool hasSerializableAnnotation(ClassElement cls) {
  for (final ElementAnnotation annotation in cls.metadata.annotations) {
    final String? displayName = annotation.element?.displayName;
    if (displayName != 'Serializable') continue;
    // Confirm the annotation is the one re-exported by d_rocket
    // (which originally came from d_serializer 1.3.0). We check
    // the library URI of the annotation's declaring class.
    final Element? annotationElement = annotation.element;
    if (annotationElement == null) continue;
    final LibraryElement? lib = annotationElement.library;
    if (lib == null) continue;
    final String path = lib.uri.path;
    if (path.contains('d_rocket') || path.contains('d_serializer')) {
      return true;
    }
  }
  return false;
}

/// Returns the class names (sorted, deduplicated) of every
/// `@Serializable` class declared in the given [library].
///
/// Generic classes (`class Foo<T>`) are skipped here — the
/// codegen for generic classes requires explicit `register<X>Foo<T>()`
/// calls from the user because type parameters are erased at
/// runtime, so emitting an automatic registration would produce
/// a `Serializer.register[Foo[T]]` that always fails at runtime.
List<String> collectSerializableClassNames(LibraryElement library) {
  final Set<String> names = <String>{};
  for (final ClassElement cls in library.classes) {
    if (!hasSerializableAnnotation(cls)) continue;
    if (cls.typeParameters.isNotEmpty) continue;
    final String name = cls.displayName;
    if (name.isEmpty) continue;
    names.add(name);
  }
  final List<String> sorted = names.toList()..sort();
  return sorted;
}
