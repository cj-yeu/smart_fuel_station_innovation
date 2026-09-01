import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuel_station_innovation/models/company_invitation_code.dart';
import 'package:smart_fuel_station_innovation/screens/company/company_invitation_management_screen.dart';
import 'package:smart_fuel_station_innovation/services/company_invitation_repository.dart';

void main() {
  testWidgets(
    'shows a loading indicator while invitation metadata is pending',
    (tester) async {
      final completer = Completer<List<CompanyInvitationCode>>();
      final repository = _FakeInvitationRepository(
        list: () => completer.future,
      );

      tester.view.physicalSize = const Size(700, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyInvitationManagementScreen(repository: repository),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(const []);
      await tester.pumpAndSettle();
      expect(find.text('No invitation codes yet'), findsOneWidget);
    },
  );

  testWidgets('shows loading, empty, error, and retry states', (tester) async {
    var attempts = 0;
    final repository = _FakeInvitationRepository(
      list: () async {
        attempts += 1;
        if (attempts == 1) {
          throw const CompanyInvitationUnavailableException();
        }
        return const [];
      },
    );

    await _pumpScreen(tester, repository);
    expect(find.text('Unable to load company invitations.'), findsOneWidget);

    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(find.text('No invitation codes yet'), findsOneWidget);
    expect(attempts, 2);
  });

  testWidgets('validates generation input and shows a raw code only once', (
    tester,
  ) async {
    String? copiedCode;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedCode =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final repository = _FakeInvitationRepository(
      list: () async => const [],
      create: (_) async => _generatedCode,
    );
    await _pumpScreen(tester, repository);

    await tester.tap(find.byKey(const ValueKey('generate-company-invitation')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '21');
    await tester.tap(find.text('Generate'));
    await tester.pump();
    expect(
      find.text('Maximum uses must be a whole number from 1 to 20.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextFormField), '2');
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('one-time-invitation-code')),
      findsOneWidget,
    );
    expect(
      find.text('Save this code now. For security, it cannot be viewed again.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copiedCode, _generatedCode.rawCode);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text(_generatedCode.rawCode), findsNothing);
    expect(repository.createCalls, 1);
  });

  testWidgets('keeps generation duplicate-submit protected while pending', (
    tester,
  ) async {
    final createCompleter = Completer<GeneratedCompanyInvitationCode>();
    final repository = _FakeInvitationRepository(
      list: () async => const [],
      create: (_) => createCompleter.future,
    );
    await _pumpScreen(tester, repository);

    await tester.tap(find.byKey(const ValueKey('generate-company-invitation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate'));
    await tester.pump();

    final generateButtonFinder = find.byKey(
      const ValueKey('generate-invitation-code-button'),
    );
    final generateButton = tester.widget<FilledButton>(generateButtonFinder);
    expect(generateButton.onPressed, isNull);
    expect(
      find.byKey(const ValueKey('generate-invitation-code-loading')),
      findsOneWidget,
    );
    expect(find.text('Generate Invitation Code'), findsOneWidget);

    await tester.tap(generateButtonFinder);
    await tester.pump();
    expect(repository.createCalls, 1);

    createCompleter.complete(_generatedCode);
    await tester.pumpAndSettle();
  });

  testWidgets('presents each status and revokes an active invitation', (
    tester,
  ) async {
    final repository = _FakeInvitationRepository(
      list: () async => _invitations,
      revoke: (_) async {},
    );
    await _pumpScreen(tester, repository);

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Expired'), findsOneWidget);
    expect(find.text('Used up'), findsOneWidget);
    expect(find.text('Revoked'), findsOneWidget);
    expect(find.text('Revoke'), findsOneWidget);

    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();
    expect(find.text('Revoke invitation?'), findsOneWidget);
    expect(
      find.text(
        'Unclaimed registrations can no longer use this code. People who have already joined are not affected.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Revoke'));
    await tester.pumpAndSettle();

    expect(repository.revokeIds, [_activeInvitation.id]);
  });

  testWidgets(
    'fits all invitation statuses on a small screen without overflow',
    (tester) async {
      await _pumpScreen(
        tester,
        _FakeInvitationRepository(list: () async => _invitations),
        physicalSize: const Size(360, 480),
      );

      expect(find.text('Active'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpScreen(
  WidgetTester tester,
  CompanyInvitationRepository repository, {
  Size physicalSize = const Size(700, 1000),
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: CompanyInvitationManagementScreen(repository: repository),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeInvitationRepository implements CompanyInvitationRepository {
  final Future<List<CompanyInvitationCode>> Function() _list;
  final Future<GeneratedCompanyInvitationCode> Function(
    CompanyInvitationCreateRequest request,
  )
  _create;
  final Future<void> Function(String invitationId) _revoke;
  int createCalls = 0;
  final List<String> revokeIds = <String>[];

  _FakeInvitationRepository({
    Future<List<CompanyInvitationCode>> Function()? list,
    Future<GeneratedCompanyInvitationCode> Function(
      CompanyInvitationCreateRequest request,
    )?
    create,
    Future<void> Function(String invitationId)? revoke,
  }) : _list = list ?? (() async => const []),
       _create = create ?? ((_) async => _generatedCode),
       _revoke = revoke ?? ((_) async {});

  @override
  Future<GeneratedCompanyInvitationCode> createInvitation(
    CompanyInvitationCreateRequest request,
  ) {
    createCalls += 1;
    return _create(request);
  }

  @override
  Future<List<CompanyInvitationCode>> listInvitations() => _list();

  @override
  Future<void> revokeInvitation(String invitationId) {
    revokeIds.add(invitationId);
    return _revoke(invitationId);
  }
}

final _generatedCode = GeneratedCompanyInvitationCode(
  invitationId: '123e4567-e89b-12d3-a456-426614174000',
  rawCode: 'ABCDEF-123456-ABCDEF-123456',
  expiresAt: DateTime.utc(2026, 9, 8),
  maximumUses: 2,
);

final _activeInvitation = CompanyInvitationCode(
  id: '123e4567-e89b-12d3-a456-426614174000',
  codeHint: '••••-CDEF',
  createdAt: DateTime.utc(2026, 9, 1),
  expiresAt: DateTime.utc(2026, 9, 8),
  maximumUses: 2,
  usedCount: 0,
  role: CompanyInvitationRole.companyUser,
  revokedAt: null,
  status: CompanyInvitationStatus.active,
);

final _invitations = <CompanyInvitationCode>[
  _activeInvitation,
  CompanyInvitationCode(
    id: '123e4567-e89b-12d3-a456-426614174001',
    codeHint: '••••-PIRE',
    createdAt: DateTime.utc(2026, 8, 1),
    expiresAt: DateTime.utc(2026, 8, 2),
    maximumUses: 1,
    usedCount: 0,
    role: CompanyInvitationRole.companyUser,
    revokedAt: null,
    status: CompanyInvitationStatus.expired,
  ),
  CompanyInvitationCode(
    id: '123e4567-e89b-12d3-a456-426614174002',
    codeHint: '••••-USED',
    createdAt: DateTime.utc(2026, 8, 1),
    expiresAt: DateTime.utc(2026, 9, 8),
    maximumUses: 1,
    usedCount: 1,
    role: CompanyInvitationRole.companyUser,
    revokedAt: null,
    status: CompanyInvitationStatus.usedUp,
  ),
  CompanyInvitationCode(
    id: '123e4567-e89b-12d3-a456-426614174003',
    codeHint: '••••-VOKE',
    createdAt: DateTime.utc(2026, 8, 1),
    expiresAt: DateTime.utc(2026, 9, 8),
    maximumUses: 1,
    usedCount: 0,
    role: CompanyInvitationRole.companyUser,
    revokedAt: DateTime.utc(2026, 8, 2),
    status: CompanyInvitationStatus.revoked,
  ),
];
