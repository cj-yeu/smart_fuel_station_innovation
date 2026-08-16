import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuell_station_innovation/models/station_assessment.dart';
import 'package:smart_fuell_station_innovation/screens/assessment/assessment_list_screen.dart';

void main() {
  const currentUserId = '20000000-0000-0000-0000-000000000001';
  const teammateUserId = '20000000-0000-0000-0000-000000000002';

  testWidgets('shows loading while the assessment future is pending', (
    tester,
  ) async {
    final completer = Completer<List<StationAssessment>>();

    await pumpAssessmentList(
      tester,
      loader: () => completer.future,
      currentUserId: currentUserId,
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(const []);
    await tester.pumpAndSettle();
  });

  testWidgets('shows the empty company-history state', (tester) async {
    await pumpAssessmentList(
      tester,
      loader: () async => const [],
      currentUserId: currentUserId,
    );
    await tester.pumpAndSettle();

    expect(find.text('No assessments yet'), findsOneWidget);
    expect(
      find.text('Create an assessment to evaluate a location.'),
      findsOneWidget,
    );
  });

  testWidgets('renders returned order and restricts teammate management', (
    tester,
  ) async {
    final teammateAssessment = assessment(
      id: 'teammate',
      userId: teammateUserId,
      locationName: 'Teammate assessment first',
    );
    final ownAssessment = assessment(
      id: 'own',
      userId: currentUserId,
      locationName: 'Own assessment second',
    );

    await pumpAssessmentList(
      tester,
      loader: () async => [teammateAssessment, ownAssessment],
      currentUserId: currentUserId,
    );
    await tester.pumpAndSettle();

    expect(find.text('Teammate assessment first'), findsOneWidget);
    expect(find.text('Own assessment second'), findsOneWidget);
    expect(
      find.textContaining('Company assessment • Read-only'),
      findsOneWidget,
    );
    expect(find.textContaining('Your assessment'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('read-only-assessment-teammate')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('delete-assessment-teammate')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('delete-assessment-own')), findsOneWidget);
    expect(find.byTooltip('Delete Assessment'), findsOneWidget);

    final teammatePosition = tester.getTopLeft(
      find.text('Teammate assessment first'),
    );
    final ownPosition = tester.getTopLeft(find.text('Own assessment second'));
    expect(teammatePosition.dy, lessThan(ownPosition.dy));

    await tester.tap(find.byKey(const ValueKey('assessment-row-teammate')));
    await tester.pumpAndSettle();
    expect(find.text('Update Assessment'), findsNothing);
    expect(find.text('Station Assessments'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('assessment-row-own')));
    await tester.pumpAndSettle();
    expect(find.text('Update Assessment'), findsOneWidget);
  });

  testWidgets('shows repository errors and retries loading', (tester) async {
    var loadCount = 0;

    Future<List<StationAssessment>> loader() async {
      loadCount++;
      if (loadCount == 1) {
        throw StateError('Synthetic repository failure');
      }
      return const [];
    }

    await pumpAssessmentList(
      tester,
      loader: loader,
      currentUserId: currentUserId,
    );
    await tester.pumpAndSettle();

    expect(find.text('Unable to load assessments'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    expect(loadCount, 1);

    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(loadCount, 2);
    expect(find.text('No assessments yet'), findsOneWidget);
  });
}

Future<void> pumpAssessmentList(
  WidgetTester tester, {
  required AssessmentLoader loader,
  required String currentUserId,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: AssessmentListScreen(
        assessmentLoader: loader,
        currentUserIdProvider: () => currentUserId,
      ),
    ),
  );
}

StationAssessment assessment({
  required String id,
  required String userId,
  required String locationName,
}) {
  return StationAssessment(
    id: id,
    userId: userId,
    companyId: '10000000-0000-0000-0000-000000000001',
    locationName: locationName,
    populationDensity: 1000,
    trafficLevel: 3,
    registeredVehicleCount: 10000,
    nearbyFuelStations: 2,
    competitorDistanceKm: 3,
    roadAccessibility: 3,
    commercialActivity: 3,
    residentialActivity: 3,
    landAccessibility: 3,
    finalScore: 60,
    suitabilityCategory: 'Moderate',
    recommendation: 'Test recommendation',
    explanation: 'Test explanation',
    createdAt: DateTime.parse('2026-08-16T01:02:03.000Z'),
    updatedAt: DateTime.parse('2026-08-16T01:02:03.000Z'),
  );
}
