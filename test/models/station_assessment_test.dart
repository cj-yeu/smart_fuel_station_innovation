import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuel_station_innovation/models/station_assessment.dart';
import 'package:smart_fuel_station_innovation/models/east_malaysia_territory.dart';
import 'package:smart_fuel_station_innovation/models/geo_point.dart';

void main() {
  group('StationAssessment.fromMap', () {
    test('parses every existing field with a non-null company_id', () {
      final assessment = StationAssessment.fromMap({
        ...assessmentRow(),
        'company_id': '10000000-0000-0000-0000-000000000001',
      });

      expect(assessment.id, '30000000-0000-0000-0000-000000000001');
      expect(assessment.userId, '20000000-0000-0000-0000-000000000001');
      expect(assessment.companyId, '10000000-0000-0000-0000-000000000001');
      expect(assessment.locationName, 'Kota Kinabalu test site');
      expect(assessment.populationDensity, 1234.5);
      expect(assessment.trafficLevel, 4);
      expect(assessment.registeredVehicleCount, 25000);
      expect(assessment.nearbyFuelStations, 2);
      expect(assessment.competitorDistanceKm, 4.25);
      expect(assessment.roadAccessibility, 5);
      expect(assessment.commercialActivity, 4);
      expect(assessment.residentialActivity, 3);
      expect(assessment.landAccessibility, 2);
      expect(assessment.finalScore, 72.3);
      expect(assessment.suitabilityCategory, 'Good');
      expect(assessment.recommendation, 'Test recommendation');
      expect(assessment.explanation, 'Test explanation');
      expect(assessment.createdAt, DateTime.parse('2026-08-16T01:02:03.000Z'));
      expect(assessment.updatedAt, DateTime.parse('2026-08-16T04:05:06.000Z'));
      expect(
        assessment.geographicValidationStatus,
        StationAssessmentGeographicStatus.legacyUnverified,
      );
      expect(assessment.siteLocation, isNull);
    });

    test('parses a legacy row with a null company_id', () {
      final assessment = StationAssessment.fromMap({
        ...assessmentRow(),
        'company_id': null,
      });

      expect(assessment.companyId, isNull);
      expect(assessment.locationName, 'Kota Kinabalu test site');
      expect(assessment.finalScore, 72.3);
    });

    test('parses a legacy-shaped row with no company_id key', () {
      final assessment = StationAssessment.fromMap(assessmentRow());

      expect(assessment.companyId, isNull);
      expect(assessment.userId, '20000000-0000-0000-0000-000000000001');
      expect(assessment.createdAt, isA<DateTime>());
      expect(
        assessment.geographicValidationStatus,
        StationAssessmentGeographicStatus.legacyUnverified,
      );
    });

    test('parses an authoritative inside geography state', () {
      final assessment = StationAssessment.fromMap({
        ...assessmentRow(),
        'company_id': '10000000-0000-0000-0000-000000000001',
        'site_location': '{"type":"Point","coordinates":[116.0735,5.9804]}',
        'analysis_radius_km': 5,
        'geographic_validation_status': 'inside',
        'confirmed_territory': 'sabah',
        'boundary_dataset_id': 'de8b4433-7315-5e60-8195-1d76744765eb',
        'geographically_validated_at': '2026-08-18T01:02:03.000Z',
      });

      expect(
        assessment.siteLocation,
        GeoPoint(latitude: 5.9804, longitude: 116.0735),
      );
      expect(assessment.analysisRadiusKm, 5);
      expect(
        assessment.geographicValidationStatus,
        StationAssessmentGeographicStatus.inside,
      );
      expect(assessment.confirmedTerritory, EastMalaysiaTerritory.sabah);
      expect(
        assessment.boundaryDatasetId,
        'de8b4433-7315-5e60-8195-1d76744765eb',
      );
      expect(
        assessment.geographicallyValidatedAt,
        DateTime.parse('2026-08-18T01:02:03.000Z'),
      );
    });

    test('parses the PostgREST EWKB geography wire representation', () {
      final assessment = StationAssessment.fromMap({
        ...validatedInsideRow(),
        'site_location': '0101000020E610000062105839B4045D405DFE43FAEDEB1740',
      });

      expect(
        assessment.siteLocation,
        GeoPoint(latitude: 5.9804, longitude: 116.0735),
      );
    });

    test('parses a bytea-prefixed EWKB Point representation', () {
      final assessment = StationAssessment.fromMap({
        ...validatedInsideRow(),
        'site_location':
            r'\x0101000020E610000062105839B4045D405DFE43FAEDEB1740',
      });

      expect(
        assessment.siteLocation,
        GeoPoint(latitude: 5.9804, longitude: 116.0735),
      );
    });

    test('parses big-endian EWKB Point with SRID 4326', () {
      final assessment = StationAssessment.fromMap({
        ...validatedInsideRow(),
        'site_location': ewkbPoint(
          latitude: 5.9804,
          longitude: 116.0735,
          endian: Endian.big,
        ),
      });

      expect(
        assessment.siteLocation,
        GeoPoint(latitude: 5.9804, longitude: 116.0735),
      );
    });

    test('rejects malformed or unsupported EWKB geography', () {
      final malformedValues = <String>[
        '',
        'not-hex',
        '0201000020E610000062105839B4045D405DFE43FAEDEB1740',
        '0101000020E610000062105839B4045D405DFE43FAEDEB17',
        '0101000020E610000062105839B4045D405DFE43FAEDEB174000',
        ewkbPoint(latitude: 5.9804, longitude: 116.0735, type: 2),
        ewkbPoint(latitude: 5.9804, longitude: 116.0735, type: 0xa0000001),
        ewkbPoint(latitude: 5.9804, longitude: 116.0735, type: 0x60000001),
        '01e903000062105839b4045d405dfe43faedeb17400000000000000000',
        ewkbPoint(latitude: 5.9804, longitude: 116.0735, srid: 3857),
        ewkbPoint(latitude: double.nan, longitude: 116.0735),
        ewkbPoint(latitude: double.infinity, longitude: 116.0735),
        ewkbPoint(latitude: 5.9804, longitude: double.negativeInfinity),
        ewkbPoint(latitude: 91, longitude: 116.0735),
      ];

      for (final value in malformedValues) {
        expect(
          () => StationAssessment.fromMap({
            ...validatedInsideRow(),
            'site_location': value,
          }),
          throwsFormatException,
          reason: value,
        );
      }
    });

    test('parses deployed legacy_unverified null geography', () {
      final assessment = StationAssessment.fromMap({
        ...assessmentRow(),
        'site_location': null,
        'analysis_radius_km': null,
        'geographic_validation_status': 'legacy_unverified',
        'confirmed_territory': null,
        'boundary_dataset_id': null,
        'geographically_validated_at': null,
      });

      expect(
        assessment.geographicValidationStatus,
        StationAssessmentGeographicStatus.legacyUnverified,
      );
      expect(assessment.siteLocation, isNull);
    });

    test('fails closed for inconsistent authoritative geography', () {
      expect(
        () => StationAssessment.fromMap({
          ...assessmentRow(),
          'site_location': {
            'type': 'Point',
            'coordinates': [116.0735, 5.9804],
          },
          'analysis_radius_km': 5,
          'geographic_validation_status': 'inside',
          'confirmed_territory': null,
          'boundary_dataset_id': 'de8b4433-7315-5e60-8195-1d76744765eb',
          'geographically_validated_at': '2026-08-18T01:02:03.000Z',
        }),
        throwsFormatException,
      );
    });

    test('does not infer territory from coordinates', () {
      final assessment = StationAssessment.fromMap({
        ...assessmentRow(),
        'site_location': {
          'type': 'Point',
          'coordinates': [116.0735, 5.9804],
        },
        'analysis_radius_km': 3,
        'geographic_validation_status': 'unverified',
        'confirmed_territory': null,
        'boundary_dataset_id': null,
        'geographically_validated_at': null,
      });

      expect(assessment.confirmedTerritory, isNull);
      expect(
        assessment.geographicValidationStatus,
        StationAssessmentGeographicStatus.unverified,
      );
    });

    for (final status in <String>['outside', 'boundary_review_required']) {
      test(
        'parses a valid $status geography state without treating it as inside',
        () {
          final assessment = StationAssessment.fromMap(
            validatedNonInsideRow(status: status),
          );

          expect(
            assessment.siteLocation,
            GeoPoint(latitude: 1.5533, longitude: 110.3592),
          );
          expect(assessment.confirmedTerritory, isNull);
          expect(
            assessment.geographicValidationStatus,
            status == 'outside'
                ? StationAssessmentGeographicStatus.outside
                : StationAssessmentGeographicStatus.boundaryReviewRequired,
          );
          expect(
            assessment.geographicValidationStatus,
            isNot(StationAssessmentGeographicStatus.inside),
          );
        },
      );

      for (final missingField in <String>[
        'boundary_dataset_id',
        'geographically_validated_at',
      ]) {
        test('rejects $status without $missingField', () {
          final row = validatedNonInsideRow(status: status)
            ..[missingField] = null;

          expect(() => StationAssessment.fromMap(row), throwsFormatException);
        });
      }

      test('rejects $status with a confirmed territory', () {
        final row = validatedNonInsideRow(status: status)
          ..['confirmed_territory'] = 'sarawak';

        expect(() => StationAssessment.fromMap(row), throwsFormatException);
      });
    }

    test('rejects a malformed boundary dataset UUID', () {
      final row = validatedNonInsideRow(status: 'outside')
        ..['boundary_dataset_id'] = 'not-a-uuid';

      expect(() => StationAssessment.fromMap(row), throwsFormatException);
    });

    test('rejects a malformed geographic validation timestamp', () {
      final row = validatedNonInsideRow(status: 'outside')
        ..['geographically_validated_at'] = 'not-a-timestamp';

      expect(() => StationAssessment.fromMap(row), throwsFormatException);
    });
  });
}

Map<String, dynamic> validatedNonInsideRow({required String status}) {
  return {
    ...assessmentRow(),
    'company_id': '10000000-0000-0000-0000-000000000001',
    'site_location': {
      'type': 'Point',
      'coordinates': [110.3592, 1.5533],
    },
    'analysis_radius_km': 10,
    'geographic_validation_status': status,
    'confirmed_territory': null,
    'boundary_dataset_id': 'de8b4433-7315-5e60-8195-1d76744765eb',
    'geographically_validated_at': '2026-08-18T01:02:03.000Z',
  };
}

Map<String, dynamic> validatedInsideRow() {
  return {
    ...assessmentRow(),
    'company_id': '10000000-0000-0000-0000-000000000001',
    'site_location': {
      'type': 'Point',
      'coordinates': [116.0735, 5.9804],
    },
    'analysis_radius_km': 5,
    'geographic_validation_status': 'inside',
    'confirmed_territory': 'sabah',
    'boundary_dataset_id': 'de8b4433-7315-5e60-8195-1d76744765eb',
    'geographically_validated_at': '2026-08-18T01:02:03.000Z',
    'validated_create_request_id': '73000000-0000-0000-0000-000000000001',
  };
}

String ewkbPoint({
  required double latitude,
  required double longitude,
  Endian endian = Endian.little,
  int type = 0x20000001,
  int srid = 4326,
}) {
  final bytes = Uint8List(25);
  final data = ByteData.sublistView(bytes);
  bytes[0] = endian == Endian.little ? 1 : 0;
  data.setUint32(1, type, endian);
  data.setUint32(5, srid, endian);
  data.setFloat64(9, longitude, endian);
  data.setFloat64(17, latitude, endian);
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

Map<String, dynamic> assessmentRow() {
  return {
    'id': '30000000-0000-0000-0000-000000000001',
    'user_id': '20000000-0000-0000-0000-000000000001',
    'location_name': 'Kota Kinabalu test site',
    'population_density': 1234.5,
    'traffic_level': 4,
    'registered_vehicle_count': 25000,
    'nearby_fuel_stations': 2,
    'competitor_distance_km': 4.25,
    'road_accessibility': 5,
    'commercial_activity': 4,
    'residential_activity': 3,
    'land_accessibility': 2,
    'final_score': 72.3,
    'suitability_category': 'Good',
    'recommendation': 'Test recommendation',
    'explanation': 'Test explanation',
    'created_at': '2026-08-16T01:02:03.000Z',
    'updated_at': '2026-08-16T04:05:06.000Z',
  };
}
