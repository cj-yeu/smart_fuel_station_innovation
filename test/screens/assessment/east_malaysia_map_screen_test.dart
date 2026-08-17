import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuell_station_innovation/models/assessment_site_candidate.dart';
import 'package:smart_fuell_station_innovation/models/east_malaysia_site_validation_result.dart';
import 'package:smart_fuell_station_innovation/models/east_malaysia_territory.dart';
import 'package:smart_fuell_station_innovation/models/geo_point.dart';
import 'package:smart_fuell_station_innovation/screens/assessment/east_malaysia_map_screen.dart';

void main() {
  final firstPoint = GeoPoint(latitude: 5.9804, longitude: 116.0735);
  final secondPoint = GeoPoint(latitude: 1.5533, longitude: 110.3592);

  testWidgets('validation is disabled until an injected point is selected', (
    tester,
  ) async {
    await pumpMapScreen(
      tester,
      validator: ({required point, required analysisRadiusKm}) {
        throw StateError('Validator must not be called without a point.');
      },
    );

    final validateButton = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('validate-site-button')),
    );
    final confirmButton = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('use-candidate-button')),
    );

    expect(validateButton.onPressed, isNull);
    expect(confirmButton.onPressed, isNull);
    expect(find.text('Not yet geographically validated'), findsOneWidget);
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.byType(TileLayer), findsNothing);
  });

  testWidgets(
    'pending validation sends exact input once and locks interaction',
    (tester) async {
      final completer = Completer<EastMalaysiaSiteValidationResult>();
      var callCount = 0;
      GeoPoint? receivedPoint;
      double? receivedRadius;

      await pumpMapScreen(
        tester,
        validator: ({required point, required analysisRadiusKm}) {
          callCount++;
          receivedPoint = point;
          receivedRadius = analysisRadiusKm;
          return completer.future;
        },
        mapContentBuilder: selectionBuilder(firstPoint, secondPoint),
      );

      await tester.tap(find.text('Select first'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('validate-site-button')));
      await tester.pump();

      expect(callCount, 1);
      expect(receivedPoint, firstPoint);
      expect(receivedRadius, 5);
      expect(find.text('Validating...'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const ValueKey('validate-site-button')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const ValueKey('use-candidate-button')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<DropdownButton<double>>(
              find.byKey(const ValueKey('analysis-radius-dropdown')),
            )
            .onChanged,
        isNull,
      );

      await tester.tap(find.text('Select second'));
      await tester.tap(
        find.byKey(const ValueKey('validate-site-button')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(callCount, 1);
      expect(find.textContaining('5.98040'), findsOneWidget);
      expect(find.textContaining('1.55330'), findsNothing);

      completer.complete(
        validationResult(
          status: GeographicValidationStatus.inside,
          point: firstPoint,
          territory: EastMalaysiaTerritory.sabah,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Confirmed in Sabah'), findsOneWidget);
    },
  );

  for (final territory in EastMalaysiaTerritory.values) {
    testWidgets('inside displays exact ${territory.displayLabel} label', (
      tester,
    ) async {
      final result = validationResult(
        status: GeographicValidationStatus.inside,
        point: firstPoint,
        territory: territory,
      );
      await pumpMapScreen(
        tester,
        validator: ({required point, required analysisRadiusKm}) async =>
            result,
        mapContentBuilder: selectionBuilder(firstPoint, secondPoint),
      );

      await selectAndValidate(tester);

      expect(
        find.text('Confirmed in ${territory.displayLabel}'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const ValueKey('use-candidate-button')),
            )
            .onPressed,
        isNotNull,
      );
    });
  }

  testWidgets('confirmation returns the exact result and dataset ID', (
    tester,
  ) async {
    final expectedResult = validationResult(
      status: GeographicValidationStatus.inside,
      point: firstPoint,
      territory: EastMalaysiaTerritory.sabah,
    );
    EastMalaysiaSiteValidationResult? returnedResult;

    await pumpMapRoute(
      tester,
      validator: ({required point, required analysisRadiusKm}) async =>
          expectedResult,
      mapContentBuilder: selectionBuilder(firstPoint, secondPoint),
      onReturned: (result) => returnedResult = result,
    );

    await tester.tap(find.text('Open map'));
    await tester.pumpAndSettle();
    await selectAndValidate(tester);
    await tester.tap(find.byKey(const ValueKey('use-candidate-button')));
    await tester.pumpAndSettle();

    expect(returnedResult, same(expectedResult));
    expect(returnedResult!.boundaryDatasetId, datasetId);
  });

  final rejectedStatuses =
      <
        GeographicValidationStatus,
        ({String label, EastMalaysiaTerritory? territory})
      >{
        GeographicValidationStatus.outside: (
          label: 'Outside the supported East Malaysia territories',
          territory: null,
        ),
        GeographicValidationStatus.unverified: (
          label:
              'Unable to verify yet because authoritative boundary data is unavailable',
          territory: null,
        ),
        GeographicValidationStatus.boundaryReviewRequired: (
          label: 'Boundary review required',
          territory: null,
        ),
      };

  for (final entry in rejectedStatuses.entries) {
    testWidgets('${entry.key.name} is displayed and cannot be confirmed', (
      tester,
    ) async {
      final result = validationResult(status: entry.key, point: firstPoint);
      await pumpMapScreen(
        tester,
        validator: ({required point, required analysisRadiusKm}) async =>
            result,
        mapContentBuilder: selectionBuilder(firstPoint, secondPoint),
      );

      await selectAndValidate(tester);

      expect(find.text(entry.value.label), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const ValueKey('use-candidate-button')),
            )
            .onPressed,
        isNull,
      );
    });
  }

  testWidgets('failure is neutral and retry can succeed', (tester) async {
    var callCount = 0;
    final success = validationResult(
      status: GeographicValidationStatus.inside,
      point: firstPoint,
      territory: EastMalaysiaTerritory.sabah,
    );
    await pumpMapScreen(
      tester,
      validator: ({required point, required analysisRadiusKm}) async {
        callCount++;
        if (callCount == 1) {
          throw StateError('Sensitive PostgREST company detail');
        }
        return success;
      },
      mapContentBuilder: selectionBuilder(firstPoint, secondPoint),
    );

    await selectAndValidate(tester);
    expect(
      find.text('Unable to validate this site. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Sensitive PostgREST'), findsNothing);
    expect(find.textContaining('5.98040'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('validate-site-button')));
    await tester.pumpAndSettle();
    expect(callCount, 2);
    expect(find.text('Confirmed in Sabah'), findsOneWidget);
  });

  testWidgets('point and radius changes clear a successful validation', (
    tester,
  ) async {
    var nextPoint = firstPoint;
    var nextRadius = 5.0;
    await pumpMapScreen(
      tester,
      validator: ({required point, required analysisRadiusKm}) async {
        nextPoint = point;
        nextRadius = analysisRadiusKm;
        return validationResult(
          status: GeographicValidationStatus.inside,
          point: point,
          radius: analysisRadiusKm,
          territory: EastMalaysiaTerritory.sabah,
        );
      },
      mapContentBuilder: selectionBuilder(firstPoint, secondPoint),
    );

    await selectAndValidate(tester);
    expect(find.text('Confirmed in Sabah'), findsOneWidget);

    await tester.tap(find.text('Select second'));
    await tester.pump();
    expect(find.text('Not yet geographically validated'), findsOneWidget);
    expect(find.textContaining('1.55330'), findsOneWidget);
    expect(nextPoint, firstPoint);

    await tester.tap(find.byKey(const ValueKey('validate-site-button')));
    await tester.pumpAndSettle();
    expect(find.text('Confirmed in Sabah'), findsOneWidget);
    expect(nextPoint, secondPoint);

    await tester.tap(find.byKey(const ValueKey('analysis-radius-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 km').last);
    await tester.pumpAndSettle();
    expect(find.text('Not yet geographically validated'), findsOneWidget);
    expect(find.textContaining('1.55330'), findsOneWidget);
    expect(nextRadius, 5);
  });

  testWidgets('initial inside result is restored and cancel returns null', (
    tester,
  ) async {
    final initialResult = validationResult(
      status: GeographicValidationStatus.inside,
      point: secondPoint,
      radius: 10,
      territory: EastMalaysiaTerritory.sarawak,
    );
    EastMalaysiaSiteValidationResult? returnedResult = initialResult;

    await pumpMapRoute(
      tester,
      initialValidationResult: initialResult,
      validator: ({required point, required analysisRadiusKm}) async =>
          initialResult,
      mapContentBuilder: selectionBuilder(firstPoint, secondPoint),
      onReturned: (result) => returnedResult = result,
    );

    await tester.tap(find.text('Open map'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmed in Sarawak'), findsOneWidget);
    expect(find.textContaining('1.55330'), findsOneWidget);
    expect(find.text('10 km'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(returnedResult, isNull);
  });

  test('production layers preserve one marker and exact metre radius', () {
    final candidate = AssessmentSiteCandidate(
      point: firstPoint,
      analysisRadiusKm: 10,
      validationStatus: GeographicValidationStatus.unverified,
    );
    final layers = EastMalaysiaMapScreen.buildSelectionLayers(candidate);
    final markerLayer = layers.whereType<MarkerLayer>().single;
    final circleLayer = layers.whereType<CircleLayer>().single;

    expect(markerLayer.markers, hasLength(1));
    expect(circleLayer.circles, hasLength(1));
    expect(circleLayer.circles.single.radius, 10000);
    expect(circleLayer.circles.single.useRadiusInMeter, isTrue);
  });
}

const datasetId = '123e4567-e89b-12d3-a456-426614174000';

EastMalaysiaSiteValidationResult validationResult({
  required GeographicValidationStatus status,
  required GeoPoint point,
  double radius = 5,
  EastMalaysiaTerritory? territory,
}) {
  final statusValue = switch (status) {
    GeographicValidationStatus.unverified => 'unverified',
    GeographicValidationStatus.inside => 'inside',
    GeographicValidationStatus.outside => 'outside',
    GeographicValidationStatus.boundaryReviewRequired =>
      'boundary_review_required',
  };

  return EastMalaysiaSiteValidationResult.fromRpcRow(
    row: {
      'validation_status': statusValue,
      'confirmed_territory': territory?.storageValue,
      'boundary_dataset_id': status == GeographicValidationStatus.unverified
          ? null
          : datasetId,
    },
    point: point,
    analysisRadiusKm: radius,
  );
}

EastMalaysiaMapContentBuilder selectionBuilder(
  GeoPoint firstPoint,
  GeoPoint secondPoint,
) {
  return (context, candidate, onPointSelected) => Row(
    children: [
      ElevatedButton(
        onPressed: () => onPointSelected(firstPoint),
        child: const Text('Select first'),
      ),
      ElevatedButton(
        onPressed: () => onPointSelected(secondPoint),
        child: const Text('Select second'),
      ),
    ],
  );
}

Future<void> pumpMapScreen(
  WidgetTester tester, {
  required EastMalaysiaSiteValidator validator,
  EastMalaysiaMapContentBuilder? mapContentBuilder,
  EastMalaysiaSiteValidationResult? initialValidationResult,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: EastMalaysiaMapScreen(
        validator: validator,
        initialValidationResult: initialValidationResult,
        mapContentBuilder:
            mapContentBuilder ??
            (context, candidate, onPointSelected) => const ColoredBox(
              color: Colors.blueGrey,
              child: Text('Offline test map placeholder'),
            ),
      ),
    ),
  );
}

Future<void> selectAndValidate(WidgetTester tester) async {
  await tester.tap(find.text('Select first'));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('validate-site-button')));
  await tester.pumpAndSettle();
}

Future<void> pumpMapRoute(
  WidgetTester tester, {
  required EastMalaysiaSiteValidator validator,
  required EastMalaysiaMapContentBuilder mapContentBuilder,
  required ValueChanged<EastMalaysiaSiteValidationResult?> onReturned,
  EastMalaysiaSiteValidationResult? initialValidationResult,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: _MapRouteHost(
        validator: validator,
        mapContentBuilder: mapContentBuilder,
        initialValidationResult: initialValidationResult,
        onReturned: onReturned,
      ),
    ),
  );
}

class _MapRouteHost extends StatelessWidget {
  final EastMalaysiaSiteValidator validator;
  final EastMalaysiaMapContentBuilder mapContentBuilder;
  final EastMalaysiaSiteValidationResult? initialValidationResult;
  final ValueChanged<EastMalaysiaSiteValidationResult?> onReturned;

  const _MapRouteHost({
    required this.validator,
    required this.mapContentBuilder,
    required this.initialValidationResult,
    required this.onReturned,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final result =
                await Navigator.push<EastMalaysiaSiteValidationResult>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EastMalaysiaMapScreen(
                      validator: validator,
                      mapContentBuilder: mapContentBuilder,
                      initialValidationResult: initialValidationResult,
                    ),
                  ),
                );
            onReturned(result);
          },
          child: const Text('Open map'),
        ),
      ),
    );
  }
}
