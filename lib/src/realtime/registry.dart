//: helpers for discovering
// `@WebSocketClient` and `@SseClient` classes in a
// `LibraryElement`. Consumed by
// [RecordRegistryBuilder] to detect which classes
// in the consumer's `lib/**.dart` files are
// realtime clients and therefore need a
// `register<X>WebSocketClient()` /
// `register<X>SseClient()` call emitted into the
// central `initializeD()`.
//
// Detection is structural: inspects the
// annotation's `enclosingElement.displayName` and
// the URI of its declaring library, so it
// correctly distinguishes `@WebSocketClient` /
// `@SseClient` from `package:d_rocket` versus any
// user-defined class with the same name.

library d_rocket_builder.realtime.registry;

import 'package:analyzer/dart/element/element.dart';

/// Returns `true` if [cls] is annotated with
/// `@WebSocketClient` from `package:d_rocket`.
bool hasWebSocketClientAnnotation(ClassElement cls) {
  for (final ElementAnnotation annotation in cls.metadata.annotations) {
    final String? displayName = annotation.element?.displayName;
    if (displayName != 'WebSocketClient') continue;
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

/// Returns `true` if [cls] is annotated with
/// `@SseClient` from `package:d_rocket`.
bool hasSseClientAnnotation(ClassElement cls) {
  for (final ElementAnnotation annotation in cls.metadata.annotations) {
    final String? displayName = annotation.element?.displayName;
    if (displayName != 'SseClient') continue;
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

/// Returns the class names (sorted, deduplicated)
/// of every `@WebSocketClient` class declared in
/// the given [library].
List<String> collectWebSocketClientClassNames(LibraryElement library) {
  final Set<String> names = <String>{};
  for (final ClassElement cls in library.classes) {
    if (!hasWebSocketClientAnnotation(cls)) continue;
    if (!cls.isAbstract) continue;
    final String name = cls.displayName;
    if (name.isEmpty) continue;
    names.add(name);
  }
  final List<String> sorted = names.toList()..sort();
  return sorted;
}

/// Returns the class names (sorted, deduplicated)
/// of every `@SseClient` class declared in the
/// given [library].
List<String> collectSseClientClassNames(LibraryElement library) {
  final Set<String> names = <String>{};
  for (final ClassElement cls in library.classes) {
    if (!hasSseClientAnnotation(cls)) continue;
    if (!cls.isAbstract) continue;
    final String name = cls.displayName;
    if (name.isEmpty) continue;
    names.add(name);
  }
  final List<String> sorted = names.toList()..sort();
  return sorted;
}
