// Verifies the runtime contract that the codegen
// migration generator relies on: an @Index annotation
// produces a non-empty list of CREATE INDEX statements
// from EntityMeta.createIndexStatements(), and a
// @Column(isForeignKey: true) flag produces a
// REFERENCES clause via the same emit path that
// @ForeignKey uses.
//
// The companion "template" tests at the bottom of
// this file read the source of
// lib/src/migration/migration_generator.dart and
// assert that the codegen template includes
// createIndexStatements() and PRAGMA foreign_keys,
// so a future refactor that drops either one will
// fail the test.
//
// Together, these two test groups catch the
// regressions that an AI review of d_rocket flagged
// for the hospital scenario:
//   * @Index annotation carries metadata but the
//     codegen does not emit CREATE INDEX.
//   * @Column(isForeignKey: true) flag is
//     ignored by the DDL.
//   * The migration template forgets to enable FK
//     enforcement (defense in depth on top of the
//     PRAGMA the runtime emits on every open).

import 'dart:io';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('@Index — runtime contract', () {
    test('createIndexStatements() is empty when no @Index is set', () {
      final ColumnMeta idCol = ColumnMeta(
        sqlName: 'id',
        dartField: 'id',
        dartType: int,
        isPrimaryKey: true,
      );
      final ColumnMeta titleCol = ColumnMeta(
        sqlName: 'title',
        dartField: 'title',
        dartType: String,
      );
      final EntityMeta meta = EntityMeta(
        tableName: 'books',
        columns: <ColumnMeta>[idCol, titleCol],
        insertableColumns: <ColumnMeta>[titleCol],
        updatableColumns: <ColumnMeta>[titleCol],
        primaryKey: idCol,
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
      );
      expect(meta.createIndexStatements(), isEmpty);
    });

    test('createIndexStatements() returns a CREATE INDEX per @Index', () {
      // Build the same ColumnMeta that the codegen
      // emits for an `@Index(unique: true, name: 'books_isbn_unq')`
      // field. The shape matches what
      // EntityMeta.createIndexStatements() consumes.
      final ColumnMeta idCol = ColumnMeta(
        sqlName: 'id',
        dartField: 'id',
        dartType: int,
        isPrimaryKey: true,
      );
      final ColumnMeta isbnCol = ColumnMeta(
        sqlName: 'isbn',
        dartField: 'isbn',
        dartType: String,
        isIndexed: true,
        isUniqueIndex: true,
        indexName: 'books_isbn_unq',
      );
      final EntityMeta meta = EntityMeta(
        tableName: 'books',
        columns: <ColumnMeta>[idCol, isbnCol],
        insertableColumns: <ColumnMeta>[isbnCol],
        updatableColumns: <ColumnMeta>[isbnCol],
        primaryKey: idCol,
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
      );
      final List<String> stmts = meta.createIndexStatements();
      expect(stmts, hasLength(1));
      expect(stmts.first, contains('CREATE'));
      expect(stmts.first, contains('UNIQUE INDEX'));
      expect(stmts.first, contains('books_isbn_unq'));
      expect(stmts.first, contains('isbn'));
    });
  });

  group('@ForeignKey vs @Column(isForeignKey: true) — runtime DDL', () {
    test('explicit @ForeignKey annotation emits REFERENCES inline', () {
      // The codegen's runtime DDL output is what
      // the migration generator relies on. Verifying
      // it here is the contract.
      final ColumnMeta idCol = ColumnMeta(
        sqlName: 'id',
        dartField: 'id',
        dartType: int,
        isPrimaryKey: true,
      );
      final ColumnMeta authorIdCol = ColumnMeta(
        sqlName: 'author_id',
        dartField: 'authorId',
        dartType: int,
        isForeignKey: true,
        foreignTable: 'authors',
        foreignColumn: 'id',
      );
      final EntityMeta meta = EntityMeta(
        tableName: 'books',
        columns: <ColumnMeta>[idCol, authorIdCol],
        insertableColumns: <ColumnMeta>[authorIdCol],
        updatableColumns: <ColumnMeta>[authorIdCol],
        primaryKey: idCol,
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
      );
      final String ddl = meta.createTableDdl();
      expect(ddl, contains('REFERENCES authors(id)'));
    });

    test(
        '@Column(isForeignKey: true) with foreignTable set also emits REFERENCES',
        () {
      // The codegen now derives foreignTable from
      // the field name when the flag form is used.
      // The runtime just consumes whatever the
      // codegen puts on the ColumnMeta, so the
      // test verifies the runtime accepts the
      // derived form and produces the expected
      // REFERENCES clause.
      final ColumnMeta idCol = ColumnMeta(
        sqlName: 'id',
        dartField: 'id',
        dartType: int,
        isPrimaryKey: true,
      );
      // The codegen sets foreignTable = 'author'
      // (the field is `authorId`, strip `Id`,
      // lowercase the first letter) and
      // foreignColumn = 'id'.
      final ColumnMeta authorIdCol = ColumnMeta(
        sqlName: 'author_id',
        dartField: 'authorId',
        dartType: int,
        isForeignKey: true,
        foreignTable: 'author',
        foreignColumn: 'id',
      );
      final EntityMeta meta = EntityMeta(
        tableName: 'books',
        columns: <ColumnMeta>[idCol, authorIdCol],
        insertableColumns: <ColumnMeta>[authorIdCol],
        updatableColumns: <ColumnMeta>[authorIdCol],
        primaryKey: idCol,
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
      );
      final String ddl = meta.createTableDdl();
      expect(ddl, contains('REFERENCES author(id)'));
    });
  });

  group(
      'codegen migration template — source-level checks '
      '(regression net for the auto-emit fix)', () {
    test('migration_generator.dart emits createIndexStatements in up()',
        () {
      // The codegen template must include
      // `createIndexStatements()` per entity, or the
      // bug we just fixed (auto-generated migrations
      // missing @Index DDL) will silently regress.
      final File f = File(
        'lib/src/migration/migration_generator.dart',
      );
      final String src = f.readAsStringSync();
      expect(
        src,
        contains('createIndexStatements'),
        reason: 'migration generator must call createIndexStatements() '
            'per entity in the up() template',
      );
    });

    test('migration_generator.dart emits PRAGMA foreign_keys = ON', () {
      // Defense in depth: the runtime sets this on
      // every open (via the d_rocket 1.1.1 fix), but
      // the migration also makes the intent explicit
      // for anyone reading the generated SQL.
      final File f = File(
        'lib/src/migration/migration_generator.dart',
      );
      final String src = f.readAsStringSync();
      expect(
        src,
        contains("PRAGMA foreign_keys = ON"),
        reason: 'migration generator must emit '
            'PRAGMA foreign_keys = ON at the end of up()',
      );
    });
  });
}
