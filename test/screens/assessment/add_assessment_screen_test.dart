import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuell_station_innovation/models/east_malaysia_site_validation_result.dart';
import 'package:smart_fuell_station_innovation/models/east_malaysia_territory.dart';
import 'package:smart_fuell_station_innovation/models/geo_point.dart';
import 'package:smart_fuell_station_innovation/models/station_assessment.dart';
import 'package:smart_fuell_station_innovation/models/station_assessment_create_input.dart';
import 'package:smart_fuell_station_innovation/screens/assessment/add_assessment_screen.dart';
import 'package:smart_fuell_station_innovation/services/station_assessment_service.dart';

void main() {
  testWidgets('validated site can be restored, cancelled, and replaced', (
    tester,
  ) async {
    final firstResult = insideResult(
      point: GeoPoint(latitude: 5.9804, longitude: 116.0735),
      radius: 5,
      territory: EastMalaysiaTerritory.sabah,
      datasetId: firstDatasetId,
    );
    final replacementResult = insideResult(
      point: GeoPoint(latitude: 1.5533, longitude: 110.3592),
      radius: 10,
      territory: EastMalaysiaTerritory.sarawak,
      datasetId: replacementDatasetId,
    );
    final receivedInitialResults = <EastMalaysiaSiteValidationResult?>[];

    await pumpAddAssessment(
      tester,
      creator: (_) async => persistedAssessment,
      mapScreenBuilder: (context, initialValidationResult) {
        receivedInitialResults.add(initialValidationResult);
        return Scaffold(
          appBar: AppBar(title: const Text('Injected map screen')),
          body: Column(
            children: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel map'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(
                  context,
                  receivedInitialResults.length == 1
                      ? firstResult
                      : replacementResult,
                ),
                child: const Text('Return candidate'),
              ),
            ],
          ),
        );
      },
    );

    final mapButton = find.text('Select Site on Map');
    final formHeading = find.text('Location and Demand');
    expect(mapButton, findsOneWidget);
    expect(formHeading, findsOneWidget);
    expect(
      tester.getTopLeft(mapButton).dy,
      lessThan(tester.getTopLeft(formHeading).dy),
    );

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Kuching candidate');
    await tester.enterText(fields.at(1), '2468.5');

    await tester.tap(mapButton);
    await tester.pumpAndSettle();
    expect(find.text('Injected map screen'), findsOneWidget);
    expect(receivedInitialResults, <EastMalaysiaSiteValidationResult?>[null]);

    await tester.tap(find.text('Return candidate'));
    await tester.pumpAndSettle();

    expect(find.textContaining('5.98040'), findsOneWidget);
    expect(find.textContaining('116.07350'), findsOneWidget);
    expect(find.textContaining('Radius: 5 km'), findsOneWidget);
    expect(find.textContaining('Confirmed territory: Sabah'), findsOneWidget);
    expect(find.textContaining('Geographically validated'), findsOneWidget);
    expect(find.textContaining(firstDatasetId), findsNothing);

    await tester.tap(mapButton);
    await tester.pumpAndSettle();
    expect(receivedInitialResults.last, same(firstResult));
    await tester.tap(find.text('Cancel map'));
    await tester.pumpAndSettle();

    expect(find.textContaining('5.98040'), findsOneWidget);
    expect(find.textContaining('Radius: 5 km'), findsOneWidget);

    await tester.tap(mapButton);
    await tester.pumpAndSettle();
    expect(receivedInitialResults.last, same(firstResult));
    await tester.tap(find.text('Return candidate'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1.55330'), findsOneWidget);
    expect(find.textContaining('110.35920'), findsOneWidget);
    expect(find.textContaining('Radius: 10 km'), findsOneWidget);
    expect(find.textContaining('Confirmed territory: Sarawak'), findsOneWidget);
    expect(find.textContaining(replacementDatasetId), findsNothing);
    expect(find.text('Kuching candidate'), findsOneWidget);
    expect(find.text('2468.5'), findsOneWidget);
  });

  testWidgets('invalid form does not call the creator', (tester) async {
    var createCount = 0;

    await pumpAddAssessment(
      tester,
      creator: (_) async {
        createCount++;
        return persistedAssessment;
      },
    );

    await tapRunAssessment(tester);

    expect(createCount, 0);
    expect(find.text('Please fill in all fields'), findsOneWidget);
    expect(find.text('New Assessment'), findsOneWidget);
  });

  testWidgets('valid form sends exact input and opens the result screen', (
    tester,
  ) async {
    var createCount = 0;
    StationAssessmentCreateInput? receivedInput;

    await pumpAddAssessment(
      tester,
      creator: (input) async {
        createCount++;
        receivedInput = input;
        return persistedAssessment;
      },
    );
    await enterValidForm(tester);

    await tapRunAssessment(tester);

    final expectedResult = StationAssessmentService.calculate(
      populationDensity: 1234.5,
      trafficLevel: 3,
      registeredVehicleCount: 25000,
      nearbyFuelStations: 2,
      competitorDistanceKm: 4.25,
      roadAccessibility: 3,
      commercialActivity: 3,
      residentialActivity: 3,
      landAccessibility: 3,
    );
    final input = receivedInput!;

    expect(createCount, 1);
    expect(input.locationName, 'Kota Kinabalu');
    expect(input.populationDensity, 1234.5);
    expect(input.trafficLevel, 3);
    expect(input.registeredVehicleCount, 25000);
    expect(input.nearbyFuelStations, 2);
    expect(input.competitorDistanceKm, 4.25);
    expect(input.roadAccessibility, 3);
    expect(input.commercialActivity, 3);
    expect(input.residentialActivity, 3);
    expect(input.landAccessibility, 3);
    expect(input.finalScore, expectedResult.finalScore);
    expect(input.suitabilityCategory, expectedResult.category);
    expect(input.recommendation, expectedResult.recommendation);
    expect(input.explanation, expectedResult.explanation);
    expect(input.toInsertMap(), isNot(contains('id')));
    expect(input.toInsertMap(), isNot(contains('user_id')));
    expect(input.toInsertMap(), isNot(contains('company_id')));
    expect(find.text('Assessment Result'), findsOneWidget);
    expect(find.text('Kota Kinabalu'), findsOneWidget);
  });

  testWidgets('pending creation disables repeated submission', (tester) async {
    var createCount = 0;
    final completer = Completer<StationAssessment>();

    await pumpAddAssessment(
      tester,
      creator: (_) {
        createCount++;
        return completer.future;
      },
    );
    await enterValidForm(tester);

    await tester.tap(find.byKey(const ValueKey('run-assessment-button')));
    await tester.pump();

    expect(createCount, 1);
    expect(find.text('Assessing...'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('run-assessment-button')),
    );
    expect(button.onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey('run-assessment-button')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(createCount, 1);

    completer.complete(persistedAssessment);
    await tester.pumpAndSettle();
    expect(find.text('Assessment Result'), findsOneWidget);
  });

  testWidgets('failure stays neutral and enables retry', (tester) async {
    var createCount = 0;

    await pumpAddAssessment(
      tester,
      creator: (_) async {
        createCount++;
        if (createCount == 1) {
          throw StateError(
            'Sensitive backend user/company authentication detail',
          );
        }
        return persistedAssessment;
      },
    );
    await enterValidForm(tester);

    await tapRunAssessment(tester);

    expect(createCount, 1);
    expect(find.text('Assessment Result'), findsNothing);
    expect(find.text('New Assessment'), findsOneWidget);
    expect(
      find.text('Unable to complete assessment. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Sensitive backend'), findsNothing);
    final retryButton = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('run-assessment-button')),
    );
    expect(retryButton.onPressed, isNotNull);

    await tapRunAssessment(tester);

    expect(createCount, 2);
    expect(find.text('Assessment Result'), findsOneWidget);
  });

  testWidgets('result action returns true through the add-screen route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AssessmentRouteHost(creator: (_) async => persistedAssessment),
      ),
    );

    await tester.tap(find.text('Open assessment'));
    await tester.pumpAndSettle();
    await enterValidForm(tester);
    await tapRunAssessment(tester);

    await tester.scrollUntilVisible(
      find.text('Return to Assessment History'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Return to Assessment History'));
    await tester.pumpAndSettle();

    expect(find.text('Returned: true'), findsOneWidget);
  });
}

Future<void> pumpAddAssessment(
  WidgetTester tester, {
  required AssessmentCreator creator,
  AssessmentMapScreenBuilder? mapScreenBuilder,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: AddAssessmentScreen(
        assessmentCreator: creator,
        mapScreenBuilder: mapScreenBuilder,
      ),
    ),
  );
}

Future<void> enterValidForm(WidgetTester tester) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), 'Kota Kinabalu');
  await tester.enterText(fields.at(1), '1234.5');
  await tester.enterText(fields.at(2), '25000');
  await tester.enterText(fields.at(3), '2');
  await tester.enterText(fields.at(4), '4.25');
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('run-assessment-button')),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> tapRunAssessment(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('run-assessment-button')),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.byKey(const ValueKey('run-assessment-button')));
  await tester.pumpAndSettle();
}

class AssessmentRouteHost extends StatefulWidget {
  final AssessmentCreator creator;

  const AssessmentRouteHost({super.key, required this.creator});

  @override
  State<AssessmentRouteHost> createState() => _AssessmentRouteHostState();
}

class _AssessmentRouteHostState extends State<AssessmentRouteHost> {
  bool? returned;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Text('Returned: $returned'),
          ElevatedButton(
            onPressed: () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      AddAssessmentScreen(assessmentCreator: widget.creator),
                ),
              );
              if (!mounted) return;
              setState(() {
                returned = result;
              });
            },
            child: const Text('Open assessment'),
          ),
        ],
      ),
    );
  }
}

final persistedAssessment = StationAssessment(
  id: '30000000-0000-0000-0000-000000000001',
  userId: '20000000-0000-0000-0000-000000000001',
  companyId: null,
  locationName: 'Kota Kinabalu',
  populationDensity: 1234.5,
  trafficLevel: 3,
  registeredVehicleCount: 25000,
  nearbyFuelStations: 2,
  competitorDistanceKm: 4.25,
  roadAccessibility: 3,
  commercialActivity: 3,
  residentialActivity: 3,
  landAccessibility: 3,
  finalScore: 55.1,
  suitabilityCategory: 'Moderate',
  recommendation: 'Test recommendation',
  explanation: 'Test explanation',
  createdAt: DateTime.parse('2026-08-16T01:02:03.000Z'),
  updatedAt: DateTime.parse('2026-08-16T01:02:03.000Z'),
);

const firstDatasetId = '123e4567-e89b-12d3-a456-426614174000';
const replacementDatasetId = '223e4567-e89b-12d3-a456-426614174000';

EastMalaysiaSiteValidationResult insideResult({
  required GeoPoint point,
  required double radius,
  required EastMalaysiaTerritory territory,
  required String datasetId,
}) {
  return EastMalaysiaSiteValidationResult.fromRpcRow(
    row: {
      'validation_status': 'inside',
      'confirmed_territory': territory.storageValue,
      'boundary_dataset_id': datasetId,
    },
    point: point,
    analysisRadiusKm: radius,
  );
}
