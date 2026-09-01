import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuel_station_innovation/models/station_assessment.dart';
import 'package:smart_fuel_station_innovation/screens/assessment/assessment_list_screen.dart';
import 'package:smart_fuel_station_innovation/services/station_assessment_repository.dart';

void main() {
  const currentUserId = '20000000-0000-0000-0000-000000000001';
  const teammateUserId = '20000000-0000-0000-0000-000000000002';
  const normalAccess = AssessmentAccessContext(
    userId: currentUserId,
    isCompanyAdmin: false,
    hasCompany: true,
  );
  const adminAccess = AssessmentAccessContext(
    userId: currentUserId,
    isCompanyAdmin: true,
    hasCompany: true,
  );

  testWidgets('shows loading while the assessment future is pending', (
    tester,
  ) async {
    final completer = Completer<List<StationAssessment>>();

    await pumpAssessmentList(
      tester,
      loader: () => completer.future,
      accessLoader: () async => normalAccess,
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(const []);
    await tester.pumpAndSettle();
  });

  testWidgets('shows the empty company-history state', (tester) async {
    await pumpAssessmentList(
      tester,
      loader: () async => const [],
      accessLoader: () async => normalAccess,
    );
    await tester.pumpAndSettle();

    expect(find.text('No assessments yet'), findsOneWidget);
    expect(
      find.text('Create an assessment to evaluate a location.'),
      findsOneWidget,
    );
  });

  testWidgets('a stale overlapping load cannot replace the newer result', (
    tester,
  ) async {
    final firstLoad = Completer<List<StationAssessment>>();
    final secondLoad = Completer<List<StationAssessment>>();
    var loadCount = 0;
    final staleAssessment = assessment(
      id: 'stale',
      userId: currentUserId,
      locationName: 'Stale initial result',
    );
    final newerAssessment = assessment(
      id: 'newer',
      userId: currentUserId,
      locationName: 'Newer overlapping result',
    );

    Future<List<StationAssessment>> loader() {
      loadCount++;
      return loadCount == 1 ? firstLoad.future : secondLoad.future;
    }

    await pumpAssessmentList(
      tester,
      loader: loader,
      accessLoader: () async => normalAccess,
    );
    await tester.pump();
    expect(loadCount, 1);

    final state = tester.state(find.byType(AssessmentListScreen)) as dynamic;
    final newerRequest = state.loadAssessments() as Future<void>;
    await tester.pump();
    expect(loadCount, 2);

    secondLoad.complete([newerAssessment]);
    await newerRequest;
    await tester.pump();

    expect(find.text('Newer overlapping result'), findsOneWidget);
    expect(find.text('Stale initial result'), findsNothing);

    firstLoad.complete([staleAssessment]);
    await tester.pumpAndSettle();

    expect(find.text('Newer overlapping result'), findsOneWidget);
    expect(find.text('Stale initial result'), findsNothing);
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
      accessLoader: () async => normalAccess,
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
    var accessCount = 0;

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
      accessLoader: () async {
        accessCount++;
        return normalAccess;
      },
    );
    await tester.pumpAndSettle();

    expect(find.text('Unable to load assessments'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    expect(loadCount, 1);
    expect(accessCount, 1);

    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(loadCount, 2);
    expect(accessCount, 2);
    expect(find.text('No assessments yet'), findsOneWidget);
  });

  testWidgets('cancelling deletion does not call the deleter', (tester) async {
    var deleteCount = 0;
    final ownAssessment = assessment(
      id: 'own',
      userId: currentUserId,
      locationName: 'Own assessment',
    );

    await pumpAssessmentList(
      tester,
      loader: () async => [ownAssessment],
      deleter: (_) async {
        deleteCount++;
      },
      accessLoader: () async => normalAccess,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('delete-assessment-own')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(deleteCount, 0);
    expect(find.byKey(const ValueKey('assessment-card-own')), findsOneWidget);
  });

  testWidgets('confirmed deletion passes the ID, succeeds, and reloads', (
    tester,
  ) async {
    var loadCount = 0;
    String? deletedId;
    final ownAssessment = assessment(
      id: 'own',
      userId: currentUserId,
      locationName: 'Own assessment',
    );

    await pumpAssessmentList(
      tester,
      loader: () async {
        loadCount++;
        return loadCount == 1 ? [ownAssessment] : const [];
      },
      deleter: (assessmentId) async {
        deletedId = assessmentId;
      },
      accessLoader: () async => normalAccess,
    );
    await tester.pumpAndSettle();

    await confirmOwnAssessmentDeletion(tester);

    expect(deletedId, 'own');
    expect(loadCount, 2);
    expect(find.text('Assessment deleted successfully'), findsOneWidget);
    expect(find.text('No assessments yet'), findsOneWidget);
  });

  testWidgets('rejected deletion stays visible and reports neutral failure', (
    tester,
  ) async {
    var loadCount = 0;
    final ownAssessment = assessment(
      id: 'own',
      userId: currentUserId,
      locationName: 'Own assessment',
    );

    await pumpAssessmentList(
      tester,
      loader: () async {
        loadCount++;
        return [ownAssessment];
      },
      deleter: (_) async => throw const AssessmentDeleteRejectedException(),
      accessLoader: () async => normalAccess,
    );
    await tester.pumpAndSettle();

    await confirmOwnAssessmentDeletion(tester);

    expect(loadCount, 1);
    expect(find.text('Assessment deleted successfully'), findsNothing);
    expect(
      find.text(
        'Assessment could not be deleted. It may be unavailable or you may '
        'not have permission.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('assessment-card-own')), findsOneWidget);
  });

  testWidgets('generic deletion failure stays visible without reloading', (
    tester,
  ) async {
    var loadCount = 0;
    final ownAssessment = assessment(
      id: 'own',
      userId: currentUserId,
      locationName: 'Own assessment',
    );

    await pumpAssessmentList(
      tester,
      loader: () async {
        loadCount++;
        return [ownAssessment];
      },
      deleter: (_) async => throw StateError('Sensitive backend detail'),
      accessLoader: () async => normalAccess,
    );
    await tester.pumpAndSettle();

    await confirmOwnAssessmentDeletion(tester);

    expect(loadCount, 1);
    expect(find.text('Assessment deleted successfully'), findsNothing);
    expect(
      find.text('Unable to delete assessment. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Sensitive backend detail'), findsNothing);
    expect(find.byKey(const ValueKey('assessment-card-own')), findsOneWidget);
  });

  testWidgets('company admin can edit and delete a teammate assessment', (
    tester,
  ) async {
    final teammateAssessment = assessment(
      id: 'teammate',
      userId: teammateUserId,
      locationName: 'Admin-managed teammate assessment',
    );

    await pumpAssessmentList(
      tester,
      loader: () async => [teammateAssessment],
      accessLoader: () async => adminAccess,
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Company assessment • Admin access'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('read-only-assessment-teammate')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('delete-assessment-teammate')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('assessment-row-teammate')));
    await tester.pumpAndSettle();

    expect(find.text('Update Assessment'), findsOneWidget);
  });

  testWidgets('confirmed admin deletion passes teammate ID and reloads', (
    tester,
  ) async {
    var loadCount = 0;
    var accessCount = 0;
    String? deletedId;
    final teammateAssessment = assessment(
      id: 'teammate',
      userId: teammateUserId,
      locationName: 'Admin-managed teammate assessment',
    );

    await pumpAssessmentList(
      tester,
      loader: () async {
        loadCount++;
        return loadCount == 1 ? [teammateAssessment] : const [];
      },
      accessLoader: () async {
        accessCount++;
        return adminAccess;
      },
      deleter: (assessmentId) async {
        deletedId = assessmentId;
      },
    );
    await tester.pumpAndSettle();

    await confirmAssessmentDeletion(tester, 'teammate');

    expect(deletedId, 'teammate');
    expect(loadCount, 2);
    expect(accessCount, 2);
    expect(find.text('Assessment deleted successfully'), findsOneWidget);
    expect(find.text('No assessments yet'), findsOneWidget);
  });

  testWidgets('rejected admin deletion stays neutral and visible', (
    tester,
  ) async {
    var loadCount = 0;
    final teammateAssessment = assessment(
      id: 'teammate',
      userId: teammateUserId,
      locationName: 'Admin-managed teammate assessment',
    );

    await pumpAssessmentList(
      tester,
      loader: () async {
        loadCount++;
        return [teammateAssessment];
      },
      accessLoader: () async => adminAccess,
      deleter: (_) async => throw const AssessmentDeleteRejectedException(),
    );
    await tester.pumpAndSettle();

    await confirmAssessmentDeletion(tester, 'teammate');

    expect(loadCount, 1);
    expect(find.text('Assessment deleted successfully'), findsNothing);
    expect(
      find.text(
        'Assessment could not be deleted. It may be unavailable or you may '
        'not have permission.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('assessment-card-teammate')),
      findsOneWidget,
    );
  });

  testWidgets('missing authoritative company access is a load error', (
    tester,
  ) async {
    var assessmentLoadCount = 0;

    await pumpAssessmentList(
      tester,
      loader: () async {
        assessmentLoadCount++;
        return const [];
      },
      accessLoader: () async => const AssessmentAccessContext(
        userId: currentUserId,
        isCompanyAdmin: false,
        hasCompany: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(assessmentLoadCount, 0);
    expect(find.text('Unable to load assessments'), findsOneWidget);
    expect(find.text('No assessments yet'), findsNothing);
  });

  testWidgets('blank authoritative user ID is a load error', (tester) async {
    var assessmentLoadCount = 0;

    await pumpAssessmentList(
      tester,
      loader: () async {
        assessmentLoadCount++;
        return const [];
      },
      accessLoader: () async => const AssessmentAccessContext(
        userId: '   ',
        isCompanyAdmin: false,
        hasCompany: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(assessmentLoadCount, 0);
    expect(find.text('Unable to load assessments'), findsOneWidget);
    expect(find.text('No assessments yet'), findsNothing);
  });

  testWidgets('access errors stay neutral and retry reloads access', (
    tester,
  ) async {
    var accessCount = 0;

    await pumpAssessmentList(
      tester,
      loader: () async => const [],
      accessLoader: () async {
        accessCount++;
        if (accessCount == 1) {
          throw StateError('Sensitive profile backend detail');
        }
        return normalAccess;
      },
    );
    await tester.pumpAndSettle();

    expect(accessCount, 1);
    expect(find.text('Unable to load assessments'), findsOneWidget);
    expect(
      find.textContaining('Sensitive profile backend detail'),
      findsNothing,
    );
    expect(find.text('No assessments yet'), findsNothing);

    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(accessCount, 2);
    expect(find.text('No assessments yet'), findsOneWidget);
  });
}

Future<void> pumpAssessmentList(
  WidgetTester tester, {
  required AssessmentLoader loader,
  AssessmentDeleter? deleter,
  required AssessmentAccessLoader accessLoader,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: AssessmentListScreen(
        assessmentLoader: loader,
        assessmentDeleter: deleter ?? (_) async {},
        accessLoader: accessLoader,
      ),
    ),
  );
}

Future<void> confirmOwnAssessmentDeletion(WidgetTester tester) async {
  await confirmAssessmentDeletion(tester, 'own');
}

Future<void> confirmAssessmentDeletion(
  WidgetTester tester,
  String assessmentId,
) async {
  await tester.tap(find.byKey(ValueKey('delete-assessment-$assessmentId')));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
  await tester.pumpAndSettle();
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
