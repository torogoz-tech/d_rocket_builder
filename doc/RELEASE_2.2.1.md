# d_rocket_builder 2.2.1

Release date: 2026-11-18

This patch release improves pub.dev metadata and documents the Forms codegen
surface introduced in 2.2.0. Generated APIs and builder behavior are
unchanged.

## Package metadata

The description is now a concise 60–180 character summary suitable for pub.dev
search results. The package version is `2.2.1` and it targets `d_rocket 2.2.1`.

## Documentation fixes

- The README lists the `d_rocket_builder:form` builder explicitly.
- Generated adapters are documented as `<ModelName>Form`.
- The Forms release guide documents output names, conversion and compatibility
  with serializer, REST, ORM, migration and realtime builders.

## Upgrade

```yaml
dependencies:
  d_rocket: ^2.2.1

dev_dependencies:
  d_rocket_builder: ^2.2.1
```

Run `dart run build_runner build --delete-conflicting-outputs` after updating
the package versions.
