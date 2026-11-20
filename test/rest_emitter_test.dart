import 'package:d_rocket_builder/src/rest/emitter.dart';
import 'package:d_rocket_builder/src/rest/parser.dart';
import 'package:test/test.dart';

void main() {
  test('emits a runtime base URL override for each client instance', () {
    final String source = emitClient(
      ParsedClient(
        className: 'ExampleClient',
        baseUrl: 'https://generated.example',
        classPath: '',
        classHeaders: const <String, String>{},
        classTimeout: null,
        methods: <ParsedMethod>[
          ParsedMethod(
            name: 'load',
            verb: 'GET',
            path: '/items',
            methodHeaders: const <String, String>{},
            returnType: ParsedReturnType(
              dartType: 'PaginationResponse?',
              isVoid: false,
              isDynamic: false,
              isList: false,
              isMap: false,
            ),
            parameters: const <ParsedParameter>[],
            timeout: null,
          ),
        ],
      ),
    );

    expect(source, contains('config?.baseUrl ??'));
    expect(source, contains('baseUrl: _baseUrl'));
    expect(source, contains('dRest.decodeBody<PaginationResponse>(data)'));
    expect(source, isNot(contains("baseUrl: 'https://generated.example'")));
  });
}
