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

  test('serializes enum query, path and header parameters by name', () {
    final String source = emitClient(
      ParsedClient(
        className: 'LocationClient',
        baseUrl: 'https://generated.example',
        classPath: '',
        classHeaders: const <String, String>{},
        classTimeout: null,
        methods: <ParsedMethod>[
          ParsedMethod(
            name: 'find',
            verb: 'GET',
            path: '/locations/{status}',
            methodHeaders: const <String, String>{},
            returnType: ParsedReturnType(
              dartType: 'dynamic',
              isVoid: false,
              isDynamic: true,
              isList: false,
              isMap: false,
            ),
            parameters: <ParsedParameter>[
              ParsedParameter(
                name: 'status',
                annotationName: 'status',
                kind: ParamKind.path,
                dartType: 'LocationStatus',
                isRequired: true,
                isNullable: false,
                isNamed: false,
                isEnum: true,
              ),
              ParsedParameter(
                name: 'filter',
                annotationName: 'filter',
                kind: ParamKind.query,
                dartType: 'LocationStatus',
                isRequired: true,
                isNullable: false,
                isNamed: false,
                isEnum: true,
              ),
              ParsedParameter(
                name: 'headerStatus',
                annotationName: 'X-Location-Status',
                kind: ParamKind.header,
                dartType: 'LocationStatus',
                isRequired: true,
                isNullable: false,
                isNamed: false,
                isEnum: true,
              ),
            ],
            timeout: null,
          ),
        ],
      ),
    );

    expect(source, contains("'X-Location-Status': '\${headerStatus.name}'"));
    expect(source, contains("'filter': filter.name"));
    expect(source, contains("'status': status.name"));
  });

  test('emits reactive query cache and successful mutation invalidation', () {
    final String source = emitClient(
      ParsedClient(
        className: 'BankingClient',
        baseUrl: 'https://generated.example',
        classPath: '',
        classHeaders: const <String, String>{},
        classTimeout: null,
        methods: <ParsedMethod>[
          ParsedMethod(
            name: 'watchAccount',
            verb: 'GET',
            path: '/accounts/{id}',
            methodHeaders: const <String, String>{},
            returnType: ParsedReturnType(
              dartType: 'Stream<Account>',
              isVoid: false,
              isDynamic: false,
              isList: false,
              isMap: false,
              isStream: true,
              innerType: 'Account',
            ),
            parameters: <ParsedParameter>[
              ParsedParameter(
                name: 'id',
                annotationName: 'id',
                kind: ParamKind.path,
                dartType: 'String',
                isRequired: true,
                isNullable: false,
                isNamed: false,
              ),
            ],
            timeout: null,
            queryCacheTags: const <String>['account:{id}'],
            queryCacheStaleTime: const Duration(seconds: 30),
            queryCacheTime: const Duration(minutes: 5),
          ),
          ParsedMethod(
            name: 'transfer',
            verb: 'POST',
            path: '/transfers',
            methodHeaders: const <String, String>{},
            returnType: ParsedReturnType(
              dartType: 'TransferReceipt',
              isVoid: false,
              isDynamic: false,
              isList: false,
              isMap: false,
            ),
            parameters: <ParsedParameter>[
              ParsedParameter(
                name: 'request',
                annotationName: null,
                kind: ParamKind.body,
                dartType: 'TransferRequest',
                isRequired: true,
                isNullable: false,
                isNamed: false,
              ),
            ],
            timeout: null,
            invalidationTags: const <String>['account:{request.sourceId}'],
          ),
        ],
      ),
    );

    expect(source, contains('Stream<Account> watchAccount'));
    expect(source, contains('dRest.queryCache.watch<Account>'));
    expect(source, contains("'account:{id}'"));
    expect(source, contains('dRest.queryCache.invalidate'));
    expect(source, contains("'request.sourceId': request.sourceId"));
  });

  test('emits typed RestPage item decoding', () {
    final String source = emitClient(
      ParsedClient(
        className: 'PageClient',
        baseUrl: 'https://generated.example',
        classPath: '',
        classHeaders: const <String, String>{},
        classTimeout: null,
        methods: <ParsedMethod>[
          ParsedMethod(
            name: 'list',
            verb: 'GET',
            path: '/items',
            methodHeaders: const <String, String>{},
            returnType: ParsedReturnType(
              dartType: 'RestPage<Item>',
              isVoid: false,
              isDynamic: false,
              isList: false,
              isMap: false,
              innerType: 'Item',
              isPage: true,
            ),
            parameters: const <ParsedParameter>[],
            timeout: null,
          ),
        ],
      ),
    );

    expect(source, contains('RestPage<Item>.fromJson'));
    expect(source, contains('dRest.decodeBody<Item>(item)'));
  });
}
