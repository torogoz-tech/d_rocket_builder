# Codegen nullability regression

This document records the regression fixed in the `d_rocket_builder` codegen.
It is intentionally version-neutral so it can be included in the next
lockstep release without changing package versions in this working tree.

## Root cause

The ORM generator used `DartType.toString()` in two different contexts without
normalizing nullability. A nullable field such as `String?` was emitted as
`dartType: String?`, even though `dartType` is a runtime `Type` literal, and
the row conversion template appended another `?`, producing `String??`.

The same template used a generic null fallback for every non-nullable field.
For `DateTime` that fallback became `null as DateTime`. DateTime values were
also passed directly to SQLite on writes, although the SQLite binding accepts
text/numeric values rather than Dart `DateTime` objects.

The serializer generator had a related gap for nullable `int` and `double`
fields: it cast the JSON value to `num` before checking whether the value was
null.

## Correction

`src/orm/type_support.dart` centralizes type-name normalization and the ORM
conversion rules:

- nullable row values retain exactly one `?`;
- DateTime is parsed from SQLite ISO-8601 text and written back as ISO-8601
  text;
- nullable numeric values are guarded before numeric conversion;
- non-nullable DateTime values fail with an explicit state error if SQLite
  returns NULL;
- existing primitive fallback behavior for non-nullable String, int, double,
  and bool is retained.

The ORM generator now derives database nullability from both `@Column` and the
Dart field type. The serializer generator guards nullable numeric JSON values.

## Covered cases

The regression tests cover:

- `String?` without generated `String??`;
- `DateTime?` from ISO-8601 text and NULL;
- non-nullable `DateTime` without `null as DateTime`;
- nullable decimal-equivalent `double?` values;
- nullable values from JSON and SQLite;
- DateTime persistence through the real SQLite provider;
- generated metadata using non-nullable runtime `Type` literals.

The project has no Decimal value-object/converter contract in `d_rocket 2.0.0`.
The supported decimal-equivalent representation is therefore `double` or
`num`; arbitrary Decimal objects still require an explicit conversion layer.
