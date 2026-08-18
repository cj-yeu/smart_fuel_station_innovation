import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/assessment_site_candidate.dart';
import '../../models/east_malaysia_site_validation_result.dart';
import '../../models/geo_point.dart';
import '../../services/east_malaysia_geography_repository.dart';

typedef EastMalaysiaMapContentBuilder =
    Widget Function(
      BuildContext context,
      AssessmentSiteCandidate? candidate,
      ValueChanged<GeoPoint> onPointSelected,
    );
typedef EastMalaysiaSiteValidator =
    Future<EastMalaysiaSiteValidationResult> Function({
      required GeoPoint point,
      required double analysisRadiusKm,
    });
typedef EastMalaysiaExternalUrlLauncher =
    Future<bool> Function(Uri url, {LaunchMode mode});

class EastMalaysiaMapScreen extends StatefulWidget {
  static const tileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const tileUserAgentPackageName =
      'com.example.smart_fuell_station_innovation';
  static final osmCopyrightUri = Uri.parse(
    'https://www.openstreetmap.org/copyright',
  );
  static final geoBoundariesProjectUri = Uri.parse(
    'https://www.geoboundaries.org/',
  );
  static final ccByFourLicenceUri = Uri.parse(
    'https://creativecommons.org/licenses/by/4.0/',
  );
  static const osmAttributionLaunchMode = LaunchMode.externalApplication;

  final EastMalaysiaSiteValidationResult? initialValidationResult;
  final EastMalaysiaMapContentBuilder? mapContentBuilder;
  final EastMalaysiaSiteValidator? validator;

  const EastMalaysiaMapScreen({
    super.key,
    this.initialValidationResult,
    this.mapContentBuilder,
    this.validator,
  });

  @visibleForTesting
  static List<Widget> buildSelectionLayers(AssessmentSiteCandidate? candidate) {
    if (candidate == null) return const [];

    final point = LatLng(candidate.point.latitude, candidate.point.longitude);

    return [
      CircleLayer(
        circles: [
          CircleMarker(
            point: point,
            radius: candidate.analysisRadiusKm * 1000,
            useRadiusInMeter: true,
            color: const Color(0x332196F3),
            borderColor: const Color(0xFF0D47A1),
            borderStrokeWidth: 3,
          ),
        ],
      ),
      MarkerLayer(
        markers: [
          Marker(
            point: point,
            width: 48,
            height: 48,
            alignment: Alignment.topCenter,
            child: Semantics(
              label: 'Selected site candidate',
              child: const Icon(
                Icons.location_pin,
                size: 44,
                color: Color(0xFFC62828),
                shadows: [Shadow(color: Colors.white, blurRadius: 3)],
              ),
            ),
          ),
        ],
      ),
    ];
  }

  @visibleForTesting
  static SimpleAttributionWidget buildOsmAttribution({
    EastMalaysiaExternalUrlLauncher? launcher,
  }) {
    final externalLauncher = launcher ?? launchUrl;
    return SimpleAttributionWidget(
      source: const Text('OpenStreetMap contributors'),
      alignment: Alignment.bottomRight,
      onTap: () async {
        await externalLauncher(osmCopyrightUri, mode: osmAttributionLaunchMode);
      },
    );
  }

  @visibleForTesting
  static Widget buildBoundaryAttribution({
    EastMalaysiaExternalUrlLauncher? launcher,
  }) {
    final externalLauncher = launcher ?? launchUrl;

    return Align(
      key: const ValueKey('boundary-data-attribution'),
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 4, bottom: 28),
        child: Material(
          color: const Color(0xD9FFFFFF),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Boundary validation: ',
                  style: TextStyle(fontSize: 11),
                ),
                InkWell(
                  key: const ValueKey('geoboundaries-attribution-link'),
                  onTap: () async {
                    await externalLauncher(
                      geoBoundariesProjectUri,
                      mode: osmAttributionLaunchMode,
                    );
                  },
                  child: const Text(
                    'geoBoundaries',
                    style: TextStyle(
                      fontSize: 11,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const Text(' (', style: TextStyle(fontSize: 11)),
                InkWell(
                  key: const ValueKey('cc-by-four-attribution-link'),
                  onTap: () async {
                    await externalLauncher(
                      ccByFourLicenceUri,
                      mode: osmAttributionLaunchMode,
                    );
                  },
                  child: const Text(
                    'CC BY 4.0',
                    style: TextStyle(
                      fontSize: 11,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const Text(')', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<EastMalaysiaMapScreen> createState() => _EastMalaysiaMapScreenState();
}

class _EastMalaysiaMapScreenState extends State<EastMalaysiaMapScreen> {
  late GeoPoint? selectedPoint =
      widget.initialValidationResult?.candidate.point;
  late double selectedRadiusKm =
      widget.initialValidationResult?.candidate.analysisRadiusKm ?? 5;
  late EastMalaysiaSiteValidationResult? validationResult =
      widget.initialValidationResult;
  EastMalaysiaSiteValidator? _productionValidator;
  bool isValidating = false;
  String? validationError;

  EastMalaysiaSiteValidator get validator =>
      widget.validator ??
      (_productionValidator ??= EastMalaysiaGeographyRepository(
        Supabase.instance.client,
      ).validateSite);

  AssessmentSiteCandidate? get candidate {
    final validatedCandidate = validationResult?.candidate;
    if (validatedCandidate != null) return validatedCandidate;

    final point = selectedPoint;
    if (point == null) return null;

    return AssessmentSiteCandidate(
      point: point,
      analysisRadiusKm: selectedRadiusKm,
      validationStatus: GeographicValidationStatus.unverified,
    );
  }

  void selectPoint(GeoPoint point) {
    if (isValidating) return;
    setState(() {
      selectedPoint = point;
      validationResult = null;
      validationError = null;
    });
  }

  void changeRadius(double radiusKm) {
    if (isValidating) return;
    setState(() {
      selectedRadiusKm = radiusKm;
      validationResult = null;
      validationError = null;
    });
  }

  Future<void> validateCandidate() async {
    if (isValidating) return;
    final currentCandidate = candidate;
    if (currentCandidate == null) return;

    setState(() {
      isValidating = true;
      validationError = null;
    });

    try {
      final result = await validator(
        point: currentCandidate.point,
        analysisRadiusKm: currentCandidate.analysisRadiusKm,
      );
      if (!mounted) return;
      setState(() {
        validationResult = result;
        selectedPoint = result.candidate.point;
        selectedRadiusKm = result.candidate.analysisRadiusKm;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        validationError = 'Unable to validate this site. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isValidating = false;
        });
      }
    }
  }

  String get validationStatusText {
    final result = validationResult;
    if (result == null) return 'Not yet geographically validated';

    return switch (result.candidate.validationStatus) {
      GeographicValidationStatus.inside =>
        'Confirmed in ${result.candidate.confirmedTerritory!.displayLabel}',
      GeographicValidationStatus.outside =>
        'Outside the supported East Malaysia territories',
      GeographicValidationStatus.unverified =>
        'Unable to verify yet because authoritative boundary data is '
            'unavailable',
      GeographicValidationStatus.boundaryReviewRequired =>
        'Boundary review required',
    };
  }

  Color get validationStatusColor {
    return validationResult?.candidate.validationStatus ==
            GeographicValidationStatus.inside
        ? const Color(0xFF1B5E20)
        : const Color(0xFFC62828);
  }

  @override
  Widget build(BuildContext context) {
    final currentCandidate = candidate;

    return Scaffold(
      appBar: AppBar(
        title: const Text('East Malaysia Site Map'),
        backgroundColor: const Color(0xFF168C4B),
        foregroundColor: Colors.white,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              'Sabah • Sarawak • Labuan',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFE7F3EC),
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              child: Padding(
                padding: EdgeInsets.all(10),
                child: Text(
                  'The map viewport is for navigation only. Territory '
                  'eligibility will be determined by authoritative boundary '
                  'validation.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          Expanded(
            child:
                widget.mapContentBuilder?.call(
                  context,
                  currentCandidate,
                  selectPoint,
                ) ??
                _ProductionEastMalaysiaMap(
                  candidate: currentCandidate,
                  onPointSelected: selectPoint,
                ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (currentCandidate == null)
                  const Text(
                    'Tap the map to choose a candidate point.',
                    textAlign: TextAlign.center,
                  )
                else
                  Text(
                    'Latitude: '
                    '${currentCandidate.point.latitude.toStringAsFixed(5)}  '
                    'Longitude: '
                    '${currentCandidate.point.longitude.toStringAsFixed(5)}',
                    key: const ValueKey('selected-coordinate-summary'),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 6),
                Text(
                  validationStatusText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: validationStatusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (validationError != null)
                  Text(
                    validationError!,
                    key: const ValueKey('validation-error-message'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFC62828)),
                  ),
                const Text(
                  'The radius circle is analysis context, not proof of '
                  'territory eligibility.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Analysis radius:'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<double>(
                        key: const ValueKey('analysis-radius-dropdown'),
                        value: selectedRadiusKm,
                        isExpanded: true,
                        items: AssessmentSiteCandidate.supportedAnalysisRadiiKm
                            .map(
                              (radius) => DropdownMenuItem<double>(
                                value: radius,
                                child: Text('${radius.toStringAsFixed(0)} km'),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: isValidating
                            ? null
                            : (radius) {
                                if (radius != null) changeRadius(radius);
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  key: const ValueKey('validate-site-button'),
                  onPressed: currentCandidate == null || isValidating
                      ? null
                      : validateCandidate,
                  child: Text(isValidating ? 'Validating...' : 'Validate Site'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        key: const ValueKey('use-candidate-button'),
                        onPressed:
                            !isValidating &&
                                validationResult?.candidate.isValidatedInside ==
                                    true
                            ? () => Navigator.pop(context, validationResult)
                            : null,
                        child: const Text('Use This Candidate'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductionEastMalaysiaMap extends StatelessWidget {
  final AssessmentSiteCandidate? candidate;
  final ValueChanged<GeoPoint> onPointSelected;

  const _ProductionEastMalaysiaMap({
    required this.candidate,
    required this.onPointSelected,
  });

  @override
  Widget build(BuildContext context) {
    final eastMalaysiaView = LatLngBounds(
      const LatLng(0.5, 109.0),
      const LatLng(7.7, 119.8),
    );

    // These camera bounds only keep navigation near the supported region.
    // They are deliberately not East Malaysia validation boundaries.
    final regionalCameraBounds = LatLngBounds(
      const LatLng(-1.5, 107.0),
      const LatLng(9.0, 121.5),
    );

    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: eastMalaysiaView,
          padding: const EdgeInsets.all(24),
        ),
        cameraConstraint: CameraConstraint.containCenter(
          bounds: regionalCameraBounds,
        ),
        minZoom: 4,
        maxZoom: 15,
        onTap: (tapPosition, point) {
          onPointSelected(
            GeoPoint(latitude: point.latitude, longitude: point.longitude),
          );
        },
      ),
      children: [
        TileLayer(
          urlTemplate: EastMalaysiaMapScreen.tileUrlTemplate,
          userAgentPackageName: EastMalaysiaMapScreen.tileUserAgentPackageName,
        ),
        ...EastMalaysiaMapScreen.buildSelectionLayers(candidate),
        EastMalaysiaMapScreen.buildBoundaryAttribution(),
        EastMalaysiaMapScreen.buildOsmAttribution(),
      ],
    );
  }
}
