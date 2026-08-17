import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuell_station_innovation/models/assessment_site_candidate.dart';
import 'package:smart_fuell_station_innovation/models/east_malaysia_territory.dart';
import 'package:smart_fuell_station_innovation/models/geo_point.dart';
import 'package:smart_fuell_station_innovation/screens/assessment/east_malaysia_map_screen.dart';

void main() {
  final firstPoint = GeoPoint(latitude: 5.9804, longitude: 116.0735);
  final secondPoint = GeoPoint(latitude: 1.5533, longitude: 110.3592);

  testWidgets('starts unselected with only the supported radius choices', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EastMalaysiaMapScreen(
          mapContentBuilder: (context, candidate, onPointSelected) {
            expect(candidate, isNull);
            return const ColoredBox(
              key: ValueKey('injected-map-placeholder'),
              color: Colors.blueGrey,
              child: Center(child: Text('Offline test map placeholder')),
            );
          },
        ),
      ),
    );

    expect(find.text('East Malaysia Site Map'), findsOneWidget);
    expect(find.text('Sabah • Sarawak • Labuan'), findsOneWidget);
    expect(find.text('Not yet geographically validated'), findsOneWidget);
    expect(find.textContaining('analysis context'), findsOneWidget);
    expect(find.text('5 km'), findsOneWidget);

    final dropdown = tester.widget<DropdownButton<double>>(
      find.byKey(const ValueKey('analysis-radius-dropdown')),
    );
    expect(dropdown.value, 5);
    expect(dropdown.items!.map((item) => item.value), <double>[3, 5, 10]);

    final confirmButton = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('use-candidate-button')),
    );
    expect(confirmButton.onPressed, isNull);

    // The injection seam prevents construction of network tile widgets.
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.byType(TileLayer), findsNothing);
  });

  testWidgets(
    'selection and radius change return an exact unverified candidate',
    (tester) async {
      AssessmentSiteCandidate? returnedCandidate;
      await pumpMapRoute(
        tester,
        onReturned: (candidate) => returnedCandidate = candidate,
        mapContentBuilder: (context, candidate, onPointSelected) {
          return Center(
            child: ElevatedButton(
              onPressed: () => onPointSelected(firstPoint),
              child: const Text('Select injected point'),
            ),
          );
        },
      );

      await tester.tap(find.text('Open map'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select injected point'));
      await tester.pump();

      expect(find.textContaining('5.98040'), findsOneWidget);
      expect(find.textContaining('116.07350'), findsOneWidget);
      expect(find.text('Not yet geographically validated'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('analysis-radius-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10 km').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('5.98040'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('use-candidate-button')));
      await tester.pumpAndSettle();

      expect(returnedCandidate, isNotNull);
      expect(returnedCandidate!.point, firstPoint);
      expect(returnedCandidate!.analysisRadiusKm, 10);
      expect(
        returnedCandidate!.validationStatus,
        GeographicValidationStatus.unverified,
      );
      expect(returnedCandidate!.confirmedTerritory, isNull);
    },
  );

  testWidgets('repeated selections replace the previous point', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EastMalaysiaMapScreen(
          mapContentBuilder: (context, candidate, onPointSelected) => Row(
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
          ),
        ),
      ),
    );

    await tester.tap(find.text('Select first'));
    await tester.pump();
    expect(find.textContaining('5.98040'), findsOneWidget);

    await tester.tap(find.text('Select second'));
    await tester.pump();
    expect(find.textContaining('1.55330'), findsOneWidget);
    expect(find.textContaining('110.35920'), findsOneWidget);
    expect(find.textContaining('5.98040'), findsNothing);
  });

  testWidgets('restores an initial unverified point and radius', (
    tester,
  ) async {
    final initialCandidate = AssessmentSiteCandidate(
      point: secondPoint,
      analysisRadiusKm: 3,
      validationStatus: GeographicValidationStatus.unverified,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EastMalaysiaMapScreen(
          initialCandidate: initialCandidate,
          mapContentBuilder: (context, candidate, onPointSelected) {
            expect(candidate, initialCandidate);
            return const SizedBox.expand();
          },
        ),
      ),
    );

    expect(find.textContaining('1.55330'), findsOneWidget);
    expect(find.textContaining('110.35920'), findsOneWidget);
    final dropdown = tester.widget<DropdownButton<double>>(
      find.byKey(const ValueKey('analysis-radius-dropdown')),
    );
    expect(dropdown.value, 3);
  });

  test('rejects an initial candidate that is already validated', () {
    final validatedCandidate = AssessmentSiteCandidate(
      point: firstPoint,
      analysisRadiusKm: 5,
      validationStatus: GeographicValidationStatus.inside,
      confirmedTerritory: EastMalaysiaTerritory.sabah,
    );

    expect(
      () => EastMalaysiaMapScreen(initialCandidate: validatedCandidate),
      throwsArgumentError,
    );
  });

  testWidgets('cancel returns no candidate', (tester) async {
    AssessmentSiteCandidate? returnedCandidate = AssessmentSiteCandidate(
      point: firstPoint,
      analysisRadiusKm: 5,
      validationStatus: GeographicValidationStatus.unverified,
    );

    await pumpMapRoute(
      tester,
      onReturned: (candidate) => returnedCandidate = candidate,
      mapContentBuilder: (context, candidate, onPointSelected) => Center(
        child: ElevatedButton(
          onPressed: () => onPointSelected(firstPoint),
          child: const Text('Select injected point'),
        ),
      ),
    );

    await tester.tap(find.text('Open map'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select injected point'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(returnedCandidate, isNull);
  });

  test(
    'production selection layers contain one marker and one metre circle',
    () {
      final candidate = AssessmentSiteCandidate(
        point: firstPoint,
        analysisRadiusKm: 10,
        validationStatus: GeographicValidationStatus.unverified,
      );

      expect(EastMalaysiaMapScreen.buildSelectionLayers(null), isEmpty);

      final layers = EastMalaysiaMapScreen.buildSelectionLayers(candidate);
      final markerLayer = layers.whereType<MarkerLayer>().single;
      final circleLayer = layers.whereType<CircleLayer>().single;

      expect(markerLayer.markers, hasLength(1));
      expect(circleLayer.circles, hasLength(1));
      expect(circleLayer.circles.single.radius, 10000);
      expect(circleLayer.circles.single.useRadiusInMeter, isTrue);
    },
  );
}

Future<void> pumpMapRoute(
  WidgetTester tester, {
  required ValueChanged<AssessmentSiteCandidate?> onReturned,
  required EastMalaysiaMapContentBuilder mapContentBuilder,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: _MapRouteHost(
        onReturned: onReturned,
        mapContentBuilder: mapContentBuilder,
      ),
    ),
  );
}

class _MapRouteHost extends StatelessWidget {
  final ValueChanged<AssessmentSiteCandidate?> onReturned;
  final EastMalaysiaMapContentBuilder mapContentBuilder;

  const _MapRouteHost({
    required this.onReturned,
    required this.mapContentBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final candidate = await Navigator.push<AssessmentSiteCandidate>(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    EastMalaysiaMapScreen(mapContentBuilder: mapContentBuilder),
              ),
            );
            onReturned(candidate);
          },
          child: const Text('Open map'),
        ),
      ),
    );
  }
}
