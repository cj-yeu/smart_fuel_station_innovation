import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../models/east_malaysia_site_validation_result.dart';
import '../../models/east_malaysia_map_selection.dart';
import '../../models/nearby_fuel_station_result.dart';
import '../../models/site_factor_intelligence_result.dart';
import '../../models/station_assessment.dart';
import '../../models/station_assessment_create_input.dart';
import '../../models/station_assessment_validated_create_input.dart';
import '../../services/station_assessment_repository.dart';
import '../../services/station_assessment_service.dart';
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

  const AddAssessmentScreen({
    super.key,
    this.assessmentCreator,
    this.validatedAssessmentCreator,
    this.mapScreenBuilder,
    this.requestIdGenerator,
  });

  @override
  State<AddAssessmentScreen> createState() => _AddAssessmentScreenState();
}

class _AddAssessmentScreenState extends State<AddAssessmentScreen> {
  late final AssessmentCreator assessmentCreator;

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
  EastMalaysiaSiteValidationResult? selectedSiteValidationResult;
  NearbyFuelStationResult? selectedNearbyFuelStationResult;
  SiteFactorIntelligenceResult? selectedSiteFactorIntelligenceResult;
  String? validatedRequestId;
  String? validatedPayloadFingerprint;

  @override
  void initState() {
    super.initState();
    assessmentCreator =
        widget.assessmentCreator ??
        StationAssessmentRepository(Supabase.instance.client).createAssessment;
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

    if (locationName.isEmpty ||
        populationDensity == null ||
        registeredVehicleCount == null ||
        nearbyFuelStations == null ||
        competitorDistanceKm == null) {
      showMessage('Please fill in all fields', isError: true);
      return;
    }

    if (populationDensity < 0 ||
        registeredVehicleCount < 0 ||
        nearbyFuelStations < 0 ||
        competitorDistanceKm < 0) {
      showMessage('Numeric values cannot be negative', isError: true);
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
    });

    try {
      final result = StationAssessmentService.calculate(
        populationDensity: populationDensity,
        trafficLevel: trafficLevel,
        registeredVehicleCount: registeredVehicleCount,
        nearbyFuelStations: nearbyFuelStations,
        competitorDistanceKm: competitorDistanceKm,
        roadAccessibility: roadAccessibility,
        commercialActivity: commercialActivity,
        residentialActivity: residentialActivity,
        landAccessibility: landAccessibility,
      );

      final input = StationAssessmentCreateInput(
        locationName: locationName,
        populationDensity: populationDensity,
        trafficLevel: trafficLevel,
        registeredVehicleCount: registeredVehicleCount,
        nearbyFuelStations: nearbyFuelStations,
        competitorDistanceKm: competitorDistanceKm,
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
        await (widget.validatedAssessmentCreator ??
            StationAssessmentRepository(
              Supabase.instance.client,
            ).createValidatedAssessment)(validatedInput);
        validatedRequestId = null;
        validatedPayloadFingerprint = null;
      } else {
        await assessmentCreator(input);
      }

      if (!mounted) return;

      final completed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => AssessmentResultScreen(
            locationName: locationName,
            result: result,
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
  }

  void _applyNearbyFuelStationAutofill(NearbyFuelStationResult? result) {
    if (result == null) return;
    if (nearbyStationsController.text.trim().isEmpty) {
      nearbyStationsController.text = result.stationCount.toString();
    }
    if (competitorDistanceController.text.trim().isEmpty) {
      competitorDistanceController.text = (result.nearestDistanceKm ?? 0)
          .toStringAsFixed(2);
    }
  }

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

    final vehicleDemand = intelligence.vehicleDemand;
    if (vehicleDemand.hasUsableSuggestion &&
        vehicleCountController.text.trim().isEmpty) {
      vehicleCountController.text = vehicleDemand.value.toString();
    }

    _applyAutomaticScore(
      intelligence.roadAccessibility.suggestedScore,
      alreadyEdited: roadAccessibilityEdited,
      apply: (value) => roadAccessibility = value,
    );
    _applyAutomaticScore(
      intelligence.commercialActivity.suggestedScore,
      alreadyEdited: commercialActivityEdited,
      apply: (value) => commercialActivity = value,
    );
    _applyAutomaticScore(
      intelligence.residentialActivity.suggestedScore,
      alreadyEdited: residentialActivityEdited,
      apply: (value) => residentialActivity = value,
    );
    _applyAutomaticScore(
      intelligence.landAccessibility.suggestedScore,
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

    return Card(
      key: const ValueKey('site-data-suggestions-panel'),
      margin: const EdgeInsets.only(top: 12),
      color: const Color(0xFFE8F1FC),
      child: ExpansionTile(
        title: const Text('Site Data'),
        subtitle: const Text(
          'Available suggested values were filled into empty fields.',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          buildPopulationSuggestion(intelligence.population),
          buildVehicleDemandSuggestion(intelligence.vehicleDemand),
          buildRoadSuggestion(intelligence.roadAccessibility),
          buildCommercialSuggestion(intelligence.commercialActivity),
          buildResidentialSuggestion(intelligence.residentialActivity),
          buildLandSuggestion(intelligence.landAccessibility),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'OSM-based scores are mapping-completeness proxies. Review them '
              'before use; they do not measure traffic or legal land access.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          if (intelligence.attribution.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Attribution: ${intelligence.attribution.map((item) => '${item.source} (${item.licence})').join(' • ')}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
        ],
      ),
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

  Widget buildVehicleDemandSuggestion(VehicleDemandProxy evidence) {
    if (!evidence.available || !evidence.hasUsableSuggestion) {
      return const SizedBox.shrink();
    }
    return buildSuggestionSection(
      title: evidence.isProxy
          ? 'Regional vehicle-registration proxy'
          : 'Vehicle demand',
      evidence: [
        'Value: ${evidence.value}',
        if (evidence.geographicScope != null)
          'Geographic scope: ${evidence.geographicScope}',
        if (evidence.dataPeriod != null) 'Period: ${evidence.dataPeriod}',
        if (evidence.source != null) 'Source: ${evidence.source}',
        'This is not a vehicle count within the selected radius.',
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
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text('New Assessment'),
        backgroundColor: const Color(0xFF168C4B),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
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
              decoration: const BoxDecoration(
                color: Color(0xFFE7F3EC),
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
          const Text(
            'Location and Demand',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
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
            hint: 'Enter your local vehicle-demand estimate',
            icon: Icons.directions_car_outlined,
            isNumber: true,
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'When available, the auto-filled number is a regional JPJ '
              'registration-channel proxy—not vehicles near this site. You can '
              'edit it manually.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Competition',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
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
          const SizedBox(height: 8),
          const Text(
            'Area Ratings',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Rate each factor from 1 (Very Low) to 5 (Very High).',
            style: TextStyle(color: Colors.black54),
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
            },
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Traffic level requires observation or a separate traffic-data provider.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        keyboardType: isDecimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : isNumber
            ? TextInputType.number
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon),
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
