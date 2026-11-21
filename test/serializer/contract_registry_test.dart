import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:d_rocket_builder/src/serializer/contract_registry_emitter.dart';
import 'package:d_rocket_builder/src/serializer/contract_type.dart';
import 'package:d_rocket_builder/src/serializer/contract_type_collector.dart';
import 'package:test/test.dart';

void main() {
  final ContractType vehicle = ContractType.named(
    'VehicleResponse',
    libraryPath: 'lib/vehicle_response.dart',
  );
  final ContractType response = ContractType.generic(
    'ResponseModel',
    <ContractType>[vehicle],
    libraryPath: 'lib/response_model.dart',
  );
  final ContractType responseList = ContractType.generic(
    'ResponseModel',
    <ContractType>[
      ContractType.generic(
        'List',
        <ContractType>[vehicle],
        libraryPath: 'dart:core',
      ),
    ],
    libraryPath: 'lib/response_model.dart',
  );

  test('collects concrete generic contract shapes once and in order', () {
    final List<ContractType> result =
        ContractTypeCollector.unique(<ContractType>[
      responseList,
      response,
      response,
    ]);

    expect(
      result.map((ContractType type) => type.displayName),
      <String>[
        'ResponseModel<List<VehicleResponse>>',
        'ResponseModel<VehicleResponse>',
      ],
    );
  });

  test('emits concrete generic registrations with nested list decoding', () {
    final String output = ContractRegistryEmitter.emit(
      <ContractType>[response, responseList],
      importIndexes: <String, int>{
        'lib/response_model.dart': 0,
        'lib/vehicle_response.dart': 1,
      },
    );

    expect(
        output,
        contains(
          '_m0.registerResponseModelSerializer<_m1.VehicleResponse>',
        ));
    expect(
        output,
        contains(
          '_m0.registerResponseModelSerializer<List<_m1.VehicleResponse>>',
        ));
    expect(
        output,
        contains(
          '(value as List<dynamic>).map((item) => '
          'Serializer.fromDynamic<_m1.VehicleResponse>(item)).toList()',
        ));
  });

  test('discovers generic return shapes from resolved client methods',
      () async {
    final Directory directory =
        await Directory.systemTemp.createTemp('d-rocket-contract-types-');
    final File source = File('${directory.path}/contracts.dart');
    await source.writeAsString('''
class VehicleResponse {}
class ResponseModel<T> { T? data; }
abstract class VehicleApi {
  Future<ResponseModel<VehicleResponse>> add();
  Future<ResponseModel<List<VehicleResponse>>> list();
}
''');
    final AnalysisContextCollection collection = AnalysisContextCollection(
      includedPaths: <String>[directory.path],
    );

    try {
      final SomeResolvedUnitResult result = await collection
          .contextFor(
            source.path,
          )
          .currentSession
          .getResolvedUnit(source.path);
      expect(result, isA<ResolvedUnitResult>());
      final LibraryElement library =
          (result as ResolvedUnitResult).libraryElement;
      final List<ContractType> found = ContractTypeCollector.fromClients(
        library.classes.where((ClassElement cls) => cls.name == 'VehicleApi'),
        genericLibraryPaths: <String, String>{
          'ResponseModel': 'lib/response_model.dart',
        },
      );

      expect(
        found.map((ContractType type) => type.displayName),
        <String>[
          'ResponseModel<List<VehicleResponse>>',
          'ResponseModel<VehicleResponse>',
        ],
      );
    } finally {
      await collection.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('uses each generic argument library instead of the envelope library',
      () async {
    final Directory directory =
        await Directory.systemTemp.createTemp('d-rocket-external-types-');
    final File envelope = File('${directory.path}/envelope.dart');
    final File item = File('${directory.path}/item.dart');
    final File api = File('${directory.path}/api.dart');
    await envelope.writeAsString('''
class Envelope<T> { T? data; }
''');
    await item.writeAsString('''
class Item { String name = ''; }
''');
    await api.writeAsString('''
import 'envelope.dart';
import 'item.dart';
abstract class Api {
  Future<Envelope<List<Item>>> list();
  Future<Envelope<Object?>> delete();
}
''');
    final AnalysisContextCollection collection = AnalysisContextCollection(
      includedPaths: <String>[directory.path],
    );

    try {
      final SomeResolvedUnitResult result = await collection
          .contextFor(api.path)
          .currentSession
          .getResolvedUnit(api.path);
      expect(result, isA<ResolvedUnitResult>());
      final LibraryElement library =
          (result as ResolvedUnitResult).libraryElement;
      final List<ContractType> found = ContractTypeCollector.fromClients(
        library.classes.where((ClassElement cls) => cls.name == 'Api'),
        genericLibraryPaths: <String, String>{
          'Envelope': envelope.path,
        },
      );

      expect(
        found
            .map((ContractType type) =>
                '${type.displayName}:${type.libraryPath}')
            .toList(),
        <String>[
          'Envelope<List<Item>>:${envelope.path}',
          'Envelope<Object?>:${envelope.path}',
        ],
      );
      expect(found.first.typeArguments.single.libraryPath, equals('dart:core'));
      expect(
        found.first.typeArguments.single.typeArguments.single.libraryPath,
        equals(item.path),
      );
      expect(found.last.typeArguments.single.libraryPath, equals('dart:core'));
      expect(found.last.typeArguments.single.isNullable, isTrue);
    } finally {
      await collection.dispose();
      await directory.delete(recursive: true);
    }
  });
}
