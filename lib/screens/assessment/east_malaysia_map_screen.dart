import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

typedef EastMalaysiaMapContentBuilder = Widget Function(BuildContext context);

class EastMalaysiaMapScreen extends StatelessWidget {
  static const tileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const tileUserAgentPackageName =
      'com.example.smart_fuell_station_innovation';

  final EastMalaysiaMapContentBuilder? mapContentBuilder;

  const EastMalaysiaMapScreen({super.key, this.mapContentBuilder});

  @override
  Widget build(BuildContext context) {
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
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Sabah • Sarawak • Labuan',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFE7F3EC),
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              child: Padding(
                padding: EdgeInsets.all(12),
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
                mapContentBuilder?.call(context) ??
                const _ProductionEastMalaysiaMap(),
          ),
        ],
      ),
    );
  }
}

class _ProductionEastMalaysiaMap extends StatelessWidget {
  const _ProductionEastMalaysiaMap();

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
      ),
      children: [
        TileLayer(
          urlTemplate: EastMalaysiaMapScreen.tileUrlTemplate,
          userAgentPackageName: EastMalaysiaMapScreen.tileUserAgentPackageName,
        ),
        const SimpleAttributionWidget(
          source: Text('OpenStreetMap contributors'),
          alignment: Alignment.bottomRight,
        ),
      ],
    );
  }
}
