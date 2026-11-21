# d_rocket_builder 2.4.0

## Contract serializer registry

The central `d_rocket_registry.g.dart` now inspects concrete generic response
types used by generated REST and realtime contracts. It emits registrations for
shapes such as:

```dart
ResponseModel<VehicleResponse>
ResponseModel<List<VehicleResponse>>
```

The generated decoder handles nested list elements and uses the correct import
alias for models declared in another source library. Applications no longer
need a manual registry entry for each response shape. Unconstrained generic
classes remain available for explicit application registration.

Regenerate normally:

```sh
dart run build_runner build --delete-conflicting-outputs
```

The generated output is source-controlled by the consuming application policy;
it must never be edited by hand.
