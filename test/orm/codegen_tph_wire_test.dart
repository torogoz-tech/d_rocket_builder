//: tests for the `wire<Root>EntityMeta`
// helper emitted by the codegen when a TPH root has
// the `children: {...}` map.

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 5.2.2 — codegen TPH: wire<Root>EntityMeta() helper', () {
    test('@Table(children: {...}) accepts a Map<String, String>', () {
      const Table ann = Table(
        inheritance: InheritanceStrategy.tph,
        children: <String, String>{'dog': 'Dog', 'cat': 'Cat'},
      );
      expect(ann.inheritance, InheritanceStrategy.tph);
      expect(ann.children, isNotNull);
      expect(ann.children!.keys, containsAll(<String>['dog', 'cat']));
      expect(ann.children!['dog'], 'Dog');
      expect(ann.children!['cat'], 'Cat');
    });

    test('@Table(children: {}) is a valid TPH root (no children yet)',
        () {
      const Table ann = Table(
        inheritance: InheritanceStrategy.tph,
        children: <String, String>{},
      );
      expect(ann.inheritance, InheritanceStrategy.tph);
      expect(ann.children, isNotNull);
      expect(ann.children!.isEmpty, isTrue);
    });

    test('@Table.tph(...) is a shorthand for the TPH root case', () {
      const Table ann = Table.tph(
        children: <String, String>{'dog': 'Dog', 'cat': 'Cat'},
      );
      expect(ann.inheritance, InheritanceStrategy.tph);
      expect(ann.discriminator, isNull,
          reason: 'the .tph constructor sets `inheritance`, not `discriminator`');
      expect(ann.children, isNotNull);
      expect(ann.children!.keys, containsAll(<String>['dog', 'cat']));
    });

    test('the @Inheritance strategy is exposed (re-exported from entity_meta)',
        () {
      //: the @Inheritance enum is
      // re-exported from `entity_meta.dart` so the
      // user can write `InheritanceStrategy.tph`
      // directly.
      expect(InheritanceStrategy.values,
          containsAll(<InheritanceStrategy>[InheritanceStrategy.none, InheritanceStrategy.tph]));
    });

    test('default @Table is non-TPH (backwards compatible)', () {
      const Table ann = Table();
      expect(ann.inheritance, InheritanceStrategy.none);
      expect(ann.discriminator, isNull);
      expect(ann.children, isNull);
    });
  });

  group('Fase 5.2.2 — codegen TPH: end-to-end wire semantics', () {
    test(
        'a hand-built wire<Root>EntityMeta() returns the meta with subclassMetas set',
        () {
      // Simulate the codegen's output: a root meta
      // (subclassMetas: <empty>) + a child meta. The
      // wire<Root>EntityMeta() helper builds a new
      // meta with subclassMetas populated.
      final ColumnMeta idCol = ColumnMeta(
        sqlName: 'id',
        dartField: 'id',
        dartType: int,
        isPrimaryKey: true,
        isAutoIncrement: true,
      );
      final ColumnMeta nameCol = ColumnMeta(
        sqlName: 'name',
        dartField: 'name',
        dartType: String,
      );
      final ColumnMeta kindCol = ColumnMeta(
        sqlName: 'kind',
        dartField: 'kind',
        dartType: String,
      );
      final EntityMeta dog = EntityMeta(
        tableName: 'animals',
        columns: <ColumnMeta>[idCol, nameCol, kindCol],
        insertableColumns: <ColumnMeta>[nameCol, kindCol],
        updatableColumns: <ColumnMeta>[nameCol, kindCol],
        primaryKey: idCol,
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
        inheritanceStrategy: InheritanceStrategy.tph,
        discriminatorValue: 'dog',
        discriminatorColumn: kindCol,
      );
      final EntityMeta cat = EntityMeta(
        tableName: 'animals',
        columns: <ColumnMeta>[idCol, nameCol, kindCol],
        insertableColumns: <ColumnMeta>[nameCol, kindCol],
        updatableColumns: <ColumnMeta>[nameCol, kindCol],
        primaryKey: idCol,
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
        inheritanceStrategy: InheritanceStrategy.tph,
        discriminatorValue: 'cat',
        discriminatorColumn: kindCol,
      );
      final EntityMeta animal = EntityMeta(
        tableName: 'animals',
        columns: <ColumnMeta>[idCol, nameCol, kindCol],
        insertableColumns: <ColumnMeta>[nameCol, kindCol],
        updatableColumns: <ColumnMeta>[nameCol, kindCol],
        primaryKey: idCol,
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
        inheritanceStrategy: InheritanceStrategy.tph,
        discriminatorColumn: kindCol,
        //: the codegen now
        // **automatically** populates this map via
        // `wire<Root>EntityMeta()` — no manual
        // `initializeD()` wiring needed.
        subclassMetas: <String, EntityMeta>{'dog': dog, 'cat': cat},
      );
      // The wire<Root>EntityMeta() helper does this:
      //   return Animal.entityMeta.copyWith(
      //     subclassMetas: <String, EntityMeta>{
      //       'dog': Dog.entityMeta,
      //       'cat': Cat.entityMeta,
      //     },
      //   );
      // For this test we already have the wired
      // meta — verify the resolution.
      expect(animal.resolveForDiscriminator('dog'), same(dog));
      expect(animal.resolveForDiscriminator('cat'), same(cat));
    });

    test('copyWith preserves the discriminatorColumn and other fields', () {
      // The wire<Root>EntityMeta() helper uses
      // copyWith(subclassMetas: ...) — make sure
      // copyWith doesn't lose the other TPH fields.
      final ColumnMeta idCol = ColumnMeta(
        sqlName: 'id',
        dartField: 'id',
        dartType: int,
        isPrimaryKey: true,
      );
      final ColumnMeta kindCol = ColumnMeta(
        sqlName: 'kind',
        dartField: 'kind',
        dartType: String,
      );
      final EntityMeta child = EntityMeta(
        tableName: 'animals',
        columns: <ColumnMeta>[idCol, kindCol],
        insertableColumns: <ColumnMeta>[kindCol],
        updatableColumns: <ColumnMeta>[kindCol],
        primaryKey: idCol,
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
        inheritanceStrategy: InheritanceStrategy.tph,
        discriminatorValue: 'dog',
      );
      final EntityMeta root = EntityMeta(
        tableName: 'animals',
        columns: <ColumnMeta>[idCol, kindCol],
        insertableColumns: <ColumnMeta>[kindCol],
        updatableColumns: <ColumnMeta>[kindCol],
        primaryKey: idCol,
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
        inheritanceStrategy: InheritanceStrategy.tph,
        discriminatorColumn: kindCol,
        subclassMetas: <String, EntityMeta>{},
      );
      final EntityMeta wired = root.copyWith(
        subclassMetas: <String, EntityMeta>{'dog': child},
      );
      // The discriminatorColumn is preserved.
      expect(wired.discriminatorColumn, same(kindCol));
      // The inheritance strategy is preserved.
      expect(wired.inheritanceStrategy, InheritanceStrategy.tph);
      // The subclassMetas is set.
      expect(wired.subclassMetas!['dog'], same(child));
    });
  });

  group('Fase 5.2.2 — codegen TPH: backwards compat with Fase 5.2.1', () {
    test('@Table(discriminator: "root") still works (Fase 5.2.1 form)',
        () {
      const Table ann = Table(discriminator: 'root');
      expect(ann.discriminator, 'root');
      expect(ann.inheritance, InheritanceStrategy.none,
          reason: 'discriminator is the Fase 5.2.1 form — '
              'inheritance defaults to none unless the user '
              'passes it explicitly');
    });
  });
}
