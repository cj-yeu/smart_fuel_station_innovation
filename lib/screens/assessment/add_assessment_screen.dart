import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../models/east_malaysia_site_validation_result.dart';
import '../../models/east_malaysia_map_selection.dart';
import '../../models/nearby_fuel_station_result.dart';
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

  bool isSaving = false;
  bool requiresSiteRevalidation = false;
  String? submissionErrorMessage;
  EastMalaysiaSiteValidationResult? selectedSiteValidationResult;
  NearbyFuelStationResult? selectedNearbyFuelStationResult;
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
    final selectedResult =
        await Navigator.push<Object?>(
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
      _applyNearbyFuelStationAutofill(selection.nearbyFuelStations);
      requiresSiteRevalidation = false;
      submissionErrorMessage = null;
    });
  }

  void _applyNearbyFuelStationAutofill(NearbyFuelStationResult? result) {
    if (result == null) return;
    nearbyStationsController.text = result.stationCount.toString();
    competitorDistanceController.text =
        result.nearestDistanceKm?.toString() ?? '0';
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
                  'Validated site: '
                  '${selectedSiteValidationResult!.candidate.point.latitude.toStringAsFixed(5)}, '
                  '${selectedSiteValidationResult!.candidate.point.longitude.toStringAsFixed(5)}'
                  '\nRadius: '
                  '${selectedSiteValidationResult!.candidate.analysisRadiusKm.toStringAsFixed(0)} km'
                  '\nConfirmed territory: '
                  '${selectedSiteValidationResult!.candidate.confirmedTerritory!.displayLabel}'
                  '\nGeographically validated',
                  key: const ValueKey('selected-site-summary'),
                ),
              ),
            ),
          ],
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
            hint: 'Estimated vehicles in the area',
            icon: Icons.directions_car_outlined,
            isNumber: true,
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
          ratingField(
            label: 'Road Accessibility',
            icon: Icons.add_road,
            value: roadAccessibility,
            onChanged: (value) {
              setState(() {
                roadAccessibility = value;
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
