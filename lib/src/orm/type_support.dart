import 'package:analyzer/dart/element/type.dart' show DartType;

/// Returns the source-level type name while preserving nullability.
String dartTypeName(DartType type) => type.toString();

/// Returns a type name suitable for a Dart `Type` literal.
String nonNullableTypeName(String typeName) => typeName.endsWith('?')
    ? typeName.substring(0, typeName.length - 1)
    : typeName;

/// Emits the value conversion used by generated ORM `fromRow` closures.
String emitOrmRowValue({
  required String rawExpression,
  required String typeName,
  required String fieldName,
  required bool nullable,
}) {
  final String baseTypeName = nonNullableTypeName(typeName);
  final String dateExpression =
      '($rawExpression is DateTime ? $rawExpression : '
      'DateTime.parse($rawExpression as String))';

  final String valueExpression = switch (baseTypeName) {
    'DateTime' => dateExpression,
    'int' => '($rawExpression as num).toInt()',
    'double' => '($rawExpression as num).toDouble()',
    'num' => '$rawExpression as num',
    'bool' => '$rawExpression as bool',
    _ => '$rawExpression as $baseTypeName',
  };

  if (nullable) {
    return '($rawExpression == null ? null : $valueExpression) as $typeName';
  }

  final String? legacyFallback = switch (baseTypeName) {
    'String' => "''",
    'int' => '0',
    'double' => '0.0',
    'bool' => 'false',
    _ => null,
  };
  if (legacyFallback != null) {
    return '($rawExpression == null ? $legacyFallback : $valueExpression) '
        'as $baseTypeName';
  }

  return '($rawExpression == null '
      '? throw StateError(\'Column $fieldName is NULL but the Dart field is '
      'non-nullable\') '
      ': $valueExpression) as $baseTypeName';
}

/// Emits the value conversion used by generated ORM `readColumn` closures.
String emitOrmSqlValue({
  required String fieldExpression,
  required String typeName,
  required bool nullable,
}) {
  final String baseTypeName = nonNullableTypeName(typeName);
  if (baseTypeName != 'DateTime') return fieldExpression;
  final String converted = '($fieldExpression as DateTime).toIso8601String()';
  return nullable ? '$fieldExpression == null ? null : $converted' : converted;
}
