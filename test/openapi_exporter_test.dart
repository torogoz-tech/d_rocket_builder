import 'package:test/test.dart';

import '../lib/src/rest/openapi_document.dart';
import '../lib/src/rest/openapi_exporter.dart';
import '../lib/src/rest/openapi_endpoint.dart';
import '../lib/src/rest/openapi_importer.dart';
import '../lib/src/rest/parser.dart';

void main() {
  test('exports REST client metadata as OpenAPI 3.1', () {
    final OpenApiDocument document = const OpenApiExporter().export(
      ParsedClient(
        className: 'CatalogClient',
        baseUrl: 'https://api.example.test',
        classPath: '/v1',
        classHeaders: const <String, String>{},
        classTimeout: null,
        methods: <ParsedMethod>[
          ParsedMethod(
            name: 'getItem',
            verb: 'GET',
            path: '/items/{id}',
            methodHeaders: const <String, String>{},
            returnType: ParsedReturnType(
              dartType: 'Item',
              isVoid: false,
              isDynamic: false,
              isList: false,
              isMap: false,
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
          ),
        ],
      ),
    );
    final Map<String, Object?> json = document.toJson();
    final Map<String, Object?> paths = json['paths']! as Map<String, Object?>;
    final Map<String, Object?> operation = (paths['/v1/items/{id}']!
        as Map<String, Object?>)['get']! as Map<String, Object?>;

    expect(json['openapi'], '3.1.0');
    expect(operation['operationId'], 'getItem');
    expect((operation['parameters']! as List<Object?>).length, 1);
    expect(json['servers'], isNotEmpty);
    expect(
      (json['components']! as Map<String, Object?>)['schemas'],
      containsPair('Item', <String, Object?>{'type': 'object'}),
    );
  });

  test('imports endpoint metadata from an OpenAPI document', () {
    const OpenApiDocument document = OpenApiDocument(<String, Object?>{
      'openapi': '3.1.0',
      'paths': <String, Object?>{
        '/items': <String, Object?>{
          'get': <String, Object?>{'operationId': 'listItems'},
          'parameters': <Object?>[],
        },
      },
    });

    final List<OpenApiEndpoint> endpoints =
        const OpenApiImporter().endpoints(document);
    expect(endpoints, hasLength(1));
    expect(endpoints.single.method, 'GET');
    expect(endpoints.single.operationId, 'listItems');
  });
}
