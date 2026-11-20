# d_rocket_builder 2.2.3

## Generic serializer codegen

This release fixes generated serializers for generic models such as:

```dart
@Serializable()
class Response<T> {
  const Response({this.data, this.message});

  final T? data;
  final String? message;
}
```

The generated decoder now calls the actual `decodeT` callback and uses the
actual JSON key. The generated `ResponseToJson<T>` function emits its map
directly and calls `encodeT` only after guarding nullable values.

The package was validated by generating the model with `build_runner` and
running `dart analyze` on the generated source.
