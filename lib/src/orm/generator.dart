import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart' show NullabilitySuffix;
import 'package:analyzer/dart/element/type.dart' show DartType;
import 'package:build/build.dart';
import 'package:d_rocket/d_rocket.dart';
import 'package:source_gen/source_gen.dart';

/// Codegen for `@Table` entities. Emits a per-class
/// static `EntityMeta entityMeta` plus a
/// `register<Class>EntityMeta()` helper that the central
/// `initializeD()` calls.
///
/// Moved into `d_rocket_builder` under ("ORM") of the
/// d_rocket roadmap. The generator walks every annotated
/// class, inspects the fields annotated with `@PrimaryKey` or
/// `@Column`, and emits the metadata literal the runtime
/// needs to build `INSERT` / `UPDATE` / `DELETE` SQL.
class TableGenerator extends GeneratorForAnnotation<Table> {
  const TableGenerator();

  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@Table can only be applied to classes.',
        element: element,
      );
    }

    final String className = element.displayName;
    final String tableName = _tableNameOf(element, annotation);

    // Discover the columns in declaration order. The analyzer
    // returns `fields` in source order, which is what we want.
    final List<FieldElement> allFields = element.fields
        .where((FieldElement f) => !f.isStatic && !f.isPrivate)
        .toList();

    final List<FieldElement> pkFields = allFields
        .where((FieldElement f) => _annotationNamed(f, 'PrimaryKey') != null)
        .toList();
    if (pkFields.length > 1) {
      throw InvalidGenerationSourceError(
        'Multiple @PrimaryKey fields on $className. '
        'Exactly one is required.',
        element: element,
      );
    }
    if (pkFields.isEmpty) {
      throw InvalidGenerationSourceError(
        'No @PrimaryKey field on $className. '
        'Exactly one is required.',
        element: element,
      );
    }
    final FieldElement pkField = pkFields.first;
    final bool pkAutoIncrement = _readBool(
      _annotationNamed(pkField, 'PrimaryKey')!,
      'autoIncrement',
    );

    // Columns: every field annotated with @Column or
    // @ForeignKey (which is a subclass of @Column), plus
    // the @PrimaryKey field (it is both a column and the
    // PK). @Index is a **marker** annotation (it does not
    // declare the column itself); we still require the
    // field to also have @Column or @ForeignKey.
    final List<_ColumnSpec> columnSpecs = <_ColumnSpec>[];
    for (final FieldElement f in allFields) {
      if (f == pkField) {
        columnSpecs.add(_ColumnSpec(
          field: f,
          isPrimaryKey: true,
          isAutoIncrement: pkAutoIncrement,
          columnAnnotation: null,
          foreignKeyAnnotation: null,
          indexAnnotation: null,
        ));
        continue;
      }
      final ConstantReader? colAnn = _annotationNamed(f, 'Column');
      final ConstantReader? fkAnn = _annotationNamed(f, 'ForeignKey');
      if (colAnn == null && fkAnn == null) continue;
      // @ForeignKey is a subclass of @Column at the
      // semantic level; the codegen reads the FK metadata
      // directly from the @ForeignKey annotation (if
      // present), or from the @Column annotation's
      // `isForeignKey: true` flag (as a fallback).
      columnSpecs.add(_ColumnSpec(
        field: f,
        isPrimaryKey: false,
        isAutoIncrement: false,
        columnAnnotation: colAnn ?? fkAnn,
        foreignKeyAnnotation: fkAnn,
        indexAnnotation: _annotationNamed(f, 'Index'),
      ));
    }
    if (columnSpecs.isEmpty) {
      throw InvalidGenerationSourceError(
        '@Table $className has no @Column fields.',
        element: element,
      );
    }

    // Build the column literals for the constructor.
    final String columnsLiteral = columnSpecs.map(_emitColumnLiteral).join(',\n    ');
    final List<_ColumnSpec> insertableSpecs = columnSpecs
        .where((_ColumnSpec s) => !(s.isPrimaryKey && s.isAutoIncrement))
        .toList();
    final List<_ColumnSpec> updatableSpecs = columnSpecs
        .where((_ColumnSpec s) => !s.isPrimaryKey)
        .toList();
    final String insertableLiteral = insertableSpecs.map(_emitColumnLiteral).join(',\n    ');
    final String updatableLiteral = updatableSpecs.map(_emitColumnLiteral).join(',\n    ');

    // .a: build the `navigations` literal
    // from any `@ForeignKey` columns. Each FK becomes
    // a `NavigationMeta` entry in the EntityMeta's
    // `navigations: <NavigationMeta>[…]` list.
    final String navigationsLiteral = _emitNavigationsLiteral(columnSpecs, className);
    // .b: emit the navigation extension
    // (e.g. `Order.customer` getter) that reads from
    // the global NavigationRegistry.
    final String navigationExtension = _emitNavigationExtension(className, columnSpecs);
    // .f: emit the include extension
    // (e.g. `OrderDbSetIncludes` with
    // `.include_customer()`) that wraps the
    // string-based `.include_<T>()` in a typed method.
    final String includeExtension = _emitIncludeExtension(className, columnSpecs);

    final int pkIndex = columnSpecs.indexWhere((_ColumnSpec s) => s.isPrimaryKey);

    final String pkOfExpr = '(Object e) => (e as $className).${pkField.displayName}';

    //  + 5.2.2 (TPH): the inheritance
    // role of this class.
    //   * `null` → non-TPH (regular table, no parent).
    // * `'root'` or
    //     `inheritance: InheritanceStrategy.tph`
    // → the root of a TPH hierarchy.
    //   * any other string → the discriminator value
    //     for a child of a TPH hierarchy.
    final String? discriminator = _readString(annotation, 'discriminator');
    final String? inheritanceName = _readEnumByName(annotation, 'inheritance');
    final bool isInheritanceTph = inheritanceName == 'tph';
    final bool isTpcRoot = inheritanceName == 'tpc';
    final bool isTphRoot = discriminator == 'root' || isInheritanceTph;
    final bool isTphChild =
        discriminator != null && discriminator != 'root';

    //  (TPH): find the discriminator
    // column (the one with `@Column(discriminator:
    // true)`) — used by the root meta.
    _ColumnSpec? discSpec;
    if (isTphRoot) {
      for (final _ColumnSpec s in columnSpecs) {
        if (s.columnAnnotation == null) continue;
        if (_readBool(s.columnAnnotation!, 'discriminator')) {
          discSpec = s;
          break;
        }
      }
      if (discSpec == null) {
        throw InvalidGenerationSourceError(
          '@Table(inheritance: "root") on '
          '$className must have a column annotated with '
          '@Column(discriminator: true).',
          element: element,
        );
      }
    }

    // `readColumn` is a fallback for entities that do NOT
    // `extends Record`. The codegen can populate it
    // unconditionally — when the entity does `extends Record`,
    // the runtime will skip it.
    final String readColumnExpr =
        '(Object e, ColumnMeta c) => switch (c.dartField) {\n'
        '${columnSpecs.map((_ColumnSpec s) => "      '${s.field.displayName}' => (e as $className).${s.field.displayName},").join('\n')}\n'
        '      _ => null,\n'
        '    }';

    // `fromRow` constructs a `T` instance from a `Map<String,
    // Object?>` row returned by the SQL provider. This is the
    // single point that materialises a row into a typed
    // entity — `DbSet<T>.toList()` and `.findById()` both
    // depend on it. If a column is nullable, the codegen
    // emits a defensive `?? null` so `int` columns with a
    // `NULL` value still produce a `null` (instead of
    // crashing the cast).
    final String fromRowExpr = _emitFromRowExpr(
      className: className,
      specs: columnSpecs,
    );

    // `setId` is the back-propagation hook for auto-PK. The
    // `DbContext.saveChanges()` flow calls it on every
    // freshly inserted entity so the in-memory instance picks
    // up the DB-assigned PK.
    final String setIdExpr;
    if (pkField.isFinal) {
      // The PK field is `final`; we cannot reassign it. The
      // codegen refuses to emit a non-assignable setter.
      setIdExpr = '(Object e, Object id) {\n'
          "    throw StateError(\n"
          "      'Cannot back-propagate PK to "
          "$className.${pkField.displayName}: field is `final`. "
          "Mark it `var` to allow auto-PK back-propagation.');\n"
          '  }';
    } else {
      setIdExpr =
          '(Object e, Object id) => (e as $className).${pkField.displayName} = id as ${_dartTypeName(pkField.type)}';
    }

    //  (TPH): read the `children` map
    // (only meaningful on a TPH root). The codegen
    // emits a `wire<Root>EntityMeta()` helper that
    // builds the `EntityMeta.subclassMetas` map from
    // the children's static `entityMeta` extensions.
    final Map<String, String>? children =
        _readStringMap(annotation, 'children');
    final String? wireHelper =
        isTphRoot && children != null && children.isNotEmpty
            ? _emitWireHelper(className, children)
            : null;

    return '''
extension _$Table$className on $className {
  static final EntityMeta entityMeta = EntityMeta(
    tableName: '$tableName',
    columns: <ColumnMeta>[
    $columnsLiteral,
    ],
    insertableColumns: <ColumnMeta>[
    $insertableLiteral,
    ],
    updatableColumns: <ColumnMeta>[
    $updatableLiteral,
    ],
    primaryKey: ${_emitColumnLiteral(columnSpecs[pkIndex]).replaceAll('\n', '\n  ')},
    primaryKeyIndex: $pkIndex,
    pkOf: $pkOfExpr,
    readColumn: $readColumnExpr,
    fromRow: $fromRowExpr,
    setId: $setIdExpr,
    ${_emitTphFields(className, isTphRoot, isTphChild, discriminator, discSpec, columnSpecs, isTpcRoot)},
    navigations: <NavigationMeta>[
    $navigationsLiteral
    ],
  );
}

${wireHelper ?? ''}
${navigationExtension}
${includeExtension}

void register${className}EntityMeta() {
  EntityRegistry.register<$className>(
    ${wireHelper != null ? 'wire${className}EntityMeta()' : '_$Table$className.entityMeta'},
  );
}
''';
  }

  /// .b: emit a `_<Class>Navigation` extension
  /// that exposes the navigation getters. The getters
  /// read from the global `NavigationRegistry`, which
  /// the framework populates after a fetch or `.include_`.
  ///
  /// Example (generated for an Order with @ForeignKey to Customer):
  /// ```dart
  /// extension _$OrderNavigation on Order {
  ///   Customer? get customer =>
  ///       NavigationRegistry.get<Customer>(this, 'customer');
  /// }
  /// ```
  ///
  /// The extension is emitted as a **part**-friendly code
  /// block (it's part of the same generator output that
  /// contains the EntityMeta).
  String _emitNavigationExtension(
    String className,
    List<_ColumnSpec> specs,
  ) {
    final List<String> getters = <String>[];
    for (final _ColumnSpec s in specs) {
      if (s.foreignKeyAnnotation == null) continue;
      final String? targetTable =
          _readString(s.foreignKeyAnnotation!, 'table');
      if (targetTable == null || targetTable.isEmpty) continue;
      final String navName = _deriveNavName(s.field.displayName);
      // .b: target type defaults to `dynamic`
      // for MVP. The codegen will resolve it via the
      // entity registry in 9.9.c (when we have access
      // to a name → Dart type mapping).
      getters.add(
        "  dynamic get $navName =>\n"
        "      NavigationRegistry.get<dynamic>(this, '$navName');",
      );
    }
    if (getters.isEmpty) return '';
    return '\nextension _\$${className}Navigation on $className {\n'
        '${getters.join('\n')}\n'
        '}\n';
  }

  /// .f: emit a `_<Class>DbSetIncludes`
  /// extension that provides typed
  /// `.include_<T>()` methods per navigation. The
  /// user can call `.include_customer()` instead
  /// of `.include_<Customer>('customer', Customer.entityMeta)`.
  ///
  /// **MVP**: target type is `dynamic` (the codegen
  /// resolves the actual type in a follow-up using
  /// the entity registry). The wrapper is still
  /// valuable because it hides the string name.
  String _emitIncludeExtension(
    String className,
    List<_ColumnSpec> specs,
  ) {
    final List<String> methods = <String>[];
    for (final _ColumnSpec s in specs) {
      if (s.foreignKeyAnnotation == null) continue;
      final String? targetTable =
          _readString(s.foreignKeyAnnotation!, 'table');
      if (targetTable == null || targetTable.isEmpty) continue;
      final String navName = _deriveNavName(s.field.displayName);
      // .f: emit a typed method. The
      // target type defaults to dynamic; the codegen
      // will resolve the actual class via the
      // entity registry in 9.9.f+.
      //
      // We can't easily get the target class name
      // here (it requires a registry lookup), so
      // for MVP we emit a dynamic-typed wrapper.
      // The wrapper is still useful: it hides the
      // string name and the type mismatch error
      // if the user passes the wrong type.
      final String targetClassName = _deriveTargetClassName(targetTable);
      methods.add(
        '  DbSet<$className> include_$navName() =>\n'
        "      include_<$targetClassName>('$navName', "
        '$targetClassName.entityMeta);',
      );
    }
    if (methods.isEmpty) return '';
    return '\nextension _\$${className}DbSetIncludes on DbSet<$className> {\n'
        '${methods.join('\n')}\n'
        '}\n';
  }

  /// .f helper: derive a Dart class name
  /// from a SQL table name. `customers` → `Customer`,
  /// `line_items` → `LineItem`. Best-effort: if the
  /// name has no underscore, we just capitalise it.
  String _deriveTargetClassName(String tableName) {
    if (tableName.isEmpty) return 'dynamic';
    final List<String> parts = tableName.split('_');
    final StringBuffer result = StringBuffer();
    for (final String p in parts) {
      if (p.isEmpty) continue;
      result.write(p[0].toUpperCase());
      if (p.length > 1) result.write(p.substring(1));
    }
    return result.toString();
  }

  /// .a: build the `navigations` literal
  /// from the columnSpecs. Each `@ForeignKey` field
  /// becomes a `NavigationMeta` entry.
  ///
  /// **MVP scope** (1:1 navigations only):
  /// - The navigation name is derived from the FK
  ///   field name: strip trailing `Id` (camelCase)
  ///   or `_id` (snake_case) and lowercase the first
  ///   letter. E.g., `customerId` → `customer`.
  /// - `targetTable` comes from the `@ForeignKey(table:)`
  ///   annotation.
  /// - `targetColumn` defaults to `'id'`.
  /// - `targetDartType` is `dynamic` for MVP (resolved
  /// in .b via the entity registry).
  /// - `isCollection` is always `false` (1:many is
  /// .b+).
  String _emitNavigationsLiteral(
    List<_ColumnSpec> specs,
    String className,
  ) {
    final List<String> entries = <String>[];
    for (final _ColumnSpec s in specs) {
      if (s.foreignKeyAnnotation == null) continue;
      final String dartField = s.field.displayName;
      final String? targetTable =
          _readString(s.foreignKeyAnnotation!, 'table');
      if (targetTable == null || targetTable.isEmpty) continue;
      final String targetColumn =
          _readString(s.foreignKeyAnnotation!, 'column') ?? 'id';
      final String navName = _deriveNavName(dartField);
      entries.add(
        "NavigationMeta(\n"
        "  name: '$navName',\n"
        "  fkColumn: '$dartField',\n"
        "  targetTable: '$targetTable',\n"
        "  targetColumn: '$targetColumn',\n"
        "  targetDartType: dynamic,\n"
        ")",
      );
    }
    if (entries.isEmpty) return '';
    return entries.join(',\n    ');
  }

  /// .a helper: derive a navigation name
  /// from a FK field name. `customerId` → `customer`,
  /// `user_id` → `user`, `OrderId` → `order`.
  String _deriveNavName(String fkField) {
    String n = fkField;
    if (n.endsWith('Id') && n.length > 2) {
      n = n.substring(0, n.length - 2);
    } else if (n.endsWith('_id') && n.length > 3) {
      n = n.substring(0, n.length - 3);
    }
    if (n.isEmpty) return fkField;
    return n[0].toLowerCase() + n.substring(1);
  }

  ///: emits a `wire<Root>EntityMeta`
  /// helper that builds the root's `subclassMetas`
  /// map by referencing the children's static
  /// `entityMeta` extensions. Returns the empty
  /// string when there are no children to wire.
  String _emitWireHelper(String className, Map<String, String> children) {
    final StringBuffer entries = StringBuffer();
    children.forEach((String discValue, String childClass) {
      entries.writeln("      '$discValue': $childClass.entityMeta,");
    });
    return '''
EntityMeta wire${className}EntityMeta() {
  return _$Table$className.entityMeta.copyWith(
    subclassMetas: <String, EntityMeta>{
${entries.toString().trimRight()}
    },
  );
}
''';
  }

  ///  + 5.2.4.1: emits the
  /// inheritance-related fields of the [EntityMeta]
  /// constructor literal (the `inheritanceStrategy:`,
  /// `discriminatorValue:`, `discriminatorColumn:`,
  /// `isAbstract:` arguments). Returns the empty
  /// string for non-inheritance entities.
  String _emitTphFields(
    String className,
    bool isTphRoot,
    bool isTphChild,
    String? discriminator,
    _ColumnSpec? discSpec,
    List<_ColumnSpec> allSpecs,
    bool isTpcRoot,
  ) {
    if (!isTphRoot && !isTphChild && !isTpcRoot) return '';
    final StringBuffer out = StringBuffer();
    if (isTphRoot) {
      out.writeln('inheritanceStrategy: InheritanceStrategy.tph,');
      out.writeln('discriminatorColumn: '
          '${_emitColumnLiteral(discSpec!).replaceAll('\n', '\n    ')},');
      out.writeln('subclassMetas: <String, EntityMeta>{},');
    } else if (isTphChild) {
      out.writeln('inheritanceStrategy: InheritanceStrategy.tph,');
      out.writeln("discriminatorValue: '$discriminator',");
      out.writeln('discriminatorColumn: '
          '${_emitColumnLiteral(allSpecs.firstWhere((s) => s.columnAnnotation != null && _readBool(s.columnAnnotation!, 'discriminator'))).replaceAll('\n', '\n    ')},');
    } else if (isTpcRoot) {
      //: TPC root with
      // `isAbstract: true` — the root owns no table.
      out.writeln('inheritanceStrategy: InheritanceStrategy.tpc,');
      out.writeln('isAbstract: true,');
    }
    return out.toString().trimRight();
  }

  /// Emits the `fromRow` closure: a `(Map<String, Object?>) →
  /// $className` function that materialises a raw row from
  /// the SQL provider into a typed instance.
  String _emitFromRowExpr({
    required String className,
    required List<_ColumnSpec> specs,
  }) {
    final StringBuffer body = StringBuffer()
      ..writeln('(Map<String, Object?> r) {');
    for (final _ColumnSpec spec in specs) {
      final String sqlName = _toSnakeCase(spec.field.displayName);
      final String type = _dartTypeName(spec.field.type);
      final String defaultValue = _dartDefaultValueFor(spec.field.type);
      if (spec.isPrimaryKey) {
        // PKs are always present.
        body.writeln(
          '    final ${type} _${spec.field.displayName} = r[\'$sqlName\'] as ${type};',
        );
      } else if (spec.isNullable) {
        body.writeln(
          '    final ${type} _${spec.field.displayName} = r[\'$sqlName\'] as ${type}?;',
        );
      } else {
        body.writeln(
          '    final ${type} _${spec.field.displayName} = r[\'$sqlName\'] as ${type}? ?? $defaultValue;',
        );
      }
    }
    body.write('    return $className(');
    body.write(specs.map((_ColumnSpec s) => '${s.field.displayName}: _${s.field.displayName}').join(', '));
    body.writeln(');');
    body.writeln('  }');
    return body.toString();
  }

  /// Returns the Dart source-level name of a Dart type as
  /// used in constructor positional / named arguments (e.g.
  /// `int`, `String`, `double`, `bool`).
  String _dartTypeName(DartType t) {
    // `getDisplayString` returns `int`, `String`, `double`,
    // `bool`, `DateTime`, `BigInt`, etc. — exactly what we
    // want for the cast.
    return t.getDisplayString();
  }

  /// Returns the literal default value (used when the row's
  /// column is `NULL` for a non-nullable Dart type).
  String _dartDefaultValueFor(DartType t) {
    final String name = t.getDisplayString();
    if (name == 'int') return '0';
    if (name == 'double') return '0.0';
    if (name == 'bool') return 'false';
    if (name == 'String') return "''";
    return 'null as $name';
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _tableNameOf(ClassElement element, ConstantReader ann) {
    final String? explicitName = _readString(ann, 'name');
    if (explicitName != null && explicitName.isNotEmpty) {
      return explicitName;
    }
    return _toSnakeCase(element.displayName);
  }

  String _emitColumnLiteral(_ColumnSpec spec) {
    final FieldElement f = spec.field;
    final String dartField = f.displayName;
    final String type = f.type.toString();
    final String sqlName = _toSnakeCase(dartField);
    final bool nullable = spec.isPrimaryKey
        ? false
        : _readBool(spec.columnAnnotation!, 'nullable');
    final String? defaultLiteral = spec.isPrimaryKey
        ? null
        : _readDefaultLiteral(spec.columnAnnotation!);

    // Foreign-key metadata. Either:
    //   * `@ForeignKey(table: 'X', column: 'Y')` — explicit
    //     target, overrides everything.
    //   * `@Column(isForeignKey: true, ...)` — flag without
    //     a target (left as a flag for downstream tools;
    //     the DDL does not emit a REFERENCES clause).
    String? foreignTable;
    String? foreignColumn;
    bool isForeignKey = false;
    if (spec.foreignKeyAnnotation != null) {
      isForeignKey = true;
      foreignTable = _readString(spec.foreignKeyAnnotation!, 'table');
      foreignColumn = _readString(spec.foreignKeyAnnotation!, 'column');
    } else if (spec.columnAnnotation != null &&
        _readBool(spec.columnAnnotation!, 'isForeignKey')) {
      isForeignKey = true;
    }

    // Index metadata. `@Index(unique: bool, name: String?)`
    // — defaults to `unique: false`, `name: null` (the
    // runtime derives the index name as
    // `<table>_<column>_idx` or `_unq` for unique indexes).
    bool isIndexed = false;
    bool isUniqueIndex = false;
    String? indexName;
    if (spec.indexAnnotation != null) {
      isIndexed = true;
      isUniqueIndex = _readBool(spec.indexAnnotation!, 'unique');
      indexName = _readString(spec.indexAnnotation!, 'name');
    }

    return '''ColumnMeta(
      sqlName: '$sqlName',
      dartField: '$dartField',
      dartType: $type,
      nullable: $nullable,
      defaultLiteral: ${defaultLiteral == null ? 'null' : "'$defaultLiteral'"},
      isPrimaryKey: ${spec.isPrimaryKey},
      isAutoIncrement: ${spec.isAutoIncrement},
      isForeignKey: $isForeignKey,
      foreignTable: ${foreignTable == null ? 'null' : "'$foreignTable'"},
      foreignColumn: ${foreignColumn == null ? 'null' : "'$foreignColumn'"},
      isIndexed: $isIndexed,
      isUniqueIndex: $isUniqueIndex,
      indexName: ${indexName == null ? 'null' : "'$indexName'"},
    )''';
  }

  ConstantReader? _annotationNamed(Element element, String name) {
    for (final ElementAnnotation a in element.metadata.annotations) {
      if (a.element?.displayName == name) {
        return ConstantReader(a.computeConstantValue());
      }
    }
    return null;
  }

  String? _readString(ConstantReader r, String field) {
    final ConstantReader? v = r.peek(field);
    if (v == null || v.isNull || !v.isString) return null;
    return v.stringValue;
  }

  ///: reads an enum-typed field (like
  /// `@Table.inheritance`) and returns its `.name`
  /// as a `String`. Returns `null` if the field is not
  /// an enum or is missing.
  String? _readEnumByName(ConstantReader r, String field) {
    final ConstantReader? v = r.peek(field);
    if (v == null || v.isNull) return null;
    // The `ConstantReader` for an enum value stores
    // the underlying `DartObject`. The object's `toStringValue()`
    // gives the enum's `.name` (e.g. `'tph'`, `'none'`).
    try {
      // The `objectValue` getter exposes the underlying
      // `DartObject`. Reading its `toStringValue()` gives
      // the enum's `.name`.
      // ignore: invalid_use_of_protected_member
      final Object? dartObj = (v as dynamic).objectValue;
      if (dartObj == null) return null;
      // The `toStringValue()` of a `DartObject` representing
      // an enum returns the enum's `.name` (e.g. `'tph'`).
      // ignore: invalid_use_of_protected_member
      return (dartObj as dynamic).toStringValue() as String?;
    } catch (_) {
      return null;
    }
  }

  ///: reads a `Map<String, String>` field
  /// (like `@Table.children`). Returns `null` if
  /// the field is missing or not a map.
  Map<String, String>? _readStringMap(ConstantReader r, String field) {
    final ConstantReader? v = r.peek(field);
    if (v == null || v.isNull) return null;
    if (!v.isMap) return null;
    final Map<String, String> out = <String, String>{};
    for (final MapEntry<dynamic, dynamic> e in v.mapValue.entries) {
      final String? k = e.key as String?;
      final String? val = e.value as String?;
      if (k != null && val != null) out[k] = val;
    }
    return out;
  }

  bool _readBool(ConstantReader r, String field) {
    final ConstantReader? v = r.peek(field);
    if (v == null || v.isNull) return false;
    return v.boolValue;
  }

  String? _readDefaultLiteral(ConstantReader r) {
    final ConstantReader? v = r.peek('defaultValue');
    if (v == null || v.isNull) return null;
    final Object? lit = v.literalValue;
    if (lit == null) return null;
    if (lit is String) return lit.replaceAll("'", "\\'");
    if (lit is bool || lit is num) return lit.toString();
    throw InvalidGenerationSourceError(
      'Unsupported @Column defaultValue type: ${lit.runtimeType}. '
      'Use String, bool, num, or null.',
    );
  }

  String _toSnakeCase(String input) {
    final StringBuffer result = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final int code = input.codeUnitAt(i);
      if (code >= 65 && code <= 90) {
        if (i > 0) result.write('_');
        result.write(String.fromCharCode(code + 32));
      } else {
        result.write(input[i]);
      }
    }
    return result.toString();
  }
}

class _ColumnSpec {
  _ColumnSpec({
    required this.field,
    required this.isPrimaryKey,
    required this.isAutoIncrement,
    required this.columnAnnotation,
    required this.foreignKeyAnnotation,
    required this.indexAnnotation,
  });

  final FieldElement field;
  final bool isPrimaryKey;
  final bool isAutoIncrement;

  /// The `@Column(...)` annotation (always present for
  /// non-PK fields in the spec; `null` for the PK field).
  /// When the field is annotated with `@ForeignKey` (a
  /// subclass), this holds the same constant reader —
  /// the codegen reads it for `nullable` / `defaultValue`.
  final ConstantReader? columnAnnotation;

  /// The `@ForeignKey(...)` annotation if present.
  /// `null` for plain `@Column` fields.
  final ConstantReader? foreignKeyAnnotation;

  /// The `@Index(...)` annotation if present. Independent
  /// of `@Column` / `@ForeignKey` (a field can be indexed
  /// without being a foreign key, and vice versa).
  final ConstantReader? indexAnnotation;

  /// Whether the underlying Dart type is nullable (e.g.
  /// `String?`). Used by the codegen to emit the right
  /// `fromRow` cast (nullable cast vs. forced non-null with
  /// default).
  bool get isNullable =>
      field.type.nullabilitySuffix ==
      // ignore: deprecated_member_use
      NullabilitySuffix.question;

}
