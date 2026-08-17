import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/assessment_site_candidate.dart';
import '../../models/geo_point.dart';

typedef EastMalaysiaMapContentBuilder =
    Widget Function(
      BuildContext context,
      AssessmentSiteCandidate? candidate,
      ValueChanged<GeoPoint> onPointSelected,
    );

class EastMalaysiaMapScreen extends StatefulWidget {
  static const tileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const tileUserAgentPackageName =
      'com.example.smart_fuell_station_innovation';

  final AssessmentSiteCandidate? initialCandidate;
  final EastMalaysiaMapContentBuilder? mapContentBuilder;

  EastMalaysiaMapScreen({
    super.key,
    this.initialCandidate,
    this.mapContentBuilder,
  }) {
    final candidate = initialCandidate;
    if (candidate != null &&
        (candidate.validationStatus != GeographicValidationStatus.unverified ||
            candidate.confirmedTerritory != null)) {
      throw ArgumentError.value(
        candidate,
        'initialCandidate',
        'The initial map candidate must be unverified without a territory.',
      );
    }
  }

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

  @override
  State<EastMalaysiaMapScreen> createState() => _EastMalaysiaMapScreenState();
}

class _EastMalaysiaMapScreenState extends State<EastMalaysiaMapScreen> {
  late GeoPoint? selectedPoint = widget.initialCandidate?.point;
  late double selectedRadiusKm = widget.initialCandidate?.analysisRadiusKm ?? 5;

  AssessmentSiteCandidate? get candidate {
    final point = selectedPoint;
    if (point == null) return null;

    return AssessmentSiteCandidate(
      point: point,
      analysisRadiusKm: selectedRadiusKm,
      validationStatus: GeographicValidationStatus.unverified,
    );
  }

  void selectPoint(GeoPoint point) {
    setState(() {
      selectedPoint = point;
    });
  }

  void changeRadius(double radiusKm) {
    setState(() {
      selectedRadiusKm = radiusKm;
    });
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
                const Text(
                  'Not yet geographically validated',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFC62828),
                    fontWeight: FontWeight.bold,
                  ),
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
                        onChanged: (radius) {
                          if (radius != null) changeRadius(radius);
                        },
                      ),
                    ),
                  ],
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
                        onPressed: currentCandidate == null
                            ? null
                            : () => Navigator.pop(context, currentCandidate),
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
        const SimpleAttributionWidget(
          source: Text('OpenStreetMap contributors'),
          alignment: Alignment.bottomRight,
        ),
      ],
    );
  }
}
