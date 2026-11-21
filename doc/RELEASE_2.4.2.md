# d_rocket_builder 2.4.2

## Opaque `Object?` envelope payloads

Concrete generic registrations for `Envelope<Object?>` now decode the payload
directly. This keeps JSON objects, lists, scalar values, and `null` opaque and
does not require registering `Object?` or inventing a business model.

The generated registration remains compatible with normal encoding:

```dart
registerEnvelopeSerializer<Object?>(
  decode: (Object? value) => value,
  encode: Serializer.encodeDynamic,
);
```

The regression suite validates generation, compilation, decoding, and JSON
round-trips for these payload shapes.
