import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import 'contract_type.dart';

/// Discovers concrete generic serializer shapes from generated contracts.
class ContractTypeCollector {
  const ContractTypeCollector._();

  /// Deduplicates and sorts already normalized contract shapes.
  static List<ContractType> unique(Iterable<ContractType> types) {
    final List<ContractType> result = types.toSet().toList()
      ..sort((ContractType left, ContractType right) {
        final int byName = left.displayName.compareTo(right.displayName);
        if (byName != 0) return byName;
        return left.libraryPath.compareTo(right.libraryPath);
      });
    return result;
  }

  /// Collects generic shapes returned by REST or realtime client methods.
  ///
  /// [genericLibraryPaths] contains only consumer-defined generic
  /// `@Serializable` classes. Core collection types such as `List` are
  /// traversed but are never emitted as registry calls.
  static List<ContractType> fromClients(
    Iterable<ClassElement> clients, {
    required Map<String, String> genericLibraryPaths,
  }) {
    final List<ContractType> found = <ContractType>[];
    for (final ClassElement client in clients) {
      for (final MethodElement method in client.methods) {
        _collect(
          _unwrapFuture(method.returnType),
          genericLibraryPaths: genericLibraryPaths,
          found: found,
        );
      }
    }
    return unique(found);
  }

  static DartType _unwrapFuture(DartType type) {
    if (type is InterfaceType &&
        (type.element.name == 'Future' || type.element.name == 'FutureOr') &&
        type.typeArguments.isNotEmpty) {
      return type.typeArguments.first;
    }
    return type;
  }

  static void _collect(
    DartType type, {
    required Map<String, String> genericLibraryPaths,
    required List<ContractType> found,
  }) {
    if (type is! InterfaceType) return;

    final String className = type.element.name ?? '';
    final String? libraryPath = genericLibraryPaths[className];
    if (libraryPath != null && type.typeArguments.isNotEmpty) {
      found.add(
        ContractType.fromDartType(
          type,
          libraryPathFor: (String name, DartType _) =>
              genericLibraryPaths[name] ??
              (_coreCollectionNames.contains(name) ? 'dart:core' : libraryPath),
        ),
      );
    }

    for (final DartType argument in type.typeArguments) {
      _collect(
        argument,
        genericLibraryPaths: genericLibraryPaths,
        found: found,
      );
    }
  }

  static const Set<String> _coreCollectionNames = <String>{
    'Iterable',
    'List',
    'Map',
    'Set',
  };
}
