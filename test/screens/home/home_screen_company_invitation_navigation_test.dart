import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuell_station_innovation/models/fuel_company.dart';
import 'package:smart_fuell_station_innovation/models/user_profile.dart';
import 'package:smart_fuell_station_innovation/screens/home/home_screen.dart';

void main() {
  testWidgets('shows Company Invitations only to company administrators', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(profile: _profile('company_admin'))),
    );

    expect(find.text('Company Invitations'), findsOneWidget);
    expect(
      find.text('Generate and revoke employee invitation codes'),
      findsOneWidget,
    );
  });

  testWidgets('hides Company Invitations from company users', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(profile: _profile('company_user'))),
    );

    expect(find.text('Company Invitations'), findsNothing);
    expect(
      find.text('Generate and revoke employee invitation codes'),
      findsNothing,
    );
  });
}

UserProfile _profile(String role) => UserProfile(
  id: '123e4567-e89b-12d3-a456-426614174000',
  userId: '123e4567-e89b-12d3-a456-426614174001',
  fullName: 'Synthetic User',
  email: 'synthetic@example.invalid',
  phone: null,
  role: role,
  companyId: '123e4567-e89b-12d3-a456-426614174002',
  company: FuelCompany(
    id: '123e4567-e89b-12d3-a456-426614174002',
    companyCode: 'SYNTHETIC',
    companyName: 'Synthetic Company',
    isActive: true,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  ),
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);
