import 'package:d_rocket_builder/src/orm/type_support.dart';
import 'package:test/test.dart';

void main() {
  group('ORM generated type support', () {
    test('nullable type names can be emitted as Type literals', () {
      expect(nonNullableTypeName('String?'), 'String');
      expect(nonNullableTypeName('DateTime?'), 'DateTime');
      expect(nonNullableTypeName('double'), 'double');
    });

    test('nullable String keeps exactly one nullable suffix', () {
      final String expression = emitOrmRowValue(
        rawExpression: "r['description']",
        typeName: 'String?',
        fieldName: 'description',
        nullable: true,
      );

      expect(expression, contains('as String'));
      expect(expression, isNot(contains('String??')));
      expect(expression, contains('? null :'));
    });

    test('nullable DateTime accepts SQLite text and null', () {
      final String expression = emitOrmRowValue(
        rawExpression: "r['timestamp']",
        typeName: 'DateTime?',
        fieldName: 'timestamp',
        nullable: true,
      );

      expect(expression, contains('DateTime.parse'));
      expect(expression, contains('? null :'));
      expect(expression, isNot(contains('null as DateTime')));
    });

    test('non-nullable DateTime rejects a NULL row explicitly', () {
      final String expression = emitOrmRowValue(
        rawExpression: "r['timestamp']",
        typeName: 'DateTime',
        fieldName: 'timestamp',
        nullable: false,
      );

      expect(expression, contains('Column timestamp is NULL'));
      expect(expression, contains('DateTime.parse'));
      expect(expression, isNot(contains('null as DateTime')));
    });

    test('decimal-compatible double values are normalised from SQLite num', () {
      final String expression = emitOrmRowValue(
        rawExpression: "r['amount']",
        typeName: 'double?',
        fieldName: 'amount',
        nullable: true,
      );

      expect(expression, contains("(r['amount'] as num).toDouble()"));
      expect(expression, contains('? null :'));
    });

    test('DateTime is converted to SQLite text when writing', () {
      expect(
        emitOrmSqlValue(
          fieldExpression: 'entity.timestamp',
          typeName: 'DateTime',
          nullable: false,
        ),
        '(entity.timestamp as DateTime).toIso8601String()',
      );
      expect(
        emitOrmSqlValue(
          fieldExpression: 'entity.timestamp',
          typeName: 'DateTime?',
          nullable: true,
        ),
        'entity.timestamp == null ? null : (entity.timestamp as DateTime).toIso8601String()',
      );
    });

    test('exact decimal value objects are rejected without a contract', () {
      expect(
          decimalConverterError('Invoice.amount', 'Decimal'),
          contains(
            'explicit converter',
          ));
    });

    test('enum values are written to SQLite as their names', () {
      expect(
        emitOrmSqlValue(
          fieldExpression: 'entity.status',
          typeName: 'LocationStatus',
          nullable: false,
          isEnum: true,
        ),
        '(entity.status).name',
      );
      expect(
        emitOrmSqlValue(
          fieldExpression: 'entity.status',
          typeName: 'LocationStatus?',
          nullable: true,
          isEnum: true,
        ),
        'entity.status == null ? null : (entity.status)!.name',
      );
    });

    test('SQLite enum text values are decoded by enum name', () {
      final String expression = emitOrmRowValue(
        rawExpression: "r['status']",
        typeName: 'LocationStatus',
        fieldName: 'status',
        nullable: false,
        isEnum: true,
      );

      expect(expression, contains('LocationStatus.values.firstWhere'));
      expect(expression, contains("candidate.name == (r['status'] as String)"));
      expect(expression, contains('Column status is NULL'));
    });

    test('enum decoding can use an explicit unknown-value fallback', () {
      final String expression = emitOrmRowValue(
        rawExpression: "r['status']",
        typeName: 'LocationStatus',
        fieldName: 'status',
        nullable: false,
        isEnum: true,
        unknownEnumValue: 'unavailable',
      );

      expect(
        expression,
        contains('LocationStatus.values.byName("unavailable")'),
      );
      expect(expression, isNot(contains('Unknown enum value')));
    });
  });
}
