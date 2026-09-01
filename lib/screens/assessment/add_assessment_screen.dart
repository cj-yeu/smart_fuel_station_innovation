import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../models/east_malaysia_site_validation_result.dart';
import '../../models/east_malaysia_map_selection.dart';
import '../../models/assessment_draft.dart';
import '../../models/nearby_fuel_station_result.dart';
import '../../models/site_factor_intelligence_result.dart';
import '../../models/station_assessment.dart';
import '../../models/station_assessment_create_input.dart';
import '../../models/station_assessment_validated_create_input.dart';
import '../../services/station_assessment_repository.dart';
import '../../services/station_assessment_service.dart';
import '../../services/assessment_draft_repository.dart';
import '../../services/site_factor_intelligence_repository.dart';
import 'assessment_result_screen.dart';
import 'east_malaysia_map_screen.dart';

typedef AssessmentCreator =
    Future<StationAssessment> Function(StationAssessmentCreateInput input);
typedef ValidatedAssessmentCreator =
    Future<StationAssessment> Function(
      StationAssessmentValidatedCreateInput input,
    );
typedef AssessmentRequestIdGenerator = String Function();
typedef AssessmentMapScreenBuilder =
    Widget Function(
      BuildContext context,
      EastMalaysiaSiteValidationResult? initialValidationResult,
    );

class AddAssessmentScreen extends StatefulWidget {
  final AssessmentCreator? assessmentCreator;
  final ValidatedAssessmentCreator? validatedAssessmentCreator;
  final AssessmentMapScreenBuilder? mapScreenBuilder;
  final AssessmentRequestIdGenerator? requestIdGenerator;
  final AssessmentDraftRepository? draftRepository;
  final String? Function()? authenticatedUserIdProvider;

  const AddAssessmentScreen({
    super.key,
    this.assessmentCreator,
    this.validatedAssessmentCreator,
    this.mapScreenBuilder,
    this.requestIdGenerator,
    this.draftRepository,
    this.authenticatedUserIdProvider,
  });

  @override
  State<AddAssessmentScreen> createState() => _AddAssessmentScreenState();
}

class _AddAssessmentScreenState extends State<AddAssessmentScreen> {
  static const _numericMaximums = <String, num>{
    'Population Density': 100000,
    'Registered Vehicle Count': 10000000,
    'Nearby Fuel Stations': 100,
    'Nearest Competitor Distance': 10,
  };

  static const _numericRangeHints = <String, String>{
    'Population Density': 'Allowed: 0–100,000 people/km²',
    'Registered Vehicle Count': 'Allowed: 0–10,000,000 vehicles',
    'Nearby Fuel Stations': 'Allowed: 0–100 stations',
    'Nearest Competitor Distance':
        'Allowed: 0–10 km (the maximum analysis radius)',
  };

  late final AssessmentCreator assessmentCreator;
  late final AssessmentDraftRepository draftRepository;

  final locationController = TextEditingController();
  final populationController = TextEditingController();
  final vehicleCountController = TextEditingController();
  final nearbyStationsController = TextEditingController();
  final competitorDistanceController = TextEditingController();

  int trafficLevel = 3;
  int roadAccessibility = 3;
  int commercialActivity = 3;
  int residentialActivity = 3;
  int landAccessibility = 3;
  bool roadAccessibilityEdited = false;
  bool commercialActivityEdited = false;
  bool residentialActivityEdited = false;
  bool landAccessibilityEdited = false;

  bool isSaving = false;
  bool requiresSiteRevalidation = false;
  String? submissionErrorMessage;
  Map<String, String> fieldErrors = const {};
  EastMalaysiaSiteValidationResult? selectedSiteValidationResult;
  NearbyFuelStationResult? selectedNearbyFuelStationResult;
  SiteFactorIntelligenceResult? selectedSiteFactorIntelligenceResult;
  String? validatedRequestId;
  String? validatedPayloadFingerprint;
  Timer? draftSaveTimer;
  Future<void> draftWriteChain = Future.value();
  bool isRestoringDraft = false;
  bool isDraftRestored = false;

  @override
  void initState() {
    super.initState();
    assessmentCreator =
        widget.assessmentCreator ??
        StationAssessmentRepository(Supabase.instance.client).createAssessment;
    draftRepository = widget.draftRepository ?? AssessmentDraftRepository();
    for (final controller in draftControllers) {
      controller.addListener(scheduleDraftSave);
    }
    unawaited(restoreDraft());
  }

  List<TextEditingController> get draftControllers => [
    locationController,
    populationController,
    vehicleCountController,
    nearbyStationsController,
    competitorDistanceController,
  ];

  String? get authenticatedUserId {
    final injectedUserId = widget.authenticatedUserIdProvider?.call();
    if (injectedUserId != null) return injectedUserId;

    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      // Widget tests and signed-out startup states have no Supabase instance.
      return null;
    }
  }

  Future<void> restoreDraft() async {
    final userId = authenticatedUserId;
    if (userId == null) return;

    try {
      final draft = await draftRepository.loadDraft(userId);
      if (!mounted || draft == null || !draft.hasContent) return;

      isRestoringDraft = true;
      setState(() {
        locationController.text = draft.locationName;
        populationController.text = draft.populationDensity;
        vehicleCountController.text = draft.registeredVehicleCount;
        nearbyStationsController.text = draft.nearbyFuelStations;
        competitorDistanceController.text = draft.competitorDistanceKm;
        trafficLevel = draft.trafficLevel;
        roadAccessibility = draft.roadAccessibility;
        commercialActivity = draft.commercialActivity;
        residentialActivity = draft.residentialActivity;
        landAccessibility = draft.landAccessibility;
        // Preserve non-default ratings from a restored draft as manual input.
        // A default 3 is the initial screen value, so an available site-data
        // suggestion may still replace it after the user confirms a site.
        roadAccessibilityEdited = draft.roadAccessibility != 3;
        commercialActivityEdited = draft.commercialActivity != 3;
        residentialActivityEdited = draft.residentialActivity != 3;
        landAccessibilityEdited = draft.landAccessibility != 3;
        isDraftRestored = true;
      });
    } catch (_) {
      // A local draft must never block the normal Supabase-backed workflow.
    } finally {
      isRestoringDraft = false;
    }
  }

  void scheduleDraftSave() {
    if (isRestoringDraft) return;
    draftSaveTimer?.cancel();
    draftSaveTimer = Timer(const Duration(milliseconds: 450), queueDraftSave);
  }

  void queueDraftSave() {
    final userId = authenticatedUserId;
    if (userId == null || isRestoringDraft) return;
    final draft = currentDraft;
    draftWriteChain = continueAfterDraftWrite().then((_) async {
      if (draft.hasContent) {
        await draftRepository.saveDraft(userId, draft);
      } else {
        await draftRepository.deleteDraft(userId);
      }
    });
  }

  AssessmentDraft get currentDraft => AssessmentDraft(
    locationName: locationController.text,
    populationDensity: populationController.text,
    registeredVehicleCount: vehicleCountController.text,
    nearbyFuelStations: nearbyStationsController.text,
    competitorDistanceKm: competitorDistanceController.text,
    trafficLevel: trafficLevel,
    roadAccessibility: roadAccessibility,
    commercialActivity: commercialActivity,
    residentialActivity: residentialActivity,
    landAccessibility: landAccessibility,
    updatedAt: DateTime.now(),
  );

  Future<void> continueAfterDraftWrite() async {
    try {
      await draftWriteChain;
    } catch (_) {
      // A failed local write must not prevent a later write or Supabase save.
    }
  }

  Future<void> clearDraft() async {
    draftSaveTimer?.cancel();
    final userId = authenticatedUserId;
    if (userId == null) return;
    draftWriteChain = continueAfterDraftWrite().then(
      (_) => draftRepository.deleteDraft(userId),
    );
    try {
      await draftWriteChain;
    } catch (_) {
      return;
    }
    if (mounted) {
      setState(() {
        isDraftRestored = false;
      });
    }
  }

  Future<void> runAssessment() async {
    if (isSaving) return;

    final locationName = locationController.text.trim();
    final populationDensity = double.tryParse(populationController.text.trim());
    final registeredVehicleCount = int.tryParse(
      vehicleCountController.text.trim(),
    );
    final nearbyFuelStations = int.tryParse(
      nearbyStationsController.text.trim(),
    );
    final competitorDistanceKm = double.tryParse(
      competitorDistanceController.text.trim(),
    );

    final missingOrInvalidFields = <String, String>{};
    void requireText(String label, String value) {
      if (value.isEmpty) {
        missingOrInvalidFields[label] = 'Required — enter a value.';
      }
    }

    void requireNumber(String label, String rawValue, num? parsedValue) {
      if (rawValue.isEmpty) {
        missingOrInvalidFields[label] = 'Required — enter a value.';
      } else if (parsedValue == null || !parsedValue.isFinite) {
        missingOrInvalidFields[label] = 'Enter a valid number.';
      } else if (parsedValue > _numericMaximums[label]!) {
        missingOrInvalidFields[label] =
            'Enter a value within ${_numericRangeHints[label]!.replaceFirst('Allowed: ', '')}.';
      }
    }

    requireText('Location Name', locationName);
    requireNumber(
      'Population Density',
      populationController.text.trim(),
      populationDensity,
    );
    requireNumber(
      'Registered Vehicle Count',
      vehicleCountController.text.trim(),
      registeredVehicleCount,
    );
    requireNumber(
      'Nearby Fuel Stations',
      nearbyStationsController.text.trim(),
      nearbyFuelStations,
    );
    requireNumber(
      'Nearest Competitor Distance',
      competitorDistanceController.text.trim(),
      competitorDistanceKm,
    );

    if (missingOrInvalidFields.isNotEmpty) {
      setState(() {
        fieldErrors = missingOrInvalidFields;
      });
      showMessage('Please fill in all fields', isError: true);
      return;
    }

    final validPopulationDensity = populationDensity!;
    final validRegisteredVehicleCount = registeredVehicleCount!;
    final validNearbyFuelStations = nearbyFuelStations!;
    final validCompetitorDistanceKm = competitorDistanceKm!;

    if (validPopulationDensity < 0 ||
        validRegisteredVehicleCount < 0 ||
        validNearbyFuelStations < 0 ||
        validCompetitorDistanceKm < 0) {
      if (validPopulationDensity < 0) {
        missingOrInvalidFields['Population Density'] =
            'Value cannot be negative.';
      }
      if (validRegisteredVehicleCount < 0) {
        missingOrInvalidFields['Registered Vehicle Count'] =
            'Value cannot be negative.';
      }
      if (validNearbyFuelStations < 0) {
        missingOrInvalidFields['Nearby Fuel Stations'] =
            'Value cannot be negative.';
      }
      if (validCompetitorDistanceKm < 0) {
        missingOrInvalidFields['Nearest Competitor Distance'] =
            'Value cannot be negative.';
      }
      setState(() {
        fieldErrors = missingOrInvalidFields;
      });
      showMessage('Correct the highlighted values', isError: true);
      return;
    }

    if (requiresSiteRevalidation && selectedSiteValidationResult == null) {
      setState(() {
        submissionErrorMessage =
            'Please validate the selected site again before continuing.';
      });
      return;
    }

    setState(() {
      isSaving = true;
      submissionErrorMessage = null;
      fieldErrors = const {};
    });

    try {
      final result = StationAssessmentService.calculate(
        populationDensity: validPopulationDensity,
        trafficLevel: trafficLevel,
        registeredVehicleCount: validRegisteredVehicleCount,
        nearbyFuelStations: validNearbyFuelStations,
        competitorDistanceKm: validCompetitorDistanceKm,
        roadAccessibility: roadAccessibility,
        commercialActivity: commercialActivity,
        residentialActivity: residentialActivity,
        landAccessibility: landAccessibility,
      );

      final input = StationAssessmentCreateInput(
        locationName: locationName,
        populationDensity: validPopulationDensity,
        trafficLevel: trafficLevel,
        registeredVehicleCount: validRegisteredVehicleCount,
        nearbyFuelStations: validNearbyFuelStations,
        competitorDistanceKm: validCompetitorDistanceKm,
        roadAccessibility: roadAccessibility,
        commercialActivity: commercialActivity,
        residentialActivity: residentialActivity,
        landAccessibility: landAccessibility,
        finalScore: result.finalScore,
        suitabilityCategory: result.category,
        recommendation: result.recommendation,
        explanation: result.explanation,
      );

      final validationResult = selectedSiteValidationResult;
      late final StationAssessment savedAssessment;
      if (validationResult != null) {
        final payloadFingerprint =
            StationAssessmentValidatedCreateInput.payloadFingerprint(
              content: input,
              validationResult: validationResult,
            );
        if (validatedPayloadFingerprint != payloadFingerprint ||
            validatedRequestId == null) {
          validatedPayloadFingerprint = payloadFingerprint;
          validatedRequestId =
              (widget.requestIdGenerator ?? _generateRequestId)();
        }
        final validatedInput = StationAssessmentValidatedCreateInput(
          content: input,
          validationResult: validationResult,
          requestId: validatedRequestId!,
        );
        savedAssessment =
            await (widget.validatedAssessmentCreator ??
                StationAssessmentRepository(
                  Supabase.instance.client,
                ).createValidatedAssessment)(validatedInput);
        validatedRequestId = null;
        validatedPayloadFingerprint = null;
      } else {
        savedAssessment = await assessmentCreator(input);
      }

      await clearDraft();

      if (!mounted) return;

      final completed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => AssessmentResultScreen(
            locationName: locationName,
            result: result,
            assessmentId: savedAssessment.id,
          ),
        ),
      );

      if (!mounted) return;

      if (completed == true) {
        Navigator.pop(context, true);
      }
    } on PostgrestException catch (error) {
      if (!mounted) return;
      if (error.code == '40001' && selectedSiteValidationResult != null) {
        setState(() {
          selectedSiteValidationResult = null;
          selectedNearbyFuelStationResult = null;
          selectedSiteFactorIntelligenceResult = null;
          requiresSiteRevalidation = true;
          validatedRequestId = null;
          validatedPayloadFingerprint = null;
          submissionErrorMessage =
              'Please validate the selected site again before continuing.';
        });
      } else {
        showMessage(
          'Unable to complete assessment. Please try again.',
          isError: true,
        );
      }
    } catch (error) {
      if (!mounted) return;
      showMessage(
        'Unable to complete assessment. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  void showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> selectSiteOnMap() async {
    final selectedResult = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            widget.mapScreenBuilder?.call(
              context,
              selectedSiteValidationResult,
            ) ??
            EastMalaysiaMapScreen(
              initialSelection: selectedSiteValidationResult == null
                  ? null
                  : EastMalaysiaMapSelection(
                      validationResult: selectedSiteValidationResult!,
                      nearbyFuelStations: selectedNearbyFuelStationResult,
                      siteFactorIntelligence:
                          selectedSiteFactorIntelligenceResult,
                    ),
            ),
      ),
    );

    if (!mounted || selectedResult == null) return;
    final selection = switch (selectedResult) {
      EastMalaysiaMapSelection selection => selection,
      // Kept only for injected legacy test builders during this UI transition.
      EastMalaysiaSiteValidationResult validationResult =>
        EastMalaysiaMapSelection(validationResult: validationResult),
      _ => null,
    };
    if (selection == null) return;
    setState(() {
      selectedSiteValidationResult = selection.validationResult;
      selectedNearbyFuelStationResult = selection.nearbyFuelStations;
      selectedSiteFactorIntelligenceResult = selection.siteFactorIntelligence;
      _autofillLocation(
        selection.validationResult,
        selection.siteFactorIntelligence,
      );
      _applyNearbyFuelStationAutofill(selection.nearbyFuelStations);
      _autofillAvailableSiteFactors(selection.siteFactorIntelligence);
      requiresSiteRevalidation = false;
      submissionErrorMessage = null;
    });
    scheduleDraftSave();
    if (selection.siteFactorIntelligence == null) {
      unawaited(_loadSiteDataSuggestions(selection.validationResult));
    }
  }

  Future<void> _loadSiteDataSuggestions(
    EastMalaysiaSiteValidationResult validation,
  ) async {
    if (!validation.candidate.isValidatedInside ||
        selectedSiteValidationResult != validation ||
        selectedSiteFactorIntelligenceResult != null) {
      return;
    }

    try {
      final intelligence = await SiteFactorIntelligenceRepository(
        Supabase.instance.client,
      ).fetchForValidatedSite(validation);
      if (!mounted || selectedSiteValidationResult != validation) return;

      setState(() {
        selectedSiteFactorIntelligenceResult = intelligence;
        _autofillLocation(validation, intelligence);
        _autofillAvailableSiteFactors(intelligence);
      });
      scheduleDraftSave();
    } catch (_) {
      // Site data is optional. The assessment remains fully manual when the
      // bounded Edge Function or a provider is temporarily unavailable.
    }
  }

  void _applyNearbyFuelStationAutofill(NearbyFuelStationResult? result) {
    if (result == null) return;
    if (nearbyStationsController.text.trim().isEmpty) {
      nearbyStationsController.text = result.stationCount.toString();
    }
    final nearestDistance = result.nearestDistanceKm;
    if (nearestDistance != null &&
        competitorDistanceController.text.trim().isEmpty) {
      competitorDistanceController.text = nearestDistance.toStringAsFixed(2);
    }
  }

  bool get requiresManualCompetitorDistance =>
      selectedNearbyFuelStationResult != null &&
      selectedNearbyFuelStationResult!.nearestDistanceKm == null;

  void _autofillLocation(
    EastMalaysiaSiteValidationResult validation,
    SiteFactorIntelligenceResult? intelligence,
  ) {
    if (locationController.text.trim().isNotEmpty) return;
    final territory = validation.candidate.confirmedTerritory;
    final district = intelligence?.districtReference;
    if (territory != null && district != null) {
      locationController.text =
          '${district.name}, ${territory.displayLabel}, Malaysia';
    } else if (territory != null) {
      locationController.text = '${territory.displayLabel}, Malaysia';
    }
  }

  void _autofillAvailableSiteFactors(
    SiteFactorIntelligenceResult? intelligence,
  ) {
    if (intelligence == null) return;
    final population = intelligence.population;
    if (population.hasUsableSuggestion &&
        populationController.text.trim().isEmpty) {
      populationController.text = population.densityPerSqKm!.toStringAsFixed(2);
    }

    _applyAutomaticScore(
      intelligence.roadAccessibility.hasUsableSuggestion
          ? intelligence.roadAccessibility.suggestedScore
          : null,
      alreadyEdited: roadAccessibilityEdited,
      apply: (value) => roadAccessibility = value,
    );
    _applyAutomaticScore(
      intelligence.commercialActivity.hasUsableSuggestion
          ? intelligence.commercialActivity.suggestedScore
          : null,
      alreadyEdited: commercialActivityEdited,
      apply: (value) => commercialActivity = value,
    );
    _applyAutomaticScore(
      intelligence.residentialActivity.hasUsableSuggestion
          ? intelligence.residentialActivity.suggestedScore
          : null,
      alreadyEdited: residentialActivityEdited,
      apply: (value) => residentialActivity = value,
    );
    _applyAutomaticScore(
      intelligence.landAccessibility.hasUsableSuggestion
          ? intelligence.landAccessibility.suggestedScore
          : null,
      alreadyEdited: landAccessibilityEdited,
      apply: (value) => landAccessibility = value,
    );
  }

  void _applyAutomaticScore(
    int? score, {
    required bool alreadyEdited,
    required ValueChanged<int> apply,
  }) {
    if (alreadyEdited || score == null || score < 1 || score > 5) return;
    apply(score);
  }

  Widget buildSiteDataSuggestionsPanel() {
    final intelligence = selectedSiteFactorIntelligenceResult;
    if (intelligence == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;

    return Card(
      key: const ValueKey('site-data-suggestions-panel'),
      margin: const EdgeInsets.only(top: 12),
      color: colors.primaryContainer,
      child: ExpansionTile(
        textColor: colors.onPrimaryContainer,
        collapsedTextColor: colors.onPrimaryContainer,
        iconColor: colors.onPrimaryContainer,
        collapsedIconColor: colors.onPrimaryContainer,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Site Data'),
            compactInformationButton(
              key: const ValueKey('site-data-information-button'),
              tooltip: 'How site data is used',
              onPressed: () => _showInformationDialog(
                title: 'About Site Data',
                message:
                    'Population is an estimated density. Road, commercial, '
                    'residential and land scores are OpenStreetMap-based suggestions '
                    'that depend on mapping completeness. They do not measure traffic. '
                    'Land accessibility is only a proximity and access-tag proxy; it '
                    'does not establish ownership, legal access, planning permission '
                    'or site availability.\n\nA JPJ/data.gov.my vehicle reference, '
                    'when shown, is regional registration-office/channel data. It is '
                    'not a vehicle count within this selected radius and never fills '
                    'the Registered Vehicle Count field.',
              ),
            ),
          ],
        ),
        subtitle: const Text(
          'Available scores update untouched ratings automatically.',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          buildPopulationSuggestion(intelligence.population),
          buildRoadSuggestion(intelligence.roadAccessibility),
          buildCommercialSuggestion(intelligence.commercialActivity),
          buildResidentialSuggestion(intelligence.residentialActivity),
          buildLandSuggestion(intelligence.landAccessibility),
          buildVehicleRegistrationReference(intelligence.vehicleDemand),
          if (intelligence.attribution.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sources',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    children: intelligence.attribution
                        .map(
                          (item) => TextButton.icon(
                            key: ValueKey('site-data-source-${item.source}'),
                            onPressed: () => _openAttributionUrl(item.url),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.open_in_new, size: 14),
                            label: Text(
                              '${item.source} (${item.licence})',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openAttributionUrl(String value) async {
    final url = Uri.tryParse(value);
    if (url == null || (url.scheme != 'https' && url.scheme != 'http')) {
      return;
    }

    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Attribution remains visible if the device has no browser handler.
    }
  }

  void _showInformationDialog({
    required String title,
    required String message,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget buildVehicleRegistrationReference(VehicleDemandProxy evidence) {
    if (!evidence.available || !evidence.isProxy || evidence.value == null) {
      return const SizedBox.shrink();
    }

    return buildSuggestionSection(
      title: 'Regional vehicle-registration proxy (reference only)',
      evidence: [
        'Reported records: ${evidence.value}',
        if (evidence.geographicScope != null)
          'Geographic scope: ${evidence.geographicScope}',
        if (evidence.dataPeriod != null) 'Period: ${evidence.dataPeriod}',
        if (evidence.source != null) 'Source: ${evidence.source}',
        'Not vehicles within this selected radius. This never fills the manual field.',
      ],
      buttonLabel: null,
      onApply: null,
    );
  }

  Widget buildPopulationSuggestion(PopulationEvidence evidence) {
    if (!evidence.available) return const SizedBox.shrink();
    final density = evidence.densityPerSqKm;
    return buildSuggestionSection(
      title: 'Population Density',
      evidence: [
        if (density != null)
          'Estimated density: ${density.toStringAsFixed(2)} people/km²',
        if (evidence.dataYear != null) 'Data year: ${evidence.dataYear}',
        if (evidence.source != null) 'Source: ${evidence.source}',
        'Confidence: ${confidenceLabel(evidence.confidence)}',
      ],
      buttonLabel: null,
      onApply: null,
    );
  }

  Widget buildRoadSuggestion(RoadAccessibilityEvidence evidence) {
    if (!evidence.available) return const SizedBox.shrink();
    return buildSuggestionSection(
      title: 'Road Accessibility',
      evidence: [
        if (evidence.nearestUsableRoadM != null)
          'Nearest usable road: ${evidence.nearestUsableRoadM!.toStringAsFixed(1)} m',
        if (evidence.majorRoadCount != null)
          'Major road features: ${evidence.majorRoadCount}',
        scoreText(evidence.suggestedScore),
        sourceConfidenceText(evidence.source, evidence.confidence),
      ],
      buttonLabel: null,
      onApply: null,
    );
  }

  Widget buildCommercialSuggestion(CommercialActivityEvidence evidence) {
    if (!evidence.available) return const SizedBox.shrink();
    return buildSuggestionSection(
      title: 'Commercial Activity',
      evidence: [
        if (evidence.commercialPoiCount != null)
          'Commercial POIs: ${evidence.commercialPoiCount}',
        if (evidence.commercialLanduseCount != null)
          'Commercial land-use features: ${evidence.commercialLanduseCount}',
        scoreText(evidence.suggestedScore),
        sourceConfidenceText(evidence.source, evidence.confidence),
      ],
      buttonLabel: null,
      onApply: null,
    );
  }

  Widget buildResidentialSuggestion(ResidentialActivityEvidence evidence) {
    if (!evidence.available) return const SizedBox.shrink();
    return buildSuggestionSection(
      title: 'Residential Activity',
      evidence: [
        if (evidence.residentialFeatureCount != null)
          'Residential features: ${evidence.residentialFeatureCount}',
        if (evidence.residentialLanduseCount != null)
          'Residential land-use features: ${evidence.residentialLanduseCount}',
        scoreText(evidence.suggestedScore),
        sourceConfidenceText(evidence.source, evidence.confidence),
      ],
      buttonLabel: null,
      onApply: null,
    );
  }

  Widget buildLandSuggestion(LandAccessibilityEvidence evidence) {
    if (!evidence.available) return const SizedBox.shrink();
    return buildSuggestionSection(
      title: 'Land Accessibility Proxy',
      evidence: [
        if (evidence.nearestAccessRoadM != null)
          'Nearest access road: ${evidence.nearestAccessRoadM!.toStringAsFixed(1)} m',
        if (evidence.restrictedAccessFeatureCount != null)
          'Restricted-access features: ${evidence.restrictedAccessFeatureCount}',
        scoreText(evidence.suggestedScore),
        sourceConfidenceText(evidence.source, evidence.confidence),
        'This does not establish ownership, legal access, planning permission or site availability.',
      ],
      buttonLabel: null,
      onApply: null,
    );
  }

  Widget buildSuggestionSection({
    required String title,
    required List<String> evidence,
    required String? buttonLabel,
    required VoidCallback? onApply,
  }) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in evidence)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(line, style: const TextStyle(fontSize: 13)),
                ),
              if (buttonLabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: OutlinedButton(
                    onPressed: isSaving ? null : onApply,
                    child: Text(buttonLabel),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String scoreText(int? score) => score == null
      ? 'Suggested score unavailable'
      : 'Suggested Score: $score / 5';

  String sourceConfidenceText(
    String? source,
    SiteFactorConfidence confidence,
  ) =>
      '${source == null ? 'Source unavailable' : 'Source: $source'} · '
      'Confidence: ${confidenceLabel(confidence)}';

  String confidenceLabel(SiteFactorConfidence confidence) =>
      switch (confidence) {
        SiteFactorConfidence.medium => 'Medium',
        SiteFactorConfidence.low => 'Low',
      };

  String get selectedSiteSummaryText {
    final validation = selectedSiteValidationResult!;
    final candidate = validation.candidate;
    final district = selectedSiteFactorIntelligenceResult?.districtReference;
    return 'Validated site: '
        '${candidate.point.latitude.toStringAsFixed(5)}, '
        '${candidate.point.longitude.toStringAsFixed(5)}'
        '\nRadius: ${candidate.analysisRadiusKm.toStringAsFixed(0)} km'
        '\nConfirmed territory: ${candidate.confirmedTerritory!.displayLabel}'
        '${district == null ? '' : '\nDistrict reference: ${district.name}'}'
        '\nGeographically validated';
  }

  @override
  void dispose() {
    draftSaveTimer?.cancel();
    for (final controller in draftControllers) {
      controller.removeListener(scheduleDraftSave);
    }
    locationController.dispose();
    populationController.dispose();
    vehicleCountController.dispose();
    nearbyStationsController.dispose();
    competitorDistanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('New Assessment'),
        backgroundColor: const Color(0xFF168C4B),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (isDraftRestored) ...[
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.save_outlined,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'A local draft was restored. Revalidate any site before saving.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: clearDraft,
                      child: const Text('Discard'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            key: const ValueKey('view-east-malaysia-map-button'),
            onPressed: selectSiteOnMap,
            icon: const Icon(Icons.map_outlined),
            label: const Text('Select Site on Map'),
          ),
          if (selectedSiteValidationResult?.candidate.isValidatedInside ==
              true) ...[
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  selectedSiteSummaryText,
                  key: const ValueKey('selected-site-summary'),
                ),
              ),
            ),
          ],
          buildSiteDataSuggestionsPanel(),
          if (submissionErrorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              submissionErrorMessage!,
              key: const ValueKey('assessment-submit-error'),
              style: const TextStyle(color: Colors.red),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Location and Demand',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),
              compactInformationButton(
                key: const ValueKey('location-demand-information-button'),
                tooltip: 'About location and demand',
                onPressed: () => _showInformationDialog(
                  title: 'Location and Demand',
                  message:
                      'Population Density may use an estimated Site Data value.\n\n'
                      'Registered Vehicle Count is always a manual local estimate. '
                      'No verified dataset provides the number of registered vehicles '
                      'inside the selected radius. Any JPJ/data.gov.my reference in '
                      'Site Data is regional registration-office/channel data only.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          inputField(
            controller: locationController,
            label: 'Location Name',
            hint: 'Example: Setapak, Kuala Lumpur',
            icon: Icons.location_on_outlined,
          ),
          inputField(
            controller: populationController,
            label: 'Population Density',
            hint: 'People per square kilometre',
            icon: Icons.groups_outlined,
            isDecimal: true,
          ),
          inputField(
            controller: vehicleCountController,
            label: 'Registered Vehicle Count',
            hint: 'Enter your local estimate',
            icon: Icons.directions_car_outlined,
            isNumber: true,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Competition',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),
              compactInformationButton(
                key: const ValueKey('competition-information-button'),
                tooltip: 'About competition data',
                onPressed: () => _showInformationDialog(
                  title: 'Competition',
                  message:
                      'Nearby Fuel Stations and Nearest Competitor Distance use '
                      'OpenStreetMap data when it is available.\n\n'
                      'Nearest Competitor Distance is the nearest returned fuel '
                      'station within the selected radius. If none is returned, it '
                      'is not set to 0 km; enter a verified manual estimate before '
                      'calculating the score.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          inputField(
            controller: nearbyStationsController,
            label: 'Nearby Fuel Stations',
            hint: 'Number of nearby competitors',
            icon: Icons.local_gas_station_outlined,
            isNumber: true,
          ),
          inputField(
            controller: competitorDistanceController,
            label: 'Nearest Competitor Distance',
            hint: 'Distance in kilometres',
            icon: Icons.route_outlined,
            isDecimal: true,
          ),
          if (requiresManualCompetitorDistance)
            Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'No nearest competitor distance was returned inside the '
                'selected radius. It was not set to 0 km; enter a verified '
                'manual estimate before calculating the score.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Area Ratings',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),
              compactInformationButton(
                key: const ValueKey('area-ratings-information-button'),
                tooltip: 'How ratings are used',
                onPressed: () => _showInformationDialog(
                  title: 'Area Ratings',
                  message:
                      'Rate each factor from 1 (Very Low) to 5 (Very High).\n\n'
                      'Traffic Level is manual: use your own observation or a '
                      'separate traffic-data provider. It is never inferred from '
                      'roads or OpenStreetMap data.\n\n'
                      'Road, commercial, residential and land suggestions can fill '
                      'an untouched default rating after Site Data loads. You can '
                      'change every rating.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ratingField(
            label: 'Traffic Level',
            icon: Icons.traffic,
            value: trafficLevel,
            onChanged: (value) {
              setState(() {
                trafficLevel = value;
              });
              scheduleDraftSave();
            },
          ),
          ratingField(
            label: 'Road Accessibility',
            icon: Icons.add_road,
            value: roadAccessibility,
            onChanged: (value) {
              setState(() {
                roadAccessibility = value;
                roadAccessibilityEdited = true;
              });
              scheduleDraftSave();
            },
          ),
          ratingField(
            label: 'Commercial Activity',
            icon: Icons.storefront,
            value: commercialActivity,
            onChanged: (value) {
              setState(() {
                commercialActivity = value;
                commercialActivityEdited = true;
              });
              scheduleDraftSave();
            },
          ),
          ratingField(
            label: 'Residential Activity',
            icon: Icons.home_work_outlined,
            value: residentialActivity,
            onChanged: (value) {
              setState(() {
                residentialActivity = value;
                residentialActivityEdited = true;
              });
              scheduleDraftSave();
            },
          ),
          ratingField(
            label: 'Land Accessibility',
            icon: Icons.landscape_outlined,
            value: landAccessibility,
            onChanged: (value) {
              setState(() {
                landAccessibility = value;
                landAccessibilityEdited = true;
              });
              scheduleDraftSave();
            },
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            key: const ValueKey('run-assessment-button'),
            onPressed: isSaving ? null : runAssessment,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: const Color(0xFF168C4B),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.green.shade200,
            ),
            icon: isSaving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.psychology),
            label: Text(
              isSaving ? 'Assessing...' : 'Run AI Assessment',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget inputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isNumber = false,
    bool isDecimal = false,
    String? informationMessage,
  }) {
    final errorText = fieldErrors[label];
    final maximum = _numericMaximums[label];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        onChanged: (_) {
          if (!fieldErrors.containsKey(label)) return;
          setState(() {
            fieldErrors = Map.of(fieldErrors)..remove(label);
          });
        },
        inputFormatters: maximum == null
            ? null
            : [
                TextInputFormatter.withFunction((oldValue, newValue) {
                  final entered = double.tryParse(newValue.text);
                  return entered == null || entered <= maximum
                      ? newValue
                      : oldValue;
                }),
              ],
        keyboardType: isDecimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : isNumber
            ? TextInputType.number
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: errorText,
          prefixIcon: Icon(icon),
          suffixIcon: informationMessage == null
              ? null
              : compactInformationButton(
                  tooltip: 'More information',
                  onPressed: () => _showInformationDialog(
                    title: label,
                    message: informationMessage,
                  ),
                ),
        ),
      ),
    );
  }

  Widget ratingField({
    required String label,
    required IconData icon,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<int>(
        key: ValueKey('$label-$value'),
        initialValue: value,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        items: List.generate(5, (index) {
          final rating = index + 1;

          return DropdownMenuItem(
            value: rating,
            child: Text('$rating - ${ratingLabel(rating)}'),
          );
        }),
        onChanged: isSaving
            ? null
            : (newValue) {
                if (newValue != null) {
                  onChanged(newValue);
                }
              },
      ),
    );
  }

  Widget compactInformationButton({
    Key? key,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      key: key,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      icon: const Icon(Icons.info_outline),
      onPressed: onPressed,
    );
  }

  String ratingLabel(int rating) {
    switch (rating) {
      case 1:
        return 'Very Low';
      case 2:
        return 'Low';
      case 3:
        return 'Moderate';
      case 4:
        return 'High';
      case 5:
        return 'Very High';
      default:
        return '';
    }
  }
}

String _generateRequestId() => const Uuid().v4();
