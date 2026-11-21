# d_rocket_builder 2.5.0

## UUID form validation

The form builder recognizes `@Uuid()` and emits a canonical UUID validator.
Use `@Uuid(version: UuidVersion.v4)` when a field must contain a UUID v4.

The generated validator covers UUID versions 1 through 8, the compatible RFC
variant, canonical hyphens, case-insensitive hexadecimal digits, custom error
messages, and stable error codes.

## Async forms and serializer diagnostics

Generated `@Form` adapters accept `AsyncFormValidator<T>`,
`asyncValidationDebounce`, and expose `validateAsync()` / `buildAsync()`.
They also forward REST problem details through `applyRestError()`.

Generated serializers wrap field conversions with `SerializationException`,
which identifies the model field, expected type, raw value and original cause.
