# d_rocket_builder 2.2.5

## Typed serializer defaults

Serializer code generation now preserves the declared type of collection
defaults. For example:

```dart
@JsonKey(defaultValue: <String>[])
final List<String> tags;
```

generates a valid `<String>[]` fallback instead of `<dynamic>[]`. Nested list,
set and map defaults also retain their declared type arguments.
