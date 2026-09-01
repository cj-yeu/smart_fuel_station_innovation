import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuel_station_innovation/models/station_assessment.dart';
import 'package:smart_fuel_station_innovation/models/station_assessment_create_input.dart';
import 'package:smart_fuel_station_innovation/screens/assessment/edit_assessment_screen.dart';
import 'package:smart_fuel_station_innovation/services/station_assessment_repository.dart';
import 'package:smart_fuel_station_innovation/services/station_assessment_service.dart';

void main() {
  testWidgets('prefills every existing assessment value', (tester) async {
    await pumpEditAssessment(tester, updater: successfulUpdater);

    final fields = find.byType(TextField);
    expect(
      tester.widget<TextField>(fields.at(0)).controller!.text,
      'Kota Kinabalu',
    );
    expect(tester.widget<TextField>(fields.at(1)).controller!.text, '1234.5');
    expect(tester.widget<TextField>(fields.at(2)).controller!.text, '25000');
    expect(tester.widget<TextField>(fields.at(3)).controller!.text, '2');
    expect(tester.widget<TextField>(fields.at(4)).controller!.text, '4.25');
    await expectRatingPrefill(tester, 'Traffic Level', 5);
    await expectRatingPrefill(tester, 'Road Accessibility', 4);
    await expectRatingPrefill(tester, 'Commercial Activity', 3);
    await expectRatingPrefill(tester, 'Residential Activity', 2);
    await expectRatingPrefill(tester, 'Land Accessibility', 1);
  });

  testWidgets('invalid edited values do not call the updater', (tester) async {
    var updateCount = 0;

    await pumpEditAssessment(
      tester,
      updater: (_, _) async {
        updateCount++;
        return persistedAssessment;
      },
    );
    await tester.enterText(find.byType(TextField).at(1), '-1');

    await tapUpdateAssessment(tester);

    expect(updateCount, 0);
    expect(find.text('Numeric values cannot be negative'), findsOneWidget);
    expect(find.text('Update Assessment'), findsOneWidget);
  });

  testWidgets('valid edit sends the ID and exact typed input', (tester) async {
    var updateCount = 0;
    String? receivedId;
    StationAssessmentCreateInput? receivedInput;

    await pumpEditAssessment(
      tester,
      updater: (assessmentId, input) async {
        updateCount++;
        receivedId = assessmentId;
        receivedInput = input;
        return persistedAssessment;
      },
    );
    await enterEditedValues(tester);

    await tapUpdateAssessment(tester);

    final expectedResult = StationAssessmentService.calculate(
      populationDensity: 4321.5,
      trafficLevel: 5,
      registeredVehicleCount: 35000,
      nearbyFuelStations: 1,
      competitorDistanceKm: 4.75,
      roadAccessibility: 4,
      commercialActivity: 3,
      residentialActivity: 2,
      landAccessibility: 1,
    );
    final input = receivedInput!;

    expect(updateCount, 1);
    expect(receivedId, persistedAssessment.id);
    expect(input.locationName, 'Kota Kinabalu Updated');
    expect(input.populationDensity, 4321.5);
    expect(input.trafficLevel, 5);
    expect(input.registeredVehicleCount, 35000);
    expect(input.nearbyFuelStations, 1);
    expect(input.competitorDistanceKm, 4.75);
    expect(input.roadAccessibility, 4);
    expect(input.commercialActivity, 3);
    expect(input.residentialActivity, 2);
    expect(input.landAccessibility, 1);
    expect(input.finalScore, expectedResult.finalScore);
    expect(input.suitabilityCategory, expectedResult.category);
    expect(input.recommendation, expectedResult.recommendation);
    expect(input.explanation, expectedResult.explanation);
    expect(input.toInsertMap(), isNot(contains('id')));
    expect(input.toInsertMap(), isNot(contains('user_id')));
    expect(input.toInsertMap(), isNot(contains('company_id')));
    expect(input.toInsertMap(), isNot(contains('created_at')));
    expect(input.toInsertMap(), isNot(contains('updated_at')));
    expect(find.text('Assessment Result'), findsOneWidget);
    expect(find.text('Kota Kinabalu Updated'), findsOneWidget);
  });

  testWidgets('pending update disables repeated submission and ratings', (
    tester,
  ) async {
    var updateCount = 0;
    final completer = Completer<StationAssessment>();

    await pumpEditAssessment(
      tester,
      updater: (_, _) {
        updateCount++;
        return completer.future;
      },
    );
    await scrollToUpdateButton(tester);

    await tester.tap(find.byKey(const ValueKey('update-assessment-button')));
    await tester.pump();

    expect(updateCount, 1);
    expect(find.text('Reassessing...'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('update-assessment-button')),
    );
    expect(button.onPressed, isNull);
    for (final dropdown in tester.widgetList<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>),
    )) {
      expect(dropdown.onChanged, isNull);
    }

    await tester.tap(
      find.byKey(const ValueKey('update-assessment-button')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(updateCount, 1);

    completer.complete(persistedAssessment);
    await tester.pumpAndSettle();
    expect(find.text('Assessment Result'), findsOneWidget);
  });

  testWidgets('rejected update stays on edit with a neutral message', (
    tester,
  ) async {
    await pumpEditAssessment(
      tester,
      updater: (_, _) async => throw const AssessmentUpdateRejectedException(),
    );

    await tapUpdateAssessment(tester);

    expect(find.text('Assessment Result'), findsNothing);
    expect(find.text('Update Assessment'), findsOneWidget);
    expect(
      find.text(
        'Assessment could not be updated. It may be unavailable or you may '
        'not have permission.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('success'), findsNothing);
  });

  testWidgets('generic failure hides details and restores retry', (
    tester,
  ) async {
    var updateCount = 0;

    await pumpEditAssessment(
      tester,
      updater: (_, _) async {
        updateCount++;
        if (updateCount == 1) {
          throw StateError(
            'Sensitive backend user/company authentication detail',
          );
        }
        return persistedAssessment;
      },
    );

    await tapUpdateAssessment(tester);

    expect(updateCount, 1);
    expect(find.text('Assessment Result'), findsNothing);
    expect(
      find.text('Unable to complete assessment. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Sensitive backend'), findsNothing);
    final retryButton = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('update-assessment-button')),
    );
    expect(retryButton.onPressed, isNotNull);

    await tapUpdateAssessment(tester);

    expect(updateCount, 2);
    expect(find.text('Assessment Result'), findsOneWidget);
  });

  testWidgets('result action returns true through the edit-screen route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: EditAssessmentRouteHost(updater: successfulUpdater)),
    );

    await tester.tap(find.text('Open assessment'));
    await tester.pumpAndSettle();
    await tapUpdateAssessment(tester);

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

Future<StationAssessment> successfulUpdater(
  String assessmentId,
  StationAssessmentCreateInput input,
) async {
  return persistedAssessment;
}

Future<void> pumpEditAssessment(
  WidgetTester tester, {
  required AssessmentUpdater updater,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: EditAssessmentScreen(
        assessment: persistedAssessment,
        assessmentUpdater: updater,
      ),
    ),
  );
}

Future<void> enterEditedValues(WidgetTester tester) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), 'Kota Kinabalu Updated');
  await tester.enterText(fields.at(1), '4321.5');
  await tester.enterText(fields.at(2), '35000');
  await tester.enterText(fields.at(3), '1');
  await tester.enterText(fields.at(4), '4.75');
  await scrollToUpdateButton(tester);
}

Future<void> expectRatingPrefill(
  WidgetTester tester,
  String label,
  int expectedValue,
) async {
  await tester.scrollUntilVisible(
    find.text(label),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  final dropdownFinder = find.ancestor(
    of: find.text(label),
    matching: find.byType(DropdownButtonFormField<int>),
  );
  final dropdown = tester.widget<DropdownButtonFormField<int>>(dropdownFinder);
  expect(dropdown.initialValue, expectedValue);
}

Future<void> scrollToUpdateButton(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('update-assessment-button')),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> tapUpdateAssessment(WidgetTester tester) async {
  await scrollToUpdateButton(tester);
  await tester.tap(find.byKey(const ValueKey('update-assessment-button')));
  await tester.pumpAndSettle();
}

class EditAssessmentRouteHost extends StatefulWidget {
  final AssessmentUpdater updater;

  const EditAssessmentRouteHost({super.key, required this.updater});

  @override
  State<EditAssessmentRouteHost> createState() =>
      _EditAssessmentRouteHostState();
}

class _EditAssessmentRouteHostState extends State<EditAssessmentRouteHost> {
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
                  builder: (context) => EditAssessmentScreen(
                    assessment: persistedAssessment,
                    assessmentUpdater: widget.updater,
                  ),
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
  trafficLevel: 5,
  registeredVehicleCount: 25000,
  nearbyFuelStations: 2,
  competitorDistanceKm: 4.25,
  roadAccessibility: 4,
  commercialActivity: 3,
  residentialActivity: 2,
  landAccessibility: 1,
  finalScore: 61.2,
  suitabilityCategory: 'Moderate',
  recommendation: 'Test recommendation',
  explanation: 'Test explanation',
  createdAt: DateTime.parse('2026-08-16T01:02:03.000Z'),
  updatedAt: DateTime.parse('2026-08-16T04:05:06.000Z'),
);
