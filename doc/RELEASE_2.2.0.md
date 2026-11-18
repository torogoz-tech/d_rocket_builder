# d_rocket_builder 2.2.0

Release date: 2026-11-18

`d_rocket_builder` 2.2.0 adds the `form` PartBuilder. It generates concrete
model-bound form adapters while preserving the existing serializer, REST, ORM,
migration, realtime and registry outputs.

## Installation

```yaml
dependencies:
  d_rocket: ^2.2.0

dev_dependencies:
  d_rocket_builder: ^2.2.0
  build_runner: ^2.4.13
```

Run:

```bash
dart pub get
dart run build_runner build --delete-conflicting-outputs
```

## Builder contract

```yaml
d_rocket_builder:form:
  build_extensions: {".dart": [".d_rocket_form.g.dart"]}
  auto_apply: dependents
  build_to: source
```

The builder only processes models annotated with `@Form`. It emits a concrete
`<ModelName>Form` adapter and does not modify or merge any other generated
part. The generated adapter imports the runtime types from `d_rocket` and
contains no Flutter, SQLite, REST-client or database code.

## Metadata and conversion generation

The generator:

- reads `@FormField` label, order and input metadata;
- includes public instance fields even when `@FormField` is omitted;
- preserves field order and emits `FormFieldDefinition` values;
- validates that included fields are named parameters of the unnamed
  generative constructor;
- validates annotation/type compatibility at generation time;
- emits raw parsers for `int`, `double`, `num`, `bool`, `DateTime` and enums;
- honors built-in string and date formats supported by the serializer;
- reports invalid raw input through the runtime's stable
  `conversion.invalid` error code;
- refuses to guess a lossy representation for exact decimal value objects.

## Output example

Given `LoginRequest` in `login_request.dart`, the builder emits:

```text
login_request.d_rocket_form.g.dart
```

The public generated API is:

```dart
final form = LoginRequestForm();
form.email.bind()(emailController.text);
form.password.bind()(passwordController.text);

if (form.validate()) {
  final request = form.build();
}
```

The serializer and REST parts remain separate:

```text
login_request.d_rocket_serializer.g.dart
auth_api.d_rocket_rest_client.g.dart
login_request.d_rocket_form.g.dart
```

## Compatibility and migration

This is a paired release with `d_rocket 2.2.0`. Existing models without
`@Form` do not receive a form output and retain their previous codegen
behavior. Existing `part` declarations for serializer, REST, ORM, migration
or realtime output do not change.

Generated files must be recreated with `build_runner`; they are not hand-edit
targets. Consumers should run generation in CI before `dart analyze` and
`dart test` when generated parts are ignored by source control.

The builder package itself was verified with its complete 59-test suite and a
clean build against the d_rocket fixtures.
