import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuell_station_innovation/models/assessment_site_candidate.dart';
import 'package:smart_fuell_station_innovation/models/east_malaysia_site_validation_result.dart';
import 'package:smart_fuell_station_innovation/models/east_malaysia_map_selection.dart';
import 'package:smart_fuell_station_innovation/models/east_malaysia_territory.dart';
import 'package:smart_fuell_station_innovation/models/geo_point.dart';
import 'package:smart_fuell_station_innovation/models/nearby_fuel_station.dart';
import 'package:smart_fuell_station_innovation/models/nearby_fuel_station_result.dart';
import 'package:smart_fuell_station_innovation/models/site_factor_intelligence_result.dart';
import 'package:smart_fuell_station_innovation/screens/assessment/east_malaysia_map_screen.dart';
import 'package:url_launcher/url_launcher.dart';

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

  test('OSM attribution has the official external copyright link', () {
    final attribution = EastMalaysiaMapScreen.buildOsmAttribution();
    final source = attribution.source;

    expect(source.data, 'OpenStreetMap contributors');
    expect(attribution.onTap, isNotNull);
    expect(
      EastMalaysiaMapScreen.osmCopyrightUri.toString(),
      'https://www.openstreetmap.org/copyright',
    );
    expect(
      EastMalaysiaMapScreen.osmAttributionLaunchMode,
      LaunchMode.externalApplication,
    );
    expect(attribution.alignment, Alignment.bottomRight);
  });

  testWidgets(
    'boundary attribution exposes project and licence links without network',
    (tester) async {
      final launches = <({Uri uri, LaunchMode mode})>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                EastMalaysiaMapScreen.buildBoundaryAttribution(
                  launcher: (uri, {mode = LaunchMode.platformDefault}) async {
                    launches.add((uri: uri, mode: mode));
                    return true;
                  },
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Boundary validation: '), findsOneWidget);
      expect(find.text('geoBoundaries'), findsOneWidget);
      expect(find.text('CC BY 4.0'), findsOneWidget);
      expect(
        tester
            .widget<Align>(
              find.byKey(const ValueKey('boundary-data-attribution')),
            )
            .alignment,
        Alignment.bottomRight,
      );

      await tester.tap(
        find.byKey(const ValueKey('geoboundaries-attribution-link')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('cc-by-four-attribution-link')),
      );
      await tester.pump();

      expect(launches, [
        (
          uri: EastMalaysiaMapScreen.geoBoundariesProjectUri,
          mode: LaunchMode.externalApplication,
        ),
        (
          uri: EastMalaysiaMapScreen.ccByFourLicenceUri,
          mode: LaunchMode.externalApplication,
        ),
      ]);
    },
  );

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
      final validateButton = find.byKey(const ValueKey('validate-site-button'));
      await ensureMapPanelTargetMounted(tester, validateButton);
      await tester.tap(validateButton);
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

      final selectSecond = find.text('Select second');
      await ensureMapPanelTargetMounted(tester, selectSecond);
      await tester.tap(selectSecond);
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
    EastMalaysiaMapSelection? returnedResult;

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
    final useCandidateButton = find.byKey(
      const ValueKey('use-candidate-button'),
    );
    await ensureMapPanelTargetMounted(tester, useCandidateButton);
    await tester.tap(useCandidateButton);
    await tester.pumpAndSettle();

    expect(returnedResult!.validationResult, same(expectedResult));
    expect(returnedResult!.validationResult.boundaryDatasetId, datasetId);
    expect(returnedResult!.nearbyFuelStations, isNull);
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

    final validateButton = find.byKey(const ValueKey('validate-site-button'));
    await ensureMapPanelTargetMounted(tester, validateButton);
    await tester.tap(validateButton);
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

    final selectSecond = find.text('Select second');
    await ensureMapPanelTargetMounted(tester, selectSecond);
    await tester.tap(selectSecond);
    await tester.pump();
    expect(find.text('Not yet geographically validated'), findsOneWidget);
    expect(find.textContaining('1.55330'), findsOneWidget);
    expect(nextPoint, firstPoint);

    final validateButton = find.byKey(const ValueKey('validate-site-button'));
    await ensureMapPanelTargetMounted(tester, validateButton);
    await tester.tap(validateButton);
    await tester.pumpAndSettle();
    expect(find.text('Confirmed in Sabah'), findsOneWidget);
    expect(nextPoint, secondPoint);

    final radiusDropdown = find.byKey(
      const ValueKey('analysis-radius-dropdown'),
    );
    await ensureMapPanelTargetMounted(tester, radiusDropdown);
    await tester.tap(radiusDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 km').last);
    await tester.pumpAndSettle();
    expect(find.text('Not yet geographically validated'), findsOneWidget);
    expect(find.textContaining('1.55330'), findsOneWidget);
    expect(nextRadius, 5);
  });

  testWidgets('a new candidate restarts a pending nearby-station lookup', (
    tester,
  ) async {
    var lookupCount = 0;
    final pendingLookups = <Completer<NearbyFuelStationResult>>[];
    await pumpMapScreen(
      tester,
      validator: ({required point, required analysisRadiusKm}) async =>
          validationResult(
            status: GeographicValidationStatus.inside,
            point: point,
            radius: analysisRadiusKm,
            territory: EastMalaysiaTerritory.sabah,
          ),
      nearbyFuelStationLoader: (_) {
        lookupCount += 1;
        final pending = Completer<NearbyFuelStationResult>();
        pendingLookups.add(pending);
        return pending.future;
      },
      mapContentBuilder: selectionBuilder(firstPoint, secondPoint),
    );

    await tester.tap(find.text('Select first'));
    await tester.pump();
    final validateButton = find.byKey(const ValueKey('validate-site-button'));
    await ensureMapPanelTargetMounted(tester, validateButton);
    await tester.tap(validateButton);
    await tester.pump();
    expect(lookupCount, 1);

    final selectSecond = find.text('Select second');
    await ensureMapPanelTargetMounted(tester, selectSecond);
    await tester.tap(selectSecond);
    await tester.pump();
    await ensureMapPanelTargetMounted(tester, validateButton);
    await tester.tap(validateButton);
    await tester.pump();
    expect(lookupCount, 2);

    for (final pending in pendingLookups) {
      pending.completeError(StateError('Test lookup cancelled.'));
    }
  });

  testWidgets('a new validation restarts a pending site-data lookup', (
    tester,
  ) async {
    var siteDataCalls = 0;
    final pendingLookups = <Completer<SiteFactorIntelligenceResult>>[];
    await pumpMapScreen(
      tester,
      validator: ({required point, required analysisRadiusKm}) async =>
          validationResult(
            status: GeographicValidationStatus.inside,
            point: point,
            radius: analysisRadiusKm,
            territory: EastMalaysiaTerritory.sabah,
          ),
      nearbyFuelStationLoader: (_) async =>
          throw StateError('No test station result.'),
      siteFactorIntelligenceLoader: (_) {
        siteDataCalls += 1;
        final pending = Completer<SiteFactorIntelligenceResult>();
        pendingLookups.add(pending);
        return pending.future;
      },
      mapContentBuilder: selectionBuilder(firstPoint, secondPoint),
    );

    await tester.tap(find.text('Select first'));
    await tester.pump();
    final validateButton = find.byKey(const ValueKey('validate-site-button'));
    await ensureMapPanelTargetMounted(tester, validateButton);
    await tester.tap(validateButton);
    await tester.pump();
    await tester.pump();
    expect(siteDataCalls, 1);

    final selectSecond = find.text('Select second');
    await ensureMapPanelTargetMounted(tester, selectSecond);
    await tester.tap(selectSecond);
    await tester.pump();
    await ensureMapPanelTargetMounted(tester, validateButton);
    await tester.tap(validateButton);
    await tester.pump();
    await tester.pump();
    expect(siteDataCalls, 2);

    for (final pending in pendingLookups) {
      pending.completeError(StateError('Test site-data lookup cancelled.'));
    }
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
    EastMalaysiaMapSelection? returnedResult = EastMalaysiaMapSelection(
      validationResult: initialResult,
    );

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

    final cancelButton = find.text('Cancel');
    await ensureMapPanelTargetMounted(tester, cancelButton);
    await tester.tap(cancelButton);
    await tester.pumpAndSettle();
    expect(returnedResult, isNull);
  });

  testWidgets('portrait layout remains scrollable without overflow', (
    tester,
  ) async {
    await setTestViewport(tester, const Size(430, 932));
    final result = validationResult(
      status: GeographicValidationStatus.inside,
      point: firstPoint,
      territory: EastMalaysiaTerritory.sabah,
    );
    final selection = completeSelection(result, stationCount: 8);

    await pumpMapScreen(
      tester,
      validator: ({required point, required analysisRadiusKm}) async => result,
      initialSelection: selection,
      mapContentBuilder: selectionBuilder(firstPoint, secondPoint),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('portrait-map-layout')), findsOneWidget);
    expect(find.byKey(const ValueKey('landscape-map-layout')), findsNothing);
    expect(
      find.byKey(const ValueKey('east-malaysia-map-pane')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('map-page-scroll')), findsOneWidget);
    expect(find.text('Nearby fuel stations: 8'), findsOneWidget);

    final pageScroll = mapPageScrollable();
    final pageState = tester.state<ScrollableState>(pageScroll);
    expect(pageState.position.maxScrollExtent, greaterThan(0));
    final mapTopBeforeScroll = tester.getTopLeft(
      find.byKey(const ValueKey('east-malaysia-map-pane')),
    );
    await tester.drag(
      find.text('Sabah • Sarawak • Labuan'),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('east-malaysia-map-pane')))
          .dy,
      lessThan(mapTopBeforeScroll.dy),
    );
    final radiusLabel = find.text('Analysis radius:');
    await tester.scrollUntilVisible(radiusLabel, 120, scrollable: pageScroll);
    await tester.pumpAndSettle();
    expect(radiusLabel.hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('use-candidate-button')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape uses one scrollable page without overflow', (
    tester,
  ) async {
    await setTestViewport(tester, const Size(932, 430));
    final result = validationResult(
      status: GeographicValidationStatus.inside,
      point: firstPoint,
      territory: EastMalaysiaTerritory.sabah,
    );

    await pumpMapScreen(
      tester,
      validator: ({required point, required analysisRadiusKm}) async => result,
      initialSelection: completeSelection(result),
      mapContentBuilder: selectionBuilder(firstPoint, secondPoint),
    );
    await tester.pumpAndSettle();

    final landscape = find.byKey(const ValueKey('landscape-map-layout'));
    final mapPane = find.byKey(const ValueKey('east-malaysia-map-pane'));
    expect(landscape, findsOneWidget);
    expect(find.byKey(const ValueKey('portrait-map-layout')), findsNothing);
    expect(find.byKey(const ValueKey('map-page-scroll')), findsOneWidget);
    expect(tester.getSize(mapPane).width, greaterThan(800));
    await ensureMapPanelTargetMounted(
      tester,
      find.byKey(const ValueKey('cancel-map-button')),
    );
    expect(
      find.byKey(const ValueKey('cancel-map-button')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('use-candidate-button')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape Cancel is visible and returns null', (tester) async {
    await setTestViewport(tester, const Size(932, 430));
    final result = validationResult(
      status: GeographicValidationStatus.inside,
      point: secondPoint,
      radius: 10,
      territory: EastMalaysiaTerritory.sarawak,
    );
    EastMalaysiaMapSelection? returned = completeSelection(result);

    await pumpMapRoute(
      tester,
      validator: ({required point, required analysisRadiusKm}) async => result,
      mapContentBuilder: selectionBuilder(firstPoint, secondPoint),
      initialSelection: completeSelection(result),
      onReturned: (value) => returned = value,
    );
    await tester.tap(find.text('Open map'));
    await tester.pumpAndSettle();

    final cancelButton = find.byKey(const ValueKey('cancel-map-button'));
    await ensureMapPanelTargetMounted(tester, cancelButton);
    expect(cancelButton.hitTestable(), findsOneWidget);
    await tester.tap(cancelButton.hitTestable());
    await tester.pumpAndSettle();

    expect(returned, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'landscape Use returns the exact validation, evidence, and dataset ID',
    (tester) async {
      await setTestViewport(tester, const Size(932, 430));
      final result = validationResult(
        status: GeographicValidationStatus.inside,
        point: firstPoint,
        radius: 10,
        territory: EastMalaysiaTerritory.labuan,
      );
      final selection = completeSelection(result, stationCount: 7);
      EastMalaysiaMapSelection? returned;

      await pumpMapRoute(
        tester,
        validator: ({required point, required analysisRadiusKm}) async =>
            result,
        mapContentBuilder: selectionBuilder(firstPoint, secondPoint),
        initialSelection: selection,
        onReturned: (value) => returned = value,
      );
      await tester.tap(find.text('Open map'));
      await tester.pumpAndSettle();

      final useButton = find.byKey(const ValueKey('use-candidate-button'));
      await ensureMapPanelTargetMounted(tester, useButton);
      expect(useButton.hitTestable(), findsOneWidget);
      await tester.tap(useButton.hitTestable());
      await tester.pumpAndSettle();

      expect(returned, isNotNull);
      expect(returned!.validationResult, same(result));
      expect(returned!.validationResult.boundaryDatasetId, datasetId);
      expect(returned!.nearbyFuelStations, same(selection.nearbyFuelStations));
      expect(
        returned!.siteFactorIntelligence,
        same(selection.siteFactorIntelligence),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rotation preserves candidate state without invoking loaders again',
    (tester) async {
      await setTestViewport(tester, const Size(430, 932));
      var validationCalls = 0;
      var stationCalls = 0;
      var siteDataCalls = 0;
      late EastMalaysiaSiteValidationResult expectedValidation;
      late NearbyFuelStationResult expectedStations;
      late SiteFactorIntelligenceResult expectedSiteData;
      EastMalaysiaMapSelection? returned;

      await pumpMapRoute(
        tester,
        validator: ({required point, required analysisRadiusKm}) async {
          validationCalls++;
          expectedValidation = validationResult(
            status: GeographicValidationStatus.inside,
            point: point,
            radius: analysisRadiusKm,
            territory: EastMalaysiaTerritory.sabah,
          );
          return expectedValidation;
        },
        nearbyFuelStationLoader: (result) async {
          stationCalls++;
          expectedStations = nearbyResult(
            result.candidate.point,
            result.candidate.analysisRadiusKm,
          );
          return expectedStations;
        },
        siteFactorIntelligenceLoader: (result) async {
          siteDataCalls++;
          expectedSiteData = siteIntelligenceResult(
            result.candidate.point,
            result.candidate.analysisRadiusKm,
          );
          return expectedSiteData;
        },
        mapContentBuilder: selectionBuilder(firstPoint, secondPoint),
        onReturned: (value) => returned = value,
      );
      await tester.tap(find.text('Open map'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select first'));
      await tester.pump();
      final radiusDropdown = find.byKey(
        const ValueKey('analysis-radius-dropdown'),
      );
      await ensureMapPanelTargetMounted(tester, radiusDropdown);
      await tester.tap(radiusDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('10 km').last);
      await tester.pumpAndSettle();
      final validateButton = find.byKey(const ValueKey('validate-site-button'));
      await ensureMapPanelTargetMounted(tester, validateButton);
      await tester.tap(validateButton);
      await tester.pumpAndSettle();

      expect(validationCalls, 1);
      expect(stationCalls, 1);
      expect(siteDataCalls, 1);
      expect(find.textContaining('5.98040'), findsOneWidget);
      expect(find.text('Confirmed in Sabah'), findsOneWidget);
      expect(find.text('Nearby fuel stations: 6'), findsOneWidget);
      expect(tester.widget<DropdownButton<double>>(radiusDropdown).value, 10);

      tester.view.physicalSize = const Size(932, 430);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('landscape-map-layout')),
        findsOneWidget,
      );
      expect(find.textContaining('5.98040'), findsOneWidget);
      expect(find.text('Confirmed in Sabah'), findsOneWidget);
      expect(find.text('Nearby fuel stations: 6'), findsOneWidget);
      expect(tester.widget<DropdownButton<double>>(radiusDropdown).value, 10);
      expect(validationCalls, 1);
      expect(stationCalls, 1);
      expect(siteDataCalls, 1);

      tester.view.physicalSize = const Size(430, 932);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('portrait-map-layout')), findsOneWidget);
      expect(find.textContaining('5.98040'), findsOneWidget);
      expect(tester.widget<DropdownButton<double>>(radiusDropdown).value, 10);
      expect(validationCalls, 1);
      expect(stationCalls, 1);
      expect(siteDataCalls, 1);
      expect(tester.takeException(), isNull);

      final useButton = find.byKey(const ValueKey('use-candidate-button'));
      await ensureMapPanelTargetMounted(tester, useButton);
      expect(useButton.hitTestable(), findsOneWidget);
      await tester.tap(useButton.hitTestable());
      await tester.pumpAndSettle();

      expect(returned, isNotNull);
      expect(returned!.validationResult, same(expectedValidation));
      expect(returned!.validationResult.boundaryDatasetId, datasetId);
      expect(returned!.nearbyFuelStations, same(expectedStations));
      expect(returned!.siteFactorIntelligence, same(expectedSiteData));
    },
  );

  testWidgets('long station evidence remains bounded and scrollable', (
    tester,
  ) async {
    await setTestViewport(tester, const Size(700, 360));
    final result = validationResult(
      status: GeographicValidationStatus.inside,
      point: firstPoint,
      territory: EastMalaysiaTerritory.sabah,
    );

    await pumpMapScreen(
      tester,
      validator: ({required point, required analysisRadiusKm}) async => result,
      initialSelection: completeSelection(
        result,
        stationCount: 12,
        longStationNames: true,
      ),
      mapContentBuilder: selectionBuilder(firstPoint, secondPoint),
    );
    await tester.pumpAndSettle();

    final detailsScroll = mapPageScrollable();
    final toggle = find.byKey(
      const ValueKey('toggle-nearby-fuel-stations-button'),
    );
    await tester.scrollUntilVisible(toggle, 100, scrollable: detailsScroll);
    await tester.pumpAndSettle();
    await tester.tap(toggle.hitTestable());
    await tester.pumpAndSettle();

    final scrollState = tester.state<ScrollableState>(detailsScroll);
    expect(scrollState.position.maxScrollExtent, greaterThan(0));
    final lastStation = find.textContaining('Synthetic Station 12');
    await tester.scrollUntilVisible(
      lastStation,
      100,
      scrollable: detailsScroll,
    );
    await tester.pumpAndSettle();

    expect(lastStation.hitTestable(), findsOneWidget);
    await ensureMapPanelTargetMounted(
      tester,
      find.byKey(const ValueKey('cancel-map-button')),
    );
    expect(
      find.byKey(const ValueKey('cancel-map-button')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('use-candidate-button')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('bearing rotation is disabled while pan and zoom remain enabled', () {
    final options = EastMalaysiaMapScreen.buildMapInteractionOptions();
    final flags = options.flags;

    expect(InteractiveFlag.hasRotate(flags), isFalse);
    expect(InteractiveFlag.hasDrag(flags), isTrue);
    expect(InteractiveFlag.hasPinchMove(flags), isTrue);
    expect(InteractiveFlag.hasPinchZoom(flags), isTrue);
    expect(InteractiveFlag.hasDoubleTapZoom(flags), isTrue);
    expect(InteractiveFlag.hasDoubleTapDragZoom(flags), isTrue);
    expect(InteractiveFlag.hasScrollWheelZoom(flags), isTrue);
    expect(
      options.cursorKeyboardRotationOptions.isKeyTrigger!(
        LogicalKeyboardKey.control,
      ),
      isFalse,
    );
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
  return (context, candidate, onPointSelected) => Wrap(
    spacing: 8,
    runSpacing: 8,
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

Finder mapPageScrollable() {
  return find
      .descendant(
        of: find.byKey(const ValueKey('map-page-scroll')),
        matching: find.byType(Scrollable),
      )
      .first;
}

Future<void> setTestViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pump();
}

EastMalaysiaMapSelection completeSelection(
  EastMalaysiaSiteValidationResult validation, {
  int stationCount = 6,
  bool longStationNames = false,
}) {
  final point = validation.candidate.point;
  final radius = validation.candidate.analysisRadiusKm;
  return EastMalaysiaMapSelection(
    validationResult: validation,
    nearbyFuelStations: nearbyResult(
      point,
      radius,
      stationCount: stationCount,
      longStationNames: longStationNames,
    ),
    siteFactorIntelligence: siteIntelligenceResult(point, radius),
  );
}

NearbyFuelStationResult nearbyResult(
  GeoPoint point,
  double radius, {
  int stationCount = 6,
  bool longStationNames = false,
}) {
  final stations = List.generate(
    stationCount,
    (index) => NearbyFuelStation(
      osmType: 'node',
      osmId: '${index + 1}',
      name: longStationNames
          ? 'Synthetic Station ${index + 1} with a deliberately long evidence label'
          : 'Synthetic Station ${index + 1}',
      brand: null,
      operatorName: null,
      latitude: point.latitude + (index * 0.0001),
      longitude: point.longitude + (index * 0.0001),
      distanceKm: (index + 1) * 0.25,
    ),
    growable: false,
  );
  return NearbyFuelStationResult(
    source: NearbyFuelStationResult.sourceOpenStreetMap,
    attribution: NearbyFuelStationResult.openStreetMapAttribution,
    attributionUrl: NearbyFuelStationResult.openStreetMapAttributionUrl,
    fetchedAt: DateTime.utc(2026, 8, 31),
    analysisRadiusKm: radius,
    point: point,
    stationCount: stationCount,
    nearestDistanceKm: stations.isEmpty ? null : stations.first.distanceKm,
    stations: stations,
  );
}

SiteFactorIntelligenceResult siteIntelligenceResult(
  GeoPoint point,
  double radius,
) {
  return SiteFactorIntelligenceResult(
    point: point,
    analysisRadiusKm: radius,
    districtReference: null,
    population: const PopulationEvidence(
      available: true,
      estimatedPopulation: 125000,
      densityPerSqKm: 1500,
      suggestedLevel: 4,
      source: 'WorldPop',
      dataYear: 2025,
      confidence: SiteFactorConfidence.medium,
    ),
    roadAccessibility: RoadAccessibilityEvidence(
      available: true,
      nearestUsableRoadM: 35,
      majorRoadCount: 3,
      suggestedScore: 4,
      source: 'OpenStreetMap',
      fetchedAt: DateTime.utc(2026, 8, 31),
      confidence: SiteFactorConfidence.medium,
    ),
    commercialActivity: CommercialActivityEvidence(
      available: true,
      commercialPoiCount: 12,
      commercialLanduseCount: 2,
      suggestedScore: 4,
      source: 'OpenStreetMap',
      fetchedAt: DateTime.utc(2026, 8, 31),
      confidence: SiteFactorConfidence.medium,
    ),
    residentialActivity: ResidentialActivityEvidence(
      available: true,
      residentialFeatureCount: 20,
      residentialLanduseCount: 4,
      suggestedScore: 4,
      source: 'OpenStreetMap',
      fetchedAt: DateTime.utc(2026, 8, 31),
      confidence: SiteFactorConfidence.medium,
    ),
    landAccessibility: LandAccessibilityEvidence(
      available: true,
      nearestAccessRoadM: 45,
      restrictedAccessFeatureCount: 0,
      suggestedScore: 5,
      source: 'OpenStreetMap',
      fetchedAt: DateTime.utc(2026, 8, 31),
      confidence: SiteFactorConfidence.medium,
    ),
    vehicleDemand: const VehicleDemandProxy(
      available: true,
      value: 123456,
      geographicScope: 'Sabah',
      dataPeriod: '2025',
      isProxy: true,
      source: 'data.gov.my',
    ),
    attribution: const [
      SiteFactorAttribution(
        source: 'Synthetic test evidence',
        url: 'https://example.invalid/evidence',
        licence: 'Test only',
      ),
    ],
  );
}

Future<void> pumpMapScreen(
  WidgetTester tester, {
  required EastMalaysiaSiteValidator validator,
  EastMalaysiaMapContentBuilder? mapContentBuilder,
  EastMalaysiaSiteValidationResult? initialValidationResult,
  EastMalaysiaMapSelection? initialSelection,
  NearbyFuelStationLoader? nearbyFuelStationLoader,
  SiteFactorIntelligenceLoader? siteFactorIntelligenceLoader,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: EastMalaysiaMapScreen(
        validator: validator,
        nearbyFuelStationLoader:
            nearbyFuelStationLoader ??
            (_) async => throw StateError('No station loader configured.'),
        siteFactorIntelligenceLoader:
            siteFactorIntelligenceLoader ??
            (_) async => throw StateError('No site-data loader configured.'),
        initialValidationResult: initialValidationResult,
        initialSelection: initialSelection,
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
  final validateButton = find.byKey(const ValueKey('validate-site-button'));
  await ensureMapPanelTargetMounted(tester, validateButton);
  await tester.tap(validateButton);
  await tester.pumpAndSettle();
}

Future<void> ensureMapPanelTargetMounted(
  WidgetTester tester,
  Finder target,
) async {
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  // Some map tests intentionally keep provider work pending. One frame is
  // enough to apply the scroll without waiting for those pending futures.
  await tester.pump();
}

Future<void> pumpMapRoute(
  WidgetTester tester, {
  required EastMalaysiaSiteValidator validator,
  required EastMalaysiaMapContentBuilder mapContentBuilder,
  required ValueChanged<EastMalaysiaMapSelection?> onReturned,
  EastMalaysiaSiteValidationResult? initialValidationResult,
  EastMalaysiaMapSelection? initialSelection,
  NearbyFuelStationLoader? nearbyFuelStationLoader,
  SiteFactorIntelligenceLoader? siteFactorIntelligenceLoader,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: _MapRouteHost(
        validator: validator,
        mapContentBuilder: mapContentBuilder,
        initialValidationResult: initialValidationResult,
        initialSelection: initialSelection,
        nearbyFuelStationLoader: nearbyFuelStationLoader,
        siteFactorIntelligenceLoader: siteFactorIntelligenceLoader,
        onReturned: onReturned,
      ),
    ),
  );
}

class _MapRouteHost extends StatelessWidget {
  final EastMalaysiaSiteValidator validator;
  final EastMalaysiaMapContentBuilder mapContentBuilder;
  final EastMalaysiaSiteValidationResult? initialValidationResult;
  final EastMalaysiaMapSelection? initialSelection;
  final ValueChanged<EastMalaysiaMapSelection?> onReturned;
  final NearbyFuelStationLoader? nearbyFuelStationLoader;
  final SiteFactorIntelligenceLoader? siteFactorIntelligenceLoader;

  const _MapRouteHost({
    required this.validator,
    required this.mapContentBuilder,
    required this.initialValidationResult,
    required this.initialSelection,
    this.nearbyFuelStationLoader,
    this.siteFactorIntelligenceLoader,
    required this.onReturned,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final result = await Navigator.push<EastMalaysiaMapSelection>(
              context,
              MaterialPageRoute(
                builder: (context) => EastMalaysiaMapScreen(
                  validator: validator,
                  mapContentBuilder: mapContentBuilder,
                  initialValidationResult: initialValidationResult,
                  initialSelection: initialSelection,
                  nearbyFuelStationLoader:
                      nearbyFuelStationLoader ??
                      (_) async =>
                          throw StateError('No station loader configured.'),
                  siteFactorIntelligenceLoader:
                      siteFactorIntelligenceLoader ??
                      (_) async =>
                          throw StateError('No site-data loader configured.'),
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
