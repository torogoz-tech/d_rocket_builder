import 'package:analyzer/dart/element/type.dart';

/// A normalized concrete type shape used by generated contract registries.
class ContractType {
  const ContractType._({
    required this.className,
    required this.typeArguments,
    required this.libraryPath,
  });

  /// Creates a non-generic contract type.
  const ContractType.named(
    String name, {
    required String libraryPath,
  }) : this._(
          className: name,
          typeArguments: const <ContractType>[],
          libraryPath: libraryPath,
        );

  /// Creates a contract type with concrete type arguments.
  const ContractType.generic(
    String name,
    List<ContractType> arguments, {
    required String libraryPath,
  }) : this._(
          className: name,
          typeArguments: arguments,
          libraryPath: libraryPath,
        );

  /// Creates a normalized shape from an analyzer type.
  factory ContractType.fromDartType(
    DartType type, {
    required String Function(String className, DartType type) libraryPathFor,
  }) {
    final DartType normalized = type;

    if (normalized is InterfaceType) {
      final String className = normalized.element.name ??
          normalized.getDisplayString();
      final String libraryPath = libraryPathFor(className, normalized);
      final List<ContractType> arguments = normalized.typeArguments
          .map(
            (DartType argument) => ContractType.fromDartType(
              argument,
              libraryPathFor: libraryPathFor,
            ),
          )
          .toList(growable: false);
      return ContractType._(
        className: className,
        typeArguments: arguments,
        libraryPath: libraryPath,
      );
    }

    return ContractType.named(
      normalized.getDisplayString(),
      libraryPath: '',
    );
  }

  /// The declared name without generic arguments.
  final String className;

  /// Concrete arguments in declaration order.
  final List<ContractType> typeArguments;

  /// Consumer source file that declares [className].
  final String libraryPath;

  /// Dart source spelling of this concrete shape.
  String get displayName => typeArguments.isEmpty
      ? className
      : '$className<${typeArguments.map((ContractType type) => type.displayName).join(', ')}>';

  /// Whether this shape can be registered as a concrete generic instance.
  bool get isGenericInstance => typeArguments.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is ContractType &&
      other.libraryPath == libraryPath &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(libraryPath, displayName);
}
