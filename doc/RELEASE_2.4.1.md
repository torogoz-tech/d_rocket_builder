# d_rocket_builder 2.4.1

## Generic registry aliases

The central registry now resolves every concrete generic argument from the
library that declares its `DartType`. A response envelope in one file can
therefore reference a serializable model in another file without generating
an invalid alias such as `_m1.Item` when `_m1` points to the envelope.

Core types such as `List`, `Object`, and nullable `Object?` are emitted without
consumer-library aliases, preserving the declared nullability.

The regression suite also regenerates and compiles a minimal multi-file REST
contract, so this fix is validated against the generated Dart, not only the
builder's analyzer tests.
