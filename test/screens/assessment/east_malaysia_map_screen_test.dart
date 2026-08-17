import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuell_station_innovation/screens/assessment/east_malaysia_map_screen.dart';

void main() {
  testWidgets('renders navigation-only East Malaysia map guidance', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EastMalaysiaMapScreen(
          mapContentBuilder: (context) => const ColoredBox(
            key: ValueKey('injected-map-placeholder'),
            color: Colors.blueGrey,
            child: Center(child: Text('Offline test map placeholder')),
          ),
        ),
      ),
    );

    expect(find.text('East Malaysia Site Map'), findsOneWidget);
    expect(find.text('Sabah • Sarawak • Labuan'), findsOneWidget);
    expect(
      find.text(
        'The map viewport is for navigation only. Territory eligibility will '
        'be determined by authoritative boundary validation.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('injected-map-placeholder')),
      findsOneWidget,
    );
    expect(find.text('Offline test map placeholder'), findsOneWidget);

    // The injected content prevents construction of network tile widgets.
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.byType(TileLayer), findsNothing);
    expect(find.textContaining('inside', findRichText: true), findsNothing);
    expect(
      find.textContaining('geographically valid', findRichText: true),
      findsNothing,
    );
    expect(find.byIcon(Icons.my_location), findsNothing);
    expect(find.byIcon(Icons.gps_fixed), findsNothing);
    expect(find.textContaining('Select site'), findsNothing);
    expect(find.textContaining('Confirm site'), findsNothing);
  });
}
