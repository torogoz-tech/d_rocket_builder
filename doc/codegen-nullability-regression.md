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

## Decimal policy in 2.1.0

The supported decimal-equivalent representations are `double` and `num`.
They map to SQLite `REAL` and `NUMERIC`, respectively, and are appropriate
when the application accepts floating-point or SQLite numeric affinity
semantics.

Exact decimal value objects such as `Decimal` or `BigDecimal` do not have an
implicit storage contract. The builder now fails generation with a clear
message unless the value is converted explicitly. For JSON, use
`@JsonKey(converter: 'money')` and provide `moneyToJson` / `moneyFromJson`.
For SQLite persistence, store an exact value as `String` or a scaled `int`
and expose the decimal object through an application-level converter. This
prevents silent precision loss and keeps the wire, ORM, and database formats
intentional.
