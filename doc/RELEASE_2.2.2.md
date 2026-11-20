# d_rocket_builder 2.2.2

Release date: 2026-11-20

## Code generation fixes

- `@Pattern` expressions are escaped as Dart string literals, including `$`
  anchors.
- Nullable nested serializer models are guarded before dispatching to the
  registered non-nullable model factory.
- Generated REST clients resolve `RestClientConfig.baseUrl` at runtime for
  each client instance. The annotation remains the fallback URL.

## Forms

Generated `<ModelName>Form` adapters now accept model-level validators:

```dart
final form = PaymentRequestForm(
  validators: <FormValidator<PaymentRequest>>[
    (PaymentRequest? value) => value?.validateCard(),
  ],
);
```

They also expose `bindComposite()` for controls that update multiple fields:

```dart
form.bindComposite<String>((String value) => <String, Object?>{
  'expirationMonth': value.substring(0, 2),
  'expirationYear': value.substring(3),
});
```

Each mapped value goes through the target field's parser and validation rules.
