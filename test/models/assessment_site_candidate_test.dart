import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuell_station_innovation/models/assessment_site_candidate.dart';
import 'package:smart_fuell_station_innovation/models/east_malaysia_territory.dart';
import 'package:smart_fuell_station_innovation/models/geo_point.dart';

void main() {
  group('GeoPoint', () {
    test('accepts a valid coordinate', () {
      final point = GeoPoint(latitude: 5.9804, longitude: 116.0735);

      expect(point.latitude, 5.9804);
      expect(point.longitude, 116.0735);
    });

    test('accepts latitude boundaries', () {
      expect(GeoPoint(latitude: -90, longitude: 0).latitude, -90);
      expect(GeoPoint(latitude: 90, longitude: 0).latitude, 90);
    });

    test('accepts longitude boundaries', () {
      expect(GeoPoint(latitude: 0, longitude: -180).longitude, -180);
      expect(GeoPoint(latitude: 0, longitude: 180).longitude, 180);
    });

    test('rejects out-of-range latitude and longitude', () {
      expect(
        () => GeoPoint(latitude: -90.1, longitude: 0),
        throwsArgumentError,
      );
      expect(() => GeoPoint(latitude: 90.1, longitude: 0), throwsArgumentError);
      expect(
        () => GeoPoint(latitude: 0, longitude: -180.1),
        throwsArgumentError,
      );
      expect(
        () => GeoPoint(latitude: 0, longitude: 180.1),
        throwsArgumentError,
      );
    });

    test('rejects NaN and infinite coordinates', () {
      for (final invalidValue in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => GeoPoint(latitude: invalidValue, longitude: 0),
          throwsArgumentError,
        );
        expect(
          () => GeoPoint(latitude: 0, longitude: invalidValue),
          throwsArgumentError,
        );
      }
    });

    test('uses coordinate value equality and hash codes', () {
      final first = GeoPoint(latitude: 5.9804, longitude: 116.0735);
      final same = GeoPoint(latitude: 5.9804, longitude: 116.0735);
      final different = GeoPoint(latitude: 5.9805, longitude: 116.0735);

      expect(first, same);
      expect(first.hashCode, same.hashCode);
      expect(first, isNot(different));
      expect(
        first.toString(),
        'GeoPoint(latitude: 5.9804, longitude: 116.0735)',
      );
    });
  });

  group('EastMalaysiaTerritory', () {
    test('provides stable storage values and display labels', () {
      expect(EastMalaysiaTerritory.sabah.storageValue, 'sabah');
      expect(EastMalaysiaTerritory.sabah.displayLabel, 'Sabah');
      expect(EastMalaysiaTerritory.sarawak.storageValue, 'sarawak');
      expect(EastMalaysiaTerritory.sarawak.displayLabel, 'Sarawak');
      expect(EastMalaysiaTerritory.labuan.storageValue, 'labuan');
      expect(EastMalaysiaTerritory.labuan.displayLabel, 'Labuan');
    });

    test('parses only exact supported storage values', () {
      expect(
        EastMalaysiaTerritory.fromStorageValue('sabah'),
        EastMalaysiaTerritory.sabah,
      );
      expect(
        EastMalaysiaTerritory.fromStorageValue('sarawak'),
        EastMalaysiaTerritory.sarawak,
      );
      expect(
        EastMalaysiaTerritory.fromStorageValue('labuan'),
        EastMalaysiaTerritory.labuan,
      );
    });

    test('rejects unknown territory storage values', () {
      for (final value in ['unknown', 'brunei', 'kalimantan', 'Sabah', '']) {
        expect(
          () => EastMalaysiaTerritory.fromStorageValue(value),
          throwsArgumentError,
        );
      }
    });
  });

  group('AssessmentSiteCandidate', () {
    test('accepts the supported 3, 5, and 10 kilometre radii', () {
      for (final radius in [3.0, 5.0, 10.0]) {
        final candidate = AssessmentSiteCandidate(
          point: testPoint,
          analysisRadiusKm: radius,
          validationStatus: GeographicValidationStatus.unverified,
        );

        expect(candidate.analysisRadiusKm, radius);
      }
    });

    test('rejects unsupported, non-finite, zero, and negative radii', () {
      for (final radius in [
        -5.0,
        0.0,
        2.0,
        4.0,
        11.0,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => AssessmentSiteCandidate(
            point: testPoint,
            analysisRadiusKm: radius,
            validationStatus: GeographicValidationStatus.unverified,
          ),
          throwsArgumentError,
        );
      }
    });

    test('represents a new selection as unverified without a territory', () {
      final candidate = AssessmentSiteCandidate(
        point: testPoint,
        analysisRadiusKm: 5,
        validationStatus: GeographicValidationStatus.unverified,
      );

      expect(candidate.validationStatus, GeographicValidationStatus.unverified);
      expect(candidate.confirmedTerritory, isNull);
      expect(candidate.isValidatedInside, isFalse);
    });

    test('represents validated Sabah, Sarawak, and Labuan candidates', () {
      for (final territory in EastMalaysiaTerritory.values) {
        final candidate = AssessmentSiteCandidate(
          point: testPoint,
          analysisRadiusKm: 5,
          validationStatus: GeographicValidationStatus.inside,
          confirmedTerritory: territory,
        );

        expect(candidate.confirmedTerritory, territory);
        expect(candidate.isValidatedInside, isTrue);
      }
    });

    test('rejects an inside candidate without a confirmed territory', () {
      expect(
        () => AssessmentSiteCandidate(
          point: testPoint,
          analysisRadiusKm: 5,
          validationStatus: GeographicValidationStatus.inside,
        ),
        throwsArgumentError,
      );
    });

    test('rejects outside or unverified candidates carrying a territory', () {
      for (final status in [
        GeographicValidationStatus.outside,
        GeographicValidationStatus.unverified,
      ]) {
        expect(
          () => AssessmentSiteCandidate(
            point: testPoint,
            analysisRadiusKm: 5,
            validationStatus: status,
            confirmedTerritory: EastMalaysiaTerritory.sabah,
          ),
          throwsArgumentError,
        );
      }
    });

    test('does not treat boundary review as validated inside', () {
      final candidate = AssessmentSiteCandidate(
        point: testPoint,
        analysisRadiusKm: 5,
        validationStatus: GeographicValidationStatus.boundaryReviewRequired,
      );

      expect(candidate.confirmedTerritory, isNull);
      expect(candidate.isValidatedInside, isFalse);
      expect(
        () => AssessmentSiteCandidate(
          point: testPoint,
          analysisRadiusKm: 5,
          validationStatus: GeographicValidationStatus.boundaryReviewRequired,
          confirmedTerritory: EastMalaysiaTerritory.labuan,
        ),
        throwsArgumentError,
      );
    });

    test('uses candidate value equality and hash codes', () {
      final first = AssessmentSiteCandidate(
        point: testPoint,
        analysisRadiusKm: 10,
        validationStatus: GeographicValidationStatus.inside,
        confirmedTerritory: EastMalaysiaTerritory.sabah,
      );
      final same = AssessmentSiteCandidate(
        point: GeoPoint(latitude: 5.9804, longitude: 116.0735),
        analysisRadiusKm: 10,
        validationStatus: GeographicValidationStatus.inside,
        confirmedTerritory: EastMalaysiaTerritory.sabah,
      );
      final different = AssessmentSiteCandidate(
        point: testPoint,
        analysisRadiusKm: 5,
        validationStatus: GeographicValidationStatus.inside,
        confirmedTerritory: EastMalaysiaTerritory.sabah,
      );

      expect(first, same);
      expect(first.hashCode, same.hashCode);
      expect(first, isNot(different));
    });
  });
}

final testPoint = GeoPoint(latitude: 5.9804, longitude: 116.0735);
