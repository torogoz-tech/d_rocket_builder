# 🔨 d_rocket_builder

> **Codegen for the [`d_rocket`](https://pub.dev/packages/d_rocket) framework.**

This is the **build-time** companion to `d_rocket`. It runs under
`build_runner` and emits all the wiring you don't want to write by
hand:

| Builder | What it emits |
|---|---|
| `d_rocket:rocket_serializer` | Per-class `fromJson` / `toJson` and central `register<X>Serializer` calls. |
| `d_rocket:rocket_rest_client` | Per-interface `RestClient` implementations with interceptors, retry, and serialization wired in. |
| `d_rocket:rocket_table` | Per-class `fromRow` (row materialiser) and `setId` (back-propagation hook) closures for the ORM. |
| `d_rocket:rocket_closure` *(optional)* | Closure-sugar `where` / `select` / `orderBy` extensions for prototyping over `Iterable<T>`. |
| `d_rocket:rocket_migration` *(CLI)* | `dart run d_rocket:rocket_migration add <name>` scaffolder. |

The codegen is the reason the runtime can offer a single
`initializeD()` call: every annotation in the project is collected
into a central `d_rocket_registry.g.dart` that registers
serializers, REST clients, and ORM metadata at startup.

---

## Table of contents

- [Installation](#installation)
- [Quickstart](#quickstart)
- [What gets generated](#what-gets-generated)
- [Lint rules](#lint-rules)
- [CLI tools](#cli-tools)
- [Support](#support)
- [License](#license)

---

## Installation

Add the builder as a dev dependency (it must NOT be in your main
dependencies — it never ships with the app):

```yaml
dev_dependencies:
  d_rocket: ^1.0.0
  d_rocket_builder: ^1.0.0
  build_runner: ^2.4.13
```

Then fetch and run the generator:

```bash
dart pub get
dart run build_runner build --delete-conflicting-outputs
```

The first run creates `d_rocket_registry.g.dart` and a
`*.d_rocket_*.g.dart` file next to every annotated source file.
Re-run the generator after every schema or API change.

## Quickstart

A minimal `pubspec.yaml` snippet for a project that uses
serialization, REST, and the ORM:

```yaml
name: my_app
description: My first d_rocket app
publish_to: none

environment:
  sdk: ^3.5.0
  flutter: ">=3.10.0"

dependencies:
  d_rocket: ^1.0.0

dev_dependencies:
  d_rocket_builder: ^1.0.0
  build_runner: ^2.4.13
```

Annotate your models:

```dart
@Serializable()
class Customer {
  Customer({required this.id, required this.name, required this.email});
  final int id;
  final String name;
  final String email;
}

@RestClient(baseUrl: 'https://api.example.com')
abstract class ShopClient {
  @HttpGet('/customers/{id}')
  Future<Customer> getCustomer(@Path('id') int id);
}

@RocketTable('customers')
class CustomerEntity {
  @PrimaryKey(autoIncrement: true) final int id;
  @Column() final String name;
  @Column() final String email;
}
```

Run the generator:

```bash
$ dart run build_runner build
[INFO] Generating build script completed in 0.3s
[INFO] Running build...
[INFO] Succeeded after 1.2s with 7 outputs (24 actions)
```

A new file `lib/d_rocket_registry.g.dart` now contains your
`initializeD()` function. Call it in `main()`:

```dart
import 'package:my_app/d_rocket_registry.g.dart';

void main() {
  initializeD();
  // every @Serializable, @RestClient, and @RocketTable
  // in the project is now wired up.
  runApp(const MyApp());
}
```

## What gets generated

For a class `Foo` annotated with `@Serializable()`:

- `Foo.fromJson(Map<String, Object?> json)` — named factory.
- `Map<String, Object?> toJson()` on `Foo`.
- `registerFooSerializer()` call in `d_rocket_registry.g.dart`.

For an interface `IBar` annotated with `@RestClient`:

- `_BarClient implements IBar` (private to the generated file).
- Per-method implementation that builds the HTTP request,
  runs the interceptor chain, applies retry / rate-limit /
  circuit-breaker, decodes the response, and deserializes
  through the registered serializer.

For a class `Baz` annotated with `@RocketTable`:

- `Baz.fromRow(Map<String, Object?> row)` — row materialiser.
- `void setId(Baz baz, Object id)` — back-propagation hook
  for the DB-assigned primary key.
- `BazSchema` constants (table name, column names) consumed
  by the SQL provider.

For a class `Qux` annotated with `@WebSocketRoute` /
`@SseRoute`:

- `Stream<Qux> ...()` method bodies in a generated
  `_QuxWsClient` / `_QuxSseClient`.

## Lint rules

`d_rocket_builder` ships two custom lint rules under
`package:custom_lint_builder`:

- `d_rocket_n_plus_one` — flags LINQ queries that trigger
  N+1 round-trips. Promotes `include_<T>()` and pre-fetch.
- `d_rocket_closure` — flags LINQ operators used on raw
  `Iterable<T>` without an `Expr` (these evaluate in-memory
  only and can't be pushed to SQL).

Enable them in your `analysis_options.yaml`:

```yaml
analyzer:
  plugins:
    - custom_lint

linter:
  rules:
    - d_rocket_n_plus_one
    - d_rocket_closure
```

## CLI tools

Two CLIs are exposed as executables on the `d_rocket_builder`
package:

```bash
# Scaffold a new migration with the right id, class name,
# and pre-filled up() / down() bodies.
dart run d_rocket:rocket_migration add create_inventory_table
# ✓ Created lib/db/migrations/M005_create_inventory_table.dart
#   id: 005, class: M005CreateInventoryTable

# Validate that the migration history is contiguous (no gaps).
dart run d_rocket:rocket_migration doctor
# ✓ Migration history is contiguous (5 migrations).
```

## Support

- **Docs**: [github.com/torogoz-tech/d_rocket](https://github.com/torogoz-tech/d_rocket)
- **Issues**: [github.com/torogoz-tech/d_rocket/issues](https://github.com/torogoz-tech/d_rocket/issues)
- **Discussions**: [github.com/torogoz-tech/d_rocket/discussions](https://github.com/torogoz-tech/d_rocket/discussions)

## License

© Torogoz Tech. Released under the [MIT License](LICENSE).
