// example/lib/main.dart
//
// Minimal example of using d_rocket_builder's codegen.
//
// The codegen reads annotations in this file and
// emits the `fromJson` / `toJson` factories and the
// `registerUserSerializer()` call in `main.g.dart`.
//
// To run:
//   cd example
//   dart pub get
//   dart run build_runner build --delete-conflicting-outputs
//   dart run main.dart

import 'package:d_rocket/d_rocket.dart';
import 'package:d_rocket_builder/d_rocket_builder.dart';

@Serializable()
class User extends Record {
  User({this.id = 0, required this.name, required this.email});
  @PrimaryKey()
  final int id;
  final String name;
  final String email;
}

@Table()
class Account extends Record {
  Account({this.id = 0, required this.ownerId, required this.balance});
  @PrimaryKey()
  final int id;
  final int ownerId;
  final double balance;
}

@RestClient(baseUrl: 'https://api.example.com/v1')
abstract class HelloClient {
  @HttpGet('/users/{id}')
  Future<User> getUser(@Path('id') int id);
}

Future<void> main() async {
  // Initialize the codegen-emitted registry.
  initializeD();

  // Use the generated serializer registry.
  final alice = User(id: 1, name: 'Alice', email: 'alice@example.com');
  print('encoded: ${Serializer.toJson(alice)}');
  print('decoded: ${Serializer.fromJson<User>('{"id": 2, "name": "Bob", "email": "bob@example.com"}')}');
}
