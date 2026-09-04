import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/station_assessment.dart';
import '../../models/station_assessment_create_input.dart';
import '../../models/east_malaysia_map_selection.dart';
import '../../models/east_malaysia_site_validation_result.dart';
import '../../services/station_assessment_repository.dart';
import '../../services/station_assessment_service.dart';
import 'assessment_result_screen.dart';
import 'east_malaysia_map_screen.dart';

typedef AssessmentUpdater =
    Future<StationAssessment> Function(
      String assessmentId,
      StationAssessmentCreateInput input,
    );

class EditAssessmentScreen extends StatefulWidget {
  final StationAssessment assessment;
  final AssessmentUpdater? assessmentUpdater;

  const EditAssessmentScreen({
    super.key,
    required this.assessment,
    this.assessmentUpdater,
  });

  @override
  State<EditAssessmentScreen> createState() => _EditAssessmentScreenState();
}

class _EditAssessmentScreenState extends State<EditAssessmentScreen> {
  static const _numericMaximums = <String, num>{
    'Population Density': 100000,
    'Registered Vehicle Count': 10000000,
    'Nearby Fuel Stations': 100,
    'Nearest Competitor Distance': 10,
  };

  late final TextEditingController locationController;
  late final TextEditingController populationController;
  late final TextEditingController vehicleCountController;
  late final TextEditingController nearbyStationsController;
  late final TextEditingController competitorDistanceController;

  int trafficLevel = 3;
  int roadAccessibility = 3;
  int commercialActivity = 3;
  int residentialActivity = 3;
  int landAccessibility = 3;

  bool isSaving = false;

  EastMalaysiaSiteValidationResult? get storedValidationResult {
    final assessment = widget.assessment;
    final location = assessment.siteLocation;
    final radius = assessment.analysisRadiusKm;
    final territory = assessment.confirmedTerritory;
    final datasetId = assessment.boundaryDatasetId;
    if (assessment.geographicValidationStatus !=
            StationAssessmentGeographicStatus.inside ||
        location == null ||
        radius == null ||
        territory == null ||
        datasetId == null) {
      return null;
    }

    return EastMalaysiaSiteValidationResult.fromRpcRow(
      row: {
        'validation_status': 'inside',
        'confirmed_territory': territory.storageValue,
        'boundary_dataset_id': datasetId,
      },
      point: location,
      analysisRadiusKm: radius.toDouble(),
    );
  }

  Future<void> viewStoredSiteOnMap() async {
    final validation = storedValidationResult;
    if (validation == null) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => EastMalaysiaMapScreen(
          initialSelection: EastMalaysiaMapSelection(
            validationResult: validation,
          ),
          allowCandidateUpdate: false,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    final assessment = widget.assessment;

    locationController = TextEditingController(text: assessment.locationName);

    populationController = TextEditingController(
      text: assessment.populationDensity.toString(),
    );

    vehicleCountController = TextEditingController(
      text: assessment.registeredVehicleCount.toString(),
    );

    nearbyStationsController = TextEditingController(
      text: assessment.nearbyFuelStations.toString(),
    );

    competitorDistanceController = TextEditingController(
      text: assessment.competitorDistanceKm.toString(),
    );

    trafficLevel = assessment.trafficLevel;
    roadAccessibility = assessment.roadAccessibility;
    commercialActivity = assessment.commercialActivity;
    residentialActivity = assessment.residentialActivity;
    landAccessibility = assessment.landAccessibility;
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

    if (populationDensity > _numericMaximums['Population Density']! ||
        registeredVehicleCount >
            _numericMaximums['Registered Vehicle Count']! ||
        nearbyFuelStations > _numericMaximums['Nearby Fuel Stations']! ||
        competitorDistanceKm >
            _numericMaximums['Nearest Competitor Distance']!) {
      showMessage('Enter values within the allowed limits', isError: true);
      return;
    }

    setState(() {
      isSaving = true;
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

      final updater =
          widget.assessmentUpdater ??
          StationAssessmentRepository(
            Supabase.instance.client,
          ).updateAssessment;
      final savedAssessment = await updater(widget.assessment.id, input);

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
    } on AssessmentUpdateRejectedException {
      if (!mounted) return;
      showMessage(
        'Assessment could not be updated. It may be unavailable or you may '
        'not have permission.',
        isError: true,
      );
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Update Assessment'),
        backgroundColor: const Color(0xFF168C4B),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (storedValidationResult != null) ...[
            OutlinedButton.icon(
              key: const ValueKey('view-stored-site-map-button'),
              onPressed: viewStoredSiteOnMap,
              icon: const Icon(Icons.map_outlined),
              label: const Text('View Validated Site Map'),
            ),
            const SizedBox(height: 12),
            Material(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Validated site: '
                  '${widget.assessment.siteLocation!.latitude.toStringAsFixed(5)}, '
                  '${widget.assessment.siteLocation!.longitude.toStringAsFixed(5)}'
                  '\nRadius: ${widget.assessment.analysisRadiusKm} km'
                  '\nConfirmed territory: ${widget.assessment.confirmedTerritory!.displayLabel}'
                  '\nGeographically validated',
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
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
            maxLength: 100,
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
          Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Enter a local estimate manually. No verified dataset provides '
              'the registered-vehicle count within the selected radius.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
          Text(
            'Rate each factor from 1 (Very Low) to 5 (Very High).',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
            key: const ValueKey('update-assessment-button'),
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
              isSaving ? 'Reassessing...' : 'Recalculate Assessment',
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
    int? maxLength,
  }) {
    final maximum = _numericMaximums[label];
    final inputFormatters = <TextInputFormatter>[
      if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
      if (maximum != null)
        TextInputFormatter.withFunction((oldValue, newValue) {
          final entered = double.tryParse(newValue.text);
          return entered == null || entered <= maximum ? newValue : oldValue;
        }),
      if (isDecimal)
        TextInputFormatter.withFunction((oldValue, newValue) {
          return newValue.text.isEmpty ||
                  RegExp(
                    r'^(?:0|[1-9]\d*)(?:\.\d{0,2})?$',
                  ).hasMatch(newValue.text)
              ? newValue
              : oldValue;
        }),
      if (isNumber)
        TextInputFormatter.withFunction((oldValue, newValue) {
          return newValue.text.isEmpty ||
                  RegExp(r'^(?:0|[1-9]\d*)$').hasMatch(newValue.text)
              ? newValue
              : oldValue;
        }),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        inputFormatters: inputFormatters.isEmpty ? null : inputFormatters,
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
