import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/assessment_site_candidate.dart';
import '../../models/east_malaysia_map_selection.dart';
import '../../models/east_malaysia_site_validation_result.dart';
import '../../models/geo_point.dart';
import '../../models/nearby_fuel_station.dart';
import '../../models/nearby_fuel_station_result.dart';
import '../../models/site_factor_intelligence_result.dart';
import '../../services/east_malaysia_geography_repository.dart';
import '../../services/nearby_fuel_station_repository.dart';
import '../../services/site_factor_intelligence_repository.dart';

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
typedef NearbyFuelStationLoader =
    Future<NearbyFuelStationResult> Function(
      EastMalaysiaSiteValidationResult validationResult,
    );
typedef SiteFactorIntelligenceLoader =
    Future<SiteFactorIntelligenceResult> Function(
      EastMalaysiaSiteValidationResult validationResult,
    );
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
  final EastMalaysiaMapSelection? initialSelection;
  final EastMalaysiaMapContentBuilder? mapContentBuilder;
  final EastMalaysiaSiteValidator? validator;
  final NearbyFuelStationLoader? nearbyFuelStationLoader;
  final SiteFactorIntelligenceLoader? siteFactorIntelligenceLoader;
  final bool allowCandidateUpdate;

  const EastMalaysiaMapScreen({
    super.key,
    this.initialValidationResult,
    this.initialSelection,
    this.mapContentBuilder,
    this.validator,
    this.nearbyFuelStationLoader,
    this.siteFactorIntelligenceLoader,
    this.allowCandidateUpdate = true,
  }) : assert(initialValidationResult == null || initialSelection == null);

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
  static MarkerLayer buildFuelStationMarkers(List<NearbyFuelStation> stations) {
    return MarkerLayer(
      markers: stations
          .map(
            (station) => Marker(
              point: LatLng(station.latitude, station.longitude),
              width: 36,
              height: 36,
              alignment: Alignment.center,
              child: Semantics(
                label: 'Fuel station ${station.name ?? station.osmId}',
                child: const Icon(
                  Icons.local_gas_station,
                  color: Color(0xFF1565C0),
                  size: 28,
                  shadows: [Shadow(color: Colors.white, blurRadius: 3)],
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
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
  late GeoPoint? selectedPoint;
  late double selectedRadiusKm;
  late EastMalaysiaSiteValidationResult? validationResult;
  late NearbyFuelStationResult? nearbyFuelStationResult;
  late SiteFactorIntelligenceResult? siteFactorIntelligenceResult;
  EastMalaysiaSiteValidator? _productionValidator;
  NearbyFuelStationLoader? _productionNearbyFuelStationLoader;
  SiteFactorIntelligenceLoader? _productionSiteFactorIntelligenceLoader;
  bool isValidating = false;
  bool isLoadingNearbyFuelStations = false;
  bool isLoadingSiteFactorIntelligence = false;
  bool showAllNearbyFuelStations = false;
  String? validationError;
  String? nearbyFuelStationError;
  String? siteFactorIntelligenceError;

  @override
  void initState() {
    super.initState();
    final initialValidation =
        widget.initialSelection?.validationResult ??
        widget.initialValidationResult;
    selectedPoint = initialValidation?.candidate.point;
    selectedRadiusKm = initialValidation?.candidate.analysisRadiusKm ?? 5;
    validationResult = initialValidation;
    nearbyFuelStationResult = widget.initialSelection?.nearbyFuelStations;
    siteFactorIntelligenceResult =
        widget.initialSelection?.siteFactorIntelligence;
    if (initialValidation?.candidate.isValidatedInside == true &&
        (nearbyFuelStationResult == null ||
            siteFactorIntelligenceResult == null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && validationResult == initialValidation) {
          unawaited(loadSiteIntelligence(initialValidation!));
        }
      });
    }
  }

  EastMalaysiaSiteValidator get validator =>
      widget.validator ??
      (_productionValidator ??= EastMalaysiaGeographyRepository(
        Supabase.instance.client,
      ).validateSite);

  NearbyFuelStationLoader get nearbyFuelStationLoader =>
      widget.nearbyFuelStationLoader ??
      (_productionNearbyFuelStationLoader ??= NearbyFuelStationRepository(
        Supabase.instance.client,
      ).fetchForValidatedSite);

  SiteFactorIntelligenceLoader get siteFactorIntelligenceLoader =>
      widget.siteFactorIntelligenceLoader ??
      (_productionSiteFactorIntelligenceLoader ??=
          SiteFactorIntelligenceRepository(
            Supabase.instance.client,
          ).fetchForValidatedSite);

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
    if (isValidating || !widget.allowCandidateUpdate) return;
    setState(() {
      selectedPoint = point;
      validationResult = null;
      validationError = null;
      nearbyFuelStationResult = null;
      nearbyFuelStationError = null;
      siteFactorIntelligenceResult = null;
      siteFactorIntelligenceError = null;
      showAllNearbyFuelStations = false;
    });
  }

  void changeRadius(double radiusKm) {
    if (isValidating || !widget.allowCandidateUpdate) return;
    setState(() {
      selectedRadiusKm = radiusKm;
      validationResult = null;
      validationError = null;
      nearbyFuelStationResult = null;
      nearbyFuelStationError = null;
      siteFactorIntelligenceResult = null;
      siteFactorIntelligenceError = null;
      showAllNearbyFuelStations = false;
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
        showAllNearbyFuelStations = false;
      });
      if (result.candidate.isValidatedInside) {
        unawaited(loadSiteIntelligence(result));
      }
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

  Future<void> loadNearbyFuelStations(
    EastMalaysiaSiteValidationResult result,
  ) async {
    if (!result.candidate.isValidatedInside || isLoadingNearbyFuelStations) {
      return;
    }

    setState(() {
      isLoadingNearbyFuelStations = true;
      nearbyFuelStationError = null;
    });
    try {
      final stations = await nearbyFuelStationLoader(result);
      if (!mounted || validationResult != result) return;
      setState(() {
        nearbyFuelStationResult = stations;
      });
    } catch (_) {
      if (!mounted || validationResult != result) return;
      setState(() {
        nearbyFuelStationResult = null;
        nearbyFuelStationError =
            'Nearby fuel-station data is unavailable. You can retry or '
            'continue without it.';
      });
    } finally {
      if (mounted && validationResult == result) {
        setState(() {
          isLoadingNearbyFuelStations = false;
        });
      }
    }
  }

  Future<void> loadSiteIntelligence(
    EastMalaysiaSiteValidationResult result,
  ) async {
    if (!result.candidate.isValidatedInside) return;

    if (nearbyFuelStationResult == null && !isLoadingNearbyFuelStations) {
      await loadNearbyFuelStations(result);
    }
    if (!mounted ||
        validationResult != result ||
        isLoadingSiteFactorIntelligence) {
      return;
    }

    setState(() {
      isLoadingSiteFactorIntelligence = true;
      siteFactorIntelligenceError = null;
    });
    try {
      final intelligence = await siteFactorIntelligenceLoader(result);
      if (!mounted || validationResult != result) return;
      setState(() {
        siteFactorIntelligenceResult = intelligence;
      });
    } catch (_) {
      if (!mounted || validationResult != result) return;
      setState(() {
        siteFactorIntelligenceResult = null;
        siteFactorIntelligenceError =
            'Site data is unavailable. You can retry or continue '
            'with manual values.';
      });
    } finally {
      if (mounted && validationResult == result) {
        setState(() {
          isLoadingSiteFactorIntelligence = false;
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

  Widget buildNearbyFuelStationStatus() {
    final result = validationResult;
    if (result?.candidate.isValidatedInside != true) {
      return const SizedBox.shrink();
    }

    if (isLoadingNearbyFuelStations) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Loading nearby fuel stations...'),
          ],
        ),
      );
    }

    if (nearbyFuelStationError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          children: [
            Text(
              nearbyFuelStationError!,
              key: const ValueKey('nearby-fuel-stations-error'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFC62828)),
            ),
            TextButton(
              key: const ValueKey('retry-nearby-fuel-stations-button'),
              onPressed: () => loadNearbyFuelStations(result!),
              child: const Text('Retry nearby fuel stations'),
            ),
          ],
        ),
      );
    }

    final stations = nearbyFuelStationResult;
    if (stations == null) return const SizedBox.shrink();
    final nearest = stations.nearestDistanceKm;
    final visibleStations = showAllNearbyFuelStations
        ? stations.stations
        : stations.stations.take(5).toList(growable: false);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        key: const ValueKey('nearby-fuel-stations-summary'),
        decoration: const BoxDecoration(
          color: Color(0xFFE7F3EC),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Text('Nearby fuel stations: ${stations.stationCount}'),
              Text(
                nearest == null
                    ? 'Nearest competitor: none within the analysis radius'
                    : 'Nearest competitor: ${nearest.toStringAsFixed(2)} km',
              ),
              if (visibleStations.isNotEmpty) ...[
                const SizedBox(height: 6),
                SizedBox(
                  height: 120,
                  child: ListView.separated(
                    key: const ValueKey('nearby-fuel-stations-list'),
                    primary: false,
                    itemCount: visibleStations.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final station = visibleStations[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Text(
                          '${station.name ?? station.brand ?? station.operatorName ?? 'Unnamed station'} '
                          '(${station.distanceKm.toStringAsFixed(2)} km)',
                        ),
                      );
                    },
                  ),
                ),
              ],
              if (stations.stationCount > 5)
                TextButton(
                  key: const ValueKey('toggle-nearby-fuel-stations-button'),
                  onPressed: () {
                    setState(() {
                      showAllNearbyFuelStations = !showAllNearbyFuelStations;
                    });
                  },
                  child: Text(
                    showAllNearbyFuelStations
                        ? 'Show less'
                        : 'View all stations (${stations.stationCount})',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildSiteFactorIntelligenceStatus() {
    final result = validationResult;
    if (result?.candidate.isValidatedInside != true) {
      return const SizedBox.shrink();
    }
    if (isLoadingSiteFactorIntelligence) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Loading site data...'),
          ],
        ),
      );
    }
    final intelligence = siteFactorIntelligenceResult;
    if (intelligence != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Material(
          key: const ValueKey('site-factor-intelligence-summary'),
          color: const Color(0xFFE7F3EC),
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            dense: true,
            title: const Text(
              'Site Data Suggestions',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'Tap to view available estimates and scores',
              style: TextStyle(fontSize: 12),
            ),
            children: [
              ...buildSiteDataEvidenceLines(intelligence),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Available estimates and suggested scores fill only empty '
                  'assessment fields after you use this candidate. You can edit '
                  'every value. Registered Vehicle Count remains manual.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (siteFactorIntelligenceError == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          Text(
            siteFactorIntelligenceError!,
            key: const ValueKey('site-factor-intelligence-error'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFC62828)),
          ),
          TextButton(
            key: const ValueKey('retry-site-factor-intelligence-button'),
            onPressed: () => loadSiteIntelligence(result!),
            child: const Text('Retry site data'),
          ),
        ],
      ),
    );
  }

  List<Widget> buildSiteDataEvidenceLines(
    SiteFactorIntelligenceResult intelligence,
  ) {
    final lines = <String>[];
    final population = intelligence.population;
    if (population.hasUsableSuggestion) {
      lines.add(
        'Estimated population density: '
        '${population.densityPerSqKm!.toStringAsFixed(2)} '
        'people/km²${population.dataYear == null ? '' : ' (${population.dataYear})'}',
      );
    }

    final road = intelligence.roadAccessibility;
    if (road.hasUsableSuggestion) {
      lines.add(
        'Road accessibility — Suggested score: ${road.suggestedScore}/5'
        '${road.majorRoadCount == null ? '' : ' · ${road.majorRoadCount} major-road features'}',
      );
    }

    final commercial = intelligence.commercialActivity;
    if (commercial.hasUsableSuggestion) {
      lines.add(
        'Commercial activity — Suggested score: ${commercial.suggestedScore}/5'
        '${commercial.commercialPoiCount == null ? '' : ' · ${commercial.commercialPoiCount} mapped POIs'}',
      );
    }

    final residential = intelligence.residentialActivity;
    if (residential.hasUsableSuggestion) {
      lines.add(
        'Residential activity — Suggested score: ${residential.suggestedScore}/5'
        '${residential.residentialFeatureCount == null ? '' : ' · ${residential.residentialFeatureCount} mapped features'}',
      );
    }

    final land = intelligence.landAccessibility;
    if (land.hasUsableSuggestion) {
      lines.add(
        'Land accessibility proxy — Suggested score: ${land.suggestedScore}/5'
        '${land.nearestAccessRoadM == null ? '' : ' · ${land.nearestAccessRoadM!.toStringAsFixed(0)} m to nearest access road'}',
      );
    }

    final vehicle = intelligence.vehicleDemand;
    if (vehicle.available && vehicle.isProxy && vehicle.value != null) {
      lines.add(
        'Regional vehicle-registration proxy (reference only): '
        '${vehicle.value} records — not a count within this selected radius',
      );
    }

    if (lines.isEmpty) {
      lines.add('No automated factor suggestions are available for this site.');
    }

    return lines
        .map(
          (line) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(line, style: const TextStyle(fontSize: 13)),
          ),
        )
        .toList(growable: false);
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
                  fuelStations: nearbyFuelStationResult?.stations ?? const [],
                  onPointSelected: selectPoint,
                ),
          ),
          SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.5,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
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
                    DecoratedBox(
                      key: const ValueKey('site-validation-summary'),
                      decoration: BoxDecoration(
                        color:
                            validationResult?.candidate.isValidatedInside ==
                                true
                            ? const Color(0xFFE7F3EC)
                            : const Color(0xFFFFEBEE),
                        borderRadius: const BorderRadius.all(
                          Radius.circular(12),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          validationStatusText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: validationStatusColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    if (validationError != null)
                      Text(
                        validationError!,
                        key: const ValueKey('validation-error-message'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFC62828)),
                      ),
                    buildNearbyFuelStationStatus(),
                    buildSiteFactorIntelligenceStatus(),
                    const Text(
                      'The radius circle is analysis context, not proof of '
                      'territory eligibility.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    if (widget.allowCandidateUpdate) ...[
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
                              items: AssessmentSiteCandidate
                                  .supportedAnalysisRadiiKm
                                  .map(
                                    (radius) => DropdownMenuItem<double>(
                                      value: radius,
                                      child: Text(
                                        '${radius.toStringAsFixed(0)} km',
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: isValidating
                                  ? null
                                  : (radius) {
                                      if (radius != null) {
                                        changeRadius(radius);
                                      }
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
                        child: Text(
                          isValidating ? 'Validating...' : 'Validate Site',
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              widget.allowCandidateUpdate ? 'Cancel' : 'Close',
                            ),
                          ),
                        ),
                        if (widget.allowCandidateUpdate) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              key: const ValueKey('use-candidate-button'),
                              onPressed:
                                  !isValidating &&
                                      validationResult
                                              ?.candidate
                                              .isValidatedInside ==
                                          true
                                  ? () => Navigator.pop(
                                      context,
                                      EastMalaysiaMapSelection(
                                        validationResult: validationResult!,
                                        nearbyFuelStations:
                                            nearbyFuelStationResult,
                                        siteFactorIntelligence:
                                            siteFactorIntelligenceResult,
                                      ),
                                    )
                                  : null,
                              child: const Text('Use This Candidate'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductionEastMalaysiaMap extends StatelessWidget {
  final AssessmentSiteCandidate? candidate;
  final List<NearbyFuelStation> fuelStations;
  final ValueChanged<GeoPoint> onPointSelected;

  const _ProductionEastMalaysiaMap({
    required this.candidate,
    required this.fuelStations,
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
        EastMalaysiaMapScreen.buildFuelStationMarkers(fuelStations),
        EastMalaysiaMapScreen.buildBoundaryAttribution(),
        EastMalaysiaMapScreen.buildOsmAttribution(),
      ],
    );
  }
}
