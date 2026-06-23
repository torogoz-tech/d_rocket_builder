# d_rocket_builder

> **Codegen for the [d_rocket 2.0](https://pub.dev/packages/d_rocket) framework.**

<p align="center">
  <img src="https://coresg-normal.trae.ai/api/ide/v1/text_to_image?prompt=A%20modern%2C%20sleek%20rocket%20launching%20through%20a%20stylized%20database%20disk%2C%20with%20a%20trail%20of%20code%20streams%20representing%20six%20layers%20%28serialization%2C%20REST%2C%20LINQ%2C%20ORM%2C%20sync%2C%20realtime%29%2C%20deep%20navy%20blue%20to%20electric%20cyan%20gradient%2C%20geometric%20hexagonal%20accents%2C%20professional%20Dart%20framework%20brand%20banner%2C%20clean%20composition%2C%20no%20text&image_size=landscape_16_9" alt="d_rocket_builder banner" width="100%">
</p>

This is the **build-time** companion to `d_rocket`. It runs under
`build_runner` and emits all the wiring you don't want to write by
hand: serializers, REST clients, ORM metadata, migrations, and
the central `initializeD()` registry call.

## Builders

| Builder | What it emits |
|---|---|
| `d_rocket_builder:record` | Per-class `_$NameInit` part and a central `register<Name>Record()` call. |
| `d_rocket_builder:serializer` | Per-class `fromJson` / `toJson` and a `register<Name>Serializer()` call. |
| `d_rocket_builder:rest_client` | Per-interface `_$ClientImpl` plus a `register<Name>RestClient()` factory. |
| `d_rocket_builder:rocket_table` | Per-class `EntityMeta` literal and a `register<Name>EntityMeta()` helper. |
| `d_rocket_builder:record_registry` | A single `lib/d_rocket_registry.g.dart` that wires up everything via `initializeD()`. |
| `d_rocket_builder:rocket_migration` | Per-`@Migration` function, a `_$<Name>` `MigrationBase` class. |
| `d_rocket_builder:realtime` | Per-`@WebSocketClient` / `@SseClient`, a typed `Stream<T>` client. |

The codegen is the reason the runtime can offer a single
`initializeD()` call: every annotation in the project is collected
into a central `d_rocket_registry.g.dart` that registers
serializers, REST clients, and ORM metadata at startup.

## Installation

Add the builder as a **dev** dependency (it must NOT be in your
main dependencies — it never ships with the app):

```yaml
dev_dependencies:
  d_rocket: ^2.0.0
  d_rocket_builder: ^2.0.0
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
  sdk: ^3.6.0
  flutter: ">=3.10.0"

dependencies:
  d_rocket: ^2.0.0
  d_rocket_engine_sqlite: ^2.0.0

dev_dependencies:
  d_rocket_builder: ^2.0.0
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

@Table()
class CustomerEntity {
  @PrimaryKey(autoIncrement: true) late int id;
  @Column() late String name;
  @Column() late String email;
}
```

Run the generator:

```bash
dart run build_runner build
```

A new file `lib/d_rocket_registry.g.dart` now contains your
`initializeD()` function. Call it in `main()`:

```dart
import 'package:my_app/d_rocket_registry.g.dart';

void main() {
  initializeD();
  // every @Serializable, @RestClient, and @Table
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

- `_$BarClient implements IBar` (private to the generated file).
- Per-method implementation that builds the HTTP request,
  runs the interceptor chain, applies retry / rate-limit /
  circuit-breaker, decodes the response, and deserializes
  through the registered serializer.
- `registerBarRestClient()` factory.

For a class `Baz` annotated with `@Table`:

- `_$TableBaz.entityMeta` — the `EntityMeta` literal consumed
  by the engine's `QueryProvider`.
- `registerBazEntityMeta()` helper.

For a class `Qux` annotated with `@WebSocketClient` /
`@SseClient`:

- A typed `Stream<Qux>` client implementation.

## Lint rules

The lints moved to the dedicated
[`d_rocket_lints`](https://pub.dev/packages/d_rocket_lints)
package. `d_rocket_builder` re-exports them for convenience,
but new code should depend on `d_rocket_lints` directly:

- `d_rocket_untranslated_closure_linq` — flags LINQ operators
  used on raw `Iterable<T>` without an `Expr` (these evaluate
  in-memory only and can't be pushed to SQL).
- `d_rocket_n_plus_one` — flags LINQ queries that trigger
  N+1 round-trips. Promotes `include_<T>()` and pre-fetch.

Enable them in your `analysis_options.yaml`:

```yaml
analyzer:
  plugins:
    - d_rocket_lints
```

## CLI tools

The CLIs ship in the [`d_rocket`](https://pub.dev/packages/d_rocket)
runtime package, not here. The two executables are:

```bash
# Scaffold a new migration with the right id, class name,
# and pre-filled up() / down() bodies.
dart run d_rocket:migration add create_inventory_table
# ✓ Created lib/db/migrations/M005_create_inventory_table.dart

# Validate that the migration history is contiguous (no gaps).
dart run d_rocket:migration doctor
# ✓ Migration history is contiguous (5 migrations).
```

The `migration add` command supports a codegen path that
pre-fills the `up()` / `down()` body from the schema diff
between the codegen-emitted `EntityMeta[]` and the live DB
schema. See `d_rocket:migration add --help` for details.

## Support

- Source: <https://github.com/torogoz-tech/d_rocket_builder>
- Issues: <https://github.com/torogoz-tech/d_rocket_builder/issues>

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Torogoz Tech.

## Author

**Abner Velasco** — *Arquitecto de Soluciones*

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Abner%20Velasco-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/abnervelasco/)
