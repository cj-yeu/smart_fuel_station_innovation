import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuell_station_innovation/models/east_malaysia_site_validation_result.dart';
import 'package:smart_fuell_station_innovation/models/east_malaysia_territory.dart';
import 'package:smart_fuell_station_innovation/models/geo_point.dart';
import 'package:smart_fuell_station_innovation/models/station_assessment.dart';
import 'package:smart_fuell_station_innovation/models/station_assessment_create_input.dart';
import 'package:smart_fuell_station_innovation/models/station_assessment_validated_create_input.dart';
import 'package:smart_fuell_station_innovation/screens/assessment/add_assessment_screen.dart';
import 'package:smart_fuell_station_innovation/services/station_assessment_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

    await enterAssessmentField(
      tester,
      label: 'Location Name',
      hint: 'Example: Setapak, Kuala Lumpur',
      value: 'Kuching candidate',
    );
    await enterAssessmentField(
      tester,
      label: 'Population Density',
      hint: 'People per square kilometre',
      value: '2468.5',
    );

    await tapSelectSiteOnMap(tester);
    expect(find.text('Injected map screen'), findsOneWidget);
    expect(receivedInitialResults, <EastMalaysiaSiteValidationResult?>[null]);

    await tester.tap(find.text('Return candidate'));
    await tester.pumpAndSettle();

    await scrollAssessmentFormToTop(tester);
    expect(find.textContaining('5.98040'), findsOneWidget);
    expect(find.textContaining('116.07350'), findsOneWidget);
    expect(find.textContaining('Radius: 5 km'), findsOneWidget);
    expect(find.textContaining('Confirmed territory: Sabah'), findsOneWidget);
    expect(find.textContaining('Geographically validated'), findsOneWidget);
    expect(find.textContaining(firstDatasetId), findsNothing);

    await tapSelectSiteOnMap(tester);
    expect(receivedInitialResults.last, same(firstResult));
    await tester.tap(find.text('Cancel map'));
    await tester.pumpAndSettle();

    await scrollAssessmentFormToTop(tester);
    expect(find.textContaining('5.98040'), findsOneWidget);
    expect(find.textContaining('Radius: 5 km'), findsOneWidget);

    await tapSelectSiteOnMap(tester);
    expect(receivedInitialResults.last, same(firstResult));
    await tester.tap(find.text('Return candidate'));
    await tester.pumpAndSettle();

    await scrollAssessmentFormToTop(tester);
    expect(find.textContaining('1.55330'), findsOneWidget);
    expect(find.textContaining('110.35920'), findsOneWidget);
    expect(find.textContaining('Radius: 10 km'), findsOneWidget);
    expect(find.textContaining('Confirmed territory: Sarawak'), findsOneWidget);
    expect(find.textContaining(replacementDatasetId), findsNothing);
    await expectAssessmentFieldValue(
      tester,
      label: 'Location Name',
      hint: 'Example: Setapak, Kuala Lumpur',
      value: 'Kuching candidate',
    );
    expect(find.text('Kuching candidate'), findsOneWidget);
    await expectAssessmentFieldValue(
      tester,
      label: 'Population Density',
      hint: 'People per square kilometre',
      value: '2468.5',
    );
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

    await submitAssessment(tester);

    expect(createCount, 0);
    expect(find.text('Please fill in all fields'), findsOneWidget);
    expect(find.text('New Assessment'), findsOneWidget);
  });

  testWidgets('valid form sends exact input and opens the result screen', (
    tester,
  ) async {
    var createCount = 0;
    var requestIdGenerationCount = 0;
    StationAssessmentCreateInput? receivedInput;

    await pumpAddAssessment(
      tester,
      creator: (input) async {
        createCount++;
        receivedInput = input;
        return persistedAssessment;
      },
      requestIdGenerator: () {
        requestIdGenerationCount++;
        return firstRequestId;
      },
    );
    await enterValidForm(tester);

    await submitAssessment(tester);

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
    expect(requestIdGenerationCount, 0);
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

  testWidgets('validated selection uses only the validated creator', (
    tester,
  ) async {
    var legacyCreateCount = 0;
    var validatedCreateCount = 0;
    StationAssessmentValidatedCreateInput? receivedInput;

    await pumpAddAssessment(
      tester,
      creator: (_) async {
        legacyCreateCount++;
        return persistedAssessment;
      },
      validatedCreator: (input) async {
        validatedCreateCount++;
        receivedInput = input;
        return persistedAssessment;
      },
      mapScreenBuilder: mapReturning(defaultInsideResult()),
      requestIdGenerator: () => firstRequestId,
    );

    await selectInjectedSite(tester);
    await enterValidForm(tester);
    await submitAssessment(tester);

    expect(legacyCreateCount, 0);
    expect(validatedCreateCount, 1);
    expect(receivedInput!.validationResult.candidate.isValidatedInside, isTrue);
    expect(receivedInput!.content.locationName, 'Kota Kinabalu');
    expect(receivedInput!.requestId, firstRequestId);
    expect(find.text('Assessment Result'), findsOneWidget);
  });

  testWidgets('stale validation clears selection but preserves form', (
    tester,
  ) async {
    var validatedCreateCount = 0;
    var legacyCreateCount = 0;
    final requestIds = <String>[];
    var generatedRequestCount = 0;

    await pumpAddAssessment(
      tester,
      creator: (_) async {
        legacyCreateCount++;
        return persistedAssessment;
      },
      validatedCreator: (input) async {
        validatedCreateCount++;
        requestIds.add(input.requestId);
        if (validatedCreateCount == 1) {
          throw const PostgrestException(
            message: 'Internal dataset replacement detail',
            code: '40001',
          );
        }
        return persistedAssessment;
      },
      mapScreenBuilder: mapReturning(defaultInsideResult()),
      requestIdGenerator: () =>
          generatedRequestCount++ == 0 ? firstRequestId : secondRequestId,
    );

    await selectInjectedSite(tester);
    await enterValidForm(tester);
    await submitAssessment(tester);

    expect(validatedCreateCount, 1);
    expect(legacyCreateCount, 0);
    expect(find.textContaining('Internal dataset'), findsNothing);
    expect(find.text('Assessment Result'), findsNothing);

    await scrollAssessmentFormToTop(tester);
    final staleError = find.byKey(const ValueKey('assessment-submit-error'));
    expect(staleError, findsOneWidget);
    expect(
      tester.widget<Text>(staleError).data,
      'Please validate the selected site again before continuing.',
    );
    expect(find.byKey(const ValueKey('selected-site-summary')), findsNothing);
    await expectAssessmentFieldValue(
      tester,
      label: 'Location Name',
      hint: 'Example: Setapak, Kuala Lumpur',
      value: 'Kota Kinabalu',
    );
    expect(find.text('Kota Kinabalu'), findsOneWidget);
    await expectAssessmentFieldValue(
      tester,
      label: 'Population Density',
      hint: 'People per square kilometre',
      value: '1234.5',
    );
    expect(find.text('1234.5'), findsOneWidget);
    await expectAssessmentFieldValue(
      tester,
      label: 'Registered Vehicle Count',
      hint: 'Estimated vehicles in the area',
      value: '25000',
    );
    await expectAssessmentFieldValue(
      tester,
      label: 'Nearby Fuel Stations',
      hint: 'Number of nearby competitors',
      value: '2',
    );
    await expectAssessmentFieldValue(
      tester,
      label: 'Nearest Competitor Distance',
      hint: 'Distance in kilometres',
      value: '4.25',
    );

    await submitAssessment(tester);
    await scrollAddAssessmentToTop(tester);
    expect(validatedCreateCount, 1);
    expect(legacyCreateCount, 0);
    final retryError = find.byKey(const ValueKey('assessment-submit-error'));
    expect(retryError, findsOneWidget);
    expect(
      tester.widget<Text>(retryError).data,
      'Please validate the selected site again before continuing.',
    );

    await selectInjectedSite(tester);
    await submitAssessment(tester);
    expect(validatedCreateCount, 2);
    expect(requestIds, [firstRequestId, secondRequestId]);
    expect(find.text('Assessment Result'), findsOneWidget);
  });

  testWidgets('non-stale validated failure preserves validation for retry', (
    tester,
  ) async {
    var validatedCreateCount = 0;
    var legacyCreateCount = 0;
    final requestIds = <String>[];

    await pumpAddAssessment(
      tester,
      creator: (_) async {
        legacyCreateCount++;
        return persistedAssessment;
      },
      validatedCreator: (input) async {
        validatedCreateCount++;
        requestIds.add(input.requestId);
        if (validatedCreateCount == 1) {
          throw const PostgrestException(
            message: 'Sensitive permission and ownership detail',
            code: '42501',
          );
        }
        return persistedAssessment;
      },
      mapScreenBuilder: mapReturning(defaultInsideResult()),
      requestIdGenerator: () => firstRequestId,
    );

    await selectInjectedSite(tester);
    await enterValidForm(tester);
    await submitAssessment(tester);

    expect(validatedCreateCount, 1);
    expect(legacyCreateCount, 0);
    expect(
      find.text('Unable to complete assessment. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Sensitive permission'), findsNothing);
    expect(find.text('Assessment Result'), findsNothing);

    await scrollAssessmentFormToTop(tester);
    expect(find.byKey(const ValueKey('selected-site-summary')), findsOneWidget);
    expect(find.textContaining('Confirmed territory: Sabah'), findsOneWidget);
    expect(find.textContaining('Radius: 5 km'), findsOneWidget);
    await expectAssessmentFieldValue(
      tester,
      label: 'Location Name',
      hint: 'Example: Setapak, Kuala Lumpur',
      value: 'Kota Kinabalu',
    );
    expect(find.text('Kota Kinabalu'), findsOneWidget);
    await expectAssessmentFieldValue(
      tester,
      label: 'Population Density',
      hint: 'People per square kilometre',
      value: '1234.5',
    );
    expect(find.text('1234.5'), findsOneWidget);
    await expectAssessmentFieldValue(
      tester,
      label: 'Registered Vehicle Count',
      hint: 'Estimated vehicles in the area',
      value: '25000',
    );
    expect(find.text('25000'), findsOneWidget);
    await expectAssessmentFieldValue(
      tester,
      label: 'Nearby Fuel Stations',
      hint: 'Number of nearby competitors',
      value: '2',
    );
    expect(find.text('2'), findsOneWidget);
    await expectAssessmentFieldValue(
      tester,
      label: 'Nearest Competitor Distance',
      hint: 'Distance in kilometres',
      value: '4.25',
    );
    expect(find.text('4.25'), findsOneWidget);

    await submitAssessment(tester);

    expect(validatedCreateCount, 2);
    expect(legacyCreateCount, 0);
    expect(requestIds, [firstRequestId, firstRequestId]);
    expect(find.text('Assessment Result'), findsOneWidget);
  });

  testWidgets('changed validated payload uses a new request ID', (
    tester,
  ) async {
    final requestIds = <String>[];
    var generatedRequestCount = 0;

    await pumpAddAssessment(
      tester,
      creator: (_) async => persistedAssessment,
      validatedCreator: (input) async {
        requestIds.add(input.requestId);
        if (requestIds.length == 1) {
          throw StateError('retryable local response failure');
        }
        return persistedAssessment;
      },
      mapScreenBuilder: mapReturning(defaultInsideResult()),
      requestIdGenerator: () =>
          generatedRequestCount++ == 0 ? firstRequestId : secondRequestId,
    );

    await selectInjectedSite(tester);
    await enterValidForm(tester);
    await submitAssessment(tester);
    await enterAssessmentField(
      tester,
      label: 'Location Name',
      hint: 'Example: Setapak, Kuala Lumpur',
      value: 'Changed Kota Kinabalu',
    );
    await submitAssessment(tester);

    expect(requestIds, [firstRequestId, secondRequestId]);
    expect(find.text('Assessment Result'), findsOneWidget);
  });

  testWidgets('pending validated creation suppresses duplicate submission', (
    tester,
  ) async {
    final completer = Completer<StationAssessment>();
    final requestIds = <String>[];

    await pumpAddAssessment(
      tester,
      creator: (_) async => persistedAssessment,
      validatedCreator: (input) {
        requestIds.add(input.requestId);
        return completer.future;
      },
      mapScreenBuilder: mapReturning(defaultInsideResult()),
      requestIdGenerator: () => firstRequestId,
    );
    await selectInjectedSite(tester);
    await enterValidForm(tester);

    await submitAssessment(tester, waitForCompletion: false);

    expect(requestIds, [firstRequestId]);
    final button = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('run-assessment-button')),
    );
    expect(button.onPressed, isNull);
    await tester.pump();
    expect(requestIds, [firstRequestId]);

    completer.complete(persistedAssessment);
    await tester.pumpAndSettle();
    expect(find.text('Assessment Result'), findsOneWidget);
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

    await submitAssessment(tester, waitForCompletion: false);

    expect(createCount, 1);
    expect(find.text('Assessing...'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('run-assessment-button')),
    );
    expect(button.onPressed, isNull);

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

    await submitAssessment(tester);

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

    await submitAssessment(tester);

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
    await submitAssessment(tester);

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

Future<void> scrollAddAssessmentToTop(WidgetTester tester) async {
  await scrollAssessmentFormToTop(tester);
}

Future<void> pumpAddAssessment(
  WidgetTester tester, {
  required AssessmentCreator creator,
  ValidatedAssessmentCreator? validatedCreator,
  AssessmentMapScreenBuilder? mapScreenBuilder,
  AssessmentRequestIdGenerator? requestIdGenerator,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AddAssessmentScreen(
        assessmentCreator: creator,
        validatedAssessmentCreator: validatedCreator,
        mapScreenBuilder: mapScreenBuilder,
        requestIdGenerator: requestIdGenerator,
      ),
    ),
  );
  await tester.pump();
}

AssessmentMapScreenBuilder mapReturning(
  EastMalaysiaSiteValidationResult result,
) {
  return (context, initialValidationResult) => Scaffold(
    body: ElevatedButton(
      onPressed: () => Navigator.pop(context, result),
      child: const Text('Return validated site'),
    ),
  );
}

Future<void> selectInjectedSite(WidgetTester tester) async {
  await tapSelectSiteOnMap(tester);
  await tester.tap(find.text('Return validated site'));
  await tester.pumpAndSettle();
}

Future<void> tapSelectSiteOnMap(WidgetTester tester) async {
  await scrollAssessmentFormToTop(tester);
  final button = find.text('Select Site on Map');
  await ensureAssessmentTargetMounted(
    tester,
    button,
    description: 'Select Site on Map button',
  );
  expect(button, findsOneWidget);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> enterValidForm(WidgetTester tester) async {
  await enterAssessmentField(
    tester,
    label: 'Location Name',
    hint: 'Example: Setapak, Kuala Lumpur',
    value: 'Kota Kinabalu',
  );
  await enterAssessmentField(
    tester,
    label: 'Population Density',
    hint: 'People per square kilometre',
    value: '1234.5',
  );
  await enterAssessmentField(
    tester,
    label: 'Registered Vehicle Count',
    hint: 'Estimated vehicles in the area',
    value: '25000',
  );
  await enterAssessmentField(
    tester,
    label: 'Nearby Fuel Stations',
    hint: 'Number of nearby competitors',
    value: '2',
  );
  await enterAssessmentField(
    tester,
    label: 'Nearest Competitor Distance',
    hint: 'Distance in kilometres',
    value: '4.25',
  );
  await ensureAssessmentTargetMounted(
    tester,
    find.byKey(const ValueKey('run-assessment-button')),
    description: 'run assessment button',
  );
}

Future<void> enterAssessmentField(
  WidgetTester tester, {
  required String label,
  required String hint,
  required String value,
}) async {
  await scrollAssessmentFormToTop(tester);
  final field = assessmentField(label: label, hint: hint);

  await ensureAssessmentTargetMounted(
    tester,
    field,
    description: 'assessment field "$label"',
  );
  expect(field, findsOneWidget);
  await tester.enterText(field, value);
  await tester.pump();
}

Future<void> expectAssessmentFieldValue(
  WidgetTester tester, {
  required String label,
  required String hint,
  required String value,
}) async {
  await scrollAssessmentFormToTop(tester);
  final field = assessmentField(label: label, hint: hint);

  await ensureAssessmentTargetMounted(
    tester,
    field,
    description: 'assessment field "$label"',
  );
  expect(field, findsOneWidget);
  final textField = tester.widget<TextField>(field);
  expect(textField.controller, isNotNull);
  expect(textField.controller!.text, value);
}

Finder assessmentField({required String label, required String hint}) {
  return find.descendant(
    of: find.byType(AddAssessmentScreen),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == label &&
          widget.decoration?.hintText == hint,
      description: 'assessment field labelled "$label"',
    ),
  );
}

Finder verticalAddAssessmentScrollable(WidgetTester tester) {
  final scrollable = find.descendant(
    of: find.byType(AddAssessmentScreen),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
      description: 'vertical assessment form scrollable',
    ),
  );
  expect(scrollable, findsOneWidget);
  return scrollable;
}

Future<void> ensureAssessmentTargetMounted(
  WidgetTester tester,
  Finder target, {
  required String description,
}) async {
  final scrollable = verticalAddAssessmentScrollable(tester);
  final state = tester.state<ScrollableState>(scrollable);
  state.position.jumpTo(state.position.minScrollExtent);
  await tester.pump();

  for (var attempt = 0; attempt < 8; attempt++) {
    if (target.evaluate().isNotEmpty) {
      return;
    }

    if (state.position.pixels >= state.position.maxScrollExtent) {
      break;
    }

    await tester.drag(scrollable, const Offset(0, -240));
    await tester.pump();
  }

  expect(target, findsOneWidget, reason: 'Could not mount $description');
}

Future<void> scrollAssessmentFormToTop(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  tester.testTextInput.hide();
  await tester.pump();
  final scrollableState = tester.state<ScrollableState>(
    verticalAddAssessmentScrollable(tester),
  );
  scrollableState.position.jumpTo(scrollableState.position.minScrollExtent);
  await tester.pump();
}

Future<void> submitAssessment(
  WidgetTester tester, {
  bool waitForCompletion = true,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  tester.testTextInput.hide();
  await tester.pump();

  final buttonFinder = find.byKey(const ValueKey('run-assessment-button'));
  await ensureAssessmentTargetMounted(
    tester,
    buttonFinder,
    description: 'run assessment button',
  );
  expect(buttonFinder, findsOneWidget);

  final button = tester.widget<ElevatedButton>(buttonFinder);
  expect(button.onPressed, isNotNull);

  button.onPressed!();

  if (waitForCompletion) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
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
const firstRequestId = '73000000-0000-0000-0000-000000000001';
const secondRequestId = '73000000-0000-0000-0000-000000000002';

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

EastMalaysiaSiteValidationResult defaultInsideResult() {
  return insideResult(
    point: GeoPoint(latitude: 5.9804, longitude: 116.0735),
    radius: 5,
    territory: EastMalaysiaTerritory.sabah,
    datasetId: firstDatasetId,
  );
}
