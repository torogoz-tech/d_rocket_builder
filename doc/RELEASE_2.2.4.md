# d_rocket_builder 2.2.4

## Generic values

Generic serializer callbacks now use raw JSON values:

```dart
T Function(Object?) decodeT
Object? Function(T) encodeT
```

This supports generic responses containing models, lists, maps and primitive
values such as `String`, `int` and `bool`. Nullable values remain guarded
before the callback is invoked.

For example, `Response<List<CardResponse>>` can provide a callback that reads
the raw list and maps each item through `CardResponseFromJson`; it is no longer
forced through `Map<String, dynamic>`.
