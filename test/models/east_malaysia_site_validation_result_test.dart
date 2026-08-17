import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuell_station_innovation/models/assessment_site_candidate.dart';
import 'package:smart_fuell_station_innovation/models/east_malaysia_site_validation_result.dart';
import 'package:smart_fuell_station_innovation/models/east_malaysia_territory.dart';
import 'package:smart_fuell_station_innovation/models/geo_point.dart';

void main() {
  const datasetId = '123e4567-e89b-12d3-a456-426614174000';
  final point = GeoPoint(latitude: 5.9804, longitude: 116.0735);

  EastMalaysiaSiteValidationResult parse({
    required Object? status,
    Object? territory,
    Object? boundaryDatasetId,
    double radius = 5,
  }) {
    return EastMalaysiaSiteValidationResult.fromRpcRow(
      row: {
        'validation_status': status,
        'confirmed_territory': territory,
        'boundary_dataset_id': boundaryDatasetId,
      },
      point: point,
      analysisRadiusKm: radius,
    );
  }

  group('valid RPC results', () {
    test('empty-boundary response remains unverified', () {
      final result = parse(status: 'unverified');

      expect(
        result.candidate.validationStatus,
        GeographicValidationStatus.unverified,
      );
      expect(result.candidate.confirmedTerritory, isNull);
      expect(result.candidate.isValidatedInside, isFalse);
      expect(result.boundaryDatasetId, isNull);
    });

    for (final territory in EastMalaysiaTerritory.values) {
      test('inside parses ${territory.displayLabel}', () {
        final result = parse(
          status: 'inside',
          territory: territory.storageValue,
          boundaryDatasetId: datasetId,
        );

        expect(result.candidate.point, point);
        expect(result.candidate.confirmedTerritory, territory);
        expect(result.candidate.isValidatedInside, isTrue);
        expect(result.boundaryDatasetId, datasetId);
      });
    }

    test('outside requires provenance and remains outside', () {
      final result = parse(status: 'outside', boundaryDatasetId: datasetId);

      expect(
        result.candidate.validationStatus,
        GeographicValidationStatus.outside,
      );
      expect(result.candidate.confirmedTerritory, isNull);
      expect(result.candidate.isValidatedInside, isFalse);
      expect(result.boundaryDatasetId, datasetId);
    });

    test('boundary review requires provenance and is not inside', () {
      final result = parse(
        status: 'boundary_review_required',
        boundaryDatasetId: datasetId,
      );

      expect(
        result.candidate.validationStatus,
        GeographicValidationStatus.boundaryReviewRequired,
      );
      expect(result.candidate.confirmedTerritory, isNull);
      expect(result.candidate.isValidatedInside, isFalse);
      expect(result.boundaryDatasetId, datasetId);
    });

    for (final radius in <double>[3, 5, 10]) {
      test('accepts $radius km radius', () {
        final result = parse(status: 'unverified', radius: radius);

        expect(result.candidate.analysisRadiusKm, radius);
      });
    }
  });

  group('malformed RPC results', () {
    test('rejects an unknown status', () {
      expect(() => parse(status: 'trusted'), throwsFormatException);
    });

    test('rejects a missing status', () {
      expect(() => parse(status: null), throwsFormatException);
    });

    test('rejects an unknown territory', () {
      expect(
        () => parse(
          status: 'inside',
          territory: 'brunei',
          boundaryDatasetId: datasetId,
        ),
        throwsFormatException,
      );
    });

    test('rejects inside without a territory', () {
      expect(
        () => parse(status: 'inside', boundaryDatasetId: datasetId),
        throwsFormatException,
      );
    });

    test('rejects inside without a dataset ID', () {
      expect(
        () => parse(status: 'inside', territory: 'sabah'),
        throwsFormatException,
      );
    });

    test('rejects outside carrying a territory', () {
      expect(
        () => parse(
          status: 'outside',
          territory: 'sabah',
          boundaryDatasetId: datasetId,
        ),
        throwsFormatException,
      );
    });

    test('rejects outside without a dataset ID', () {
      expect(() => parse(status: 'outside'), throwsFormatException);
    });

    test('rejects boundary review carrying a territory', () {
      expect(
        () => parse(
          status: 'boundary_review_required',
          territory: 'sarawak',
          boundaryDatasetId: datasetId,
        ),
        throwsFormatException,
      );
    });

    test('rejects unverified carrying a territory', () {
      expect(
        () => parse(status: 'unverified', territory: 'labuan'),
        throwsFormatException,
      );
    });

    test('rejects unverified carrying a dataset ID', () {
      expect(
        () => parse(status: 'unverified', boundaryDatasetId: datasetId),
        throwsFormatException,
      );
    });

    test('rejects an empty dataset ID', () {
      expect(
        () =>
            parse(status: 'inside', territory: 'sabah', boundaryDatasetId: ''),
        throwsFormatException,
      );
    });

    test('rejects a malformed dataset UUID', () {
      expect(
        () => parse(
          status: 'inside',
          territory: 'sabah',
          boundaryDatasetId: 'not-a-uuid',
        ),
        throwsFormatException,
      );
    });
  });

  group('fail-closed domain behavior', () {
    for (final radius in <double>[2, 0, -3, double.nan, double.infinity]) {
      test('rejects unsupported radius $radius', () {
        expect(
          () => parse(status: 'unverified', radius: radius),
          throwsArgumentError,
        );
      });
    }

    test('does not infer territory from coordinates', () {
      final sabahPoint = GeoPoint(latitude: 5.9804, longitude: 116.0735);
      final result = EastMalaysiaSiteValidationResult.fromRpcRow(
        row: {
          'validation_status': 'unverified',
          'confirmed_territory': null,
          'boundary_dataset_id': null,
        },
        point: sabahPoint,
        analysisRadiusKm: 3,
      );

      expect(result.candidate.point, sabahPoint);
      expect(result.candidate.confirmedTerritory, isNull);
      expect(result.candidate.isValidatedInside, isFalse);
    });
  });
}
