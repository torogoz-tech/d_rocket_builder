//: tests for the TPC codegen. The
// `@Table(inheritance: InheritanceStrategy.tpc,
// isAbstract: true)` annotation marks a TPC root that
// owns no table. The codegen sets `isAbstract: true`
// on the EntityMeta and skips the migration DDL.

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 5.2.4.1 — codegen TPC: annotation', () {
    test('@Table(isAbstract: true) marks a TPC root', () {
      const Table ann = Table(
        inheritance: InheritanceStrategy.tpc,
        isAbstract: true,
      );
      expect(ann.isAbstract, isTrue);
      expect(ann.inheritance, InheritanceStrategy.tpc);
    });

    test('@Table.tpc() is shorthand for TPC root', () {
      const Table ann = Table.tpc();
      expect(ann.isAbstract, isTrue);
      expect(ann.inheritance, InheritanceStrategy.tpc);
    });

    test('@Table default: isAbstract is false', () {
      const Table ann = Table();
      expect(ann.isAbstract, isFalse);
    });
  });

  group('Fase 5.2.4.1 — codegen TPC: codegen-emitted meta shape', () {
    test('a TPC root meta has tpc strategy + isAbstract: true', () {
      // Simulate the codegen's output for a TPC root.
      final EntityMeta root = EntityMeta(
        tableName: 'animals',  // never used at runtime
        columns: <ColumnMeta>[],
        insertableColumns: <ColumnMeta>[],
        updatableColumns: <ColumnMeta>[],
        primaryKey: ColumnMeta(
          sqlName: 'id',
          dartField: 'id',
          dartType: int,
          isPrimaryKey: true,
        ),
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
        //  (codegen-emitted):
        inheritanceStrategy: InheritanceStrategy.tpc,
        isAbstract: true,
      );
      expect(root.inheritanceStrategy, InheritanceStrategy.tpc);
      expect(root.isAbstract, isTrue);
    });

    test('a TPC leaf meta has tpc strategy + isAbstract: false', () {
      // The leaf declares all the columns (root's +
      // leaf's) explicitly in the codegen. No special
      // treatment needed beyond `isAbstract: false`.
      final EntityMeta leaf = EntityMeta(
        tableName: 'dogs',
        columns: <ColumnMeta>[
          ColumnMeta(
            sqlName: 'id',
            dartField: 'id',
            dartType: int,
            isPrimaryKey: true,
          ),
          ColumnMeta(
            sqlName: 'name',
            dartField: 'name',
            dartType: String,
          ),
          ColumnMeta(
            sqlName: 'breed',
            dartField: 'breed',
            dartType: String,
            nullable: true,
          ),
        ],
        insertableColumns: <ColumnMeta>[
          ColumnMeta(
            sqlName: 'name',
            dartField: 'name',
            dartType: String,
          ),
          ColumnMeta(
            sqlName: 'breed',
            dartField: 'breed',
            dartType: String,
            nullable: true,
          ),
        ],
        updatableColumns: <ColumnMeta>[
          ColumnMeta(
            sqlName: 'name',
            dartField: 'name',
            dartType: String,
          ),
          ColumnMeta(
            sqlName: 'breed',
            dartField: 'breed',
            dartType: String,
            nullable: true,
          ),
        ],
        primaryKey: ColumnMeta(
          sqlName: 'id',
          dartField: 'id',
          dartType: int,
          isPrimaryKey: true,
        ),
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
        inheritanceStrategy: InheritanceStrategy.tpc,
        isAbstract: false,
      );
      expect(leaf.inheritanceStrategy, InheritanceStrategy.tpc);
      expect(leaf.isAbstract, isFalse);
    });
  });

  group('Fase 5.2.4.1 — codegen TPC: copyWith preserves isAbstract', () {
    test('a TPC root meta can be rebuilt via copyWith', () {
      final ColumnMeta idCol = ColumnMeta(
        sqlName: 'id',
        dartField: 'id',
        dartType: int,
        isPrimaryKey: true,
      );
      final EntityMeta root = EntityMeta(
        tableName: 'animals',
        columns: <ColumnMeta>[idCol],
        insertableColumns: <ColumnMeta>[],
        updatableColumns: <ColumnMeta>[],
        primaryKey: idCol,
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
        inheritanceStrategy: InheritanceStrategy.tpc,
        isAbstract: true,
      );
      final EntityMeta copy = root.copyWith(isAbstract: false);
      expect(copy.isAbstract, isFalse);
      expect(copy.inheritanceStrategy, InheritanceStrategy.tpc);
    });
  });

  group('Fase 5.2.4.1 — codegen TPC: cross-strategy interaction', () {
    test('TPH and TPC and TPT are all distinct', () {
      expect(InheritanceStrategy.tph,
          isNot(InheritanceStrategy.tpt));
      expect(InheritanceStrategy.tpt,
          isNot(InheritanceStrategy.tpc));
      expect(InheritanceStrategy.tph,
          isNot(InheritanceStrategy.tpc));
    });

    test('a TPH child has isAbstract: false (TPH never has abstract roots)',
        () {
      final ColumnMeta idCol = ColumnMeta(
        sqlName: 'id',
        dartField: 'id',
        dartType: int,
        isPrimaryKey: true,
      );
      final EntityMeta child = EntityMeta(
        tableName: 'animals',
        columns: <ColumnMeta>[idCol],
        insertableColumns: <ColumnMeta>[],
        updatableColumns: <ColumnMeta>[],
        primaryKey: idCol,
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
        inheritanceStrategy: InheritanceStrategy.tph,
        discriminatorValue: 'dog',
      );
      expect(child.isAbstract, isFalse);
    });
  });
}
