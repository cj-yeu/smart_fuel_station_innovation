import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuel_station_innovation/models/company_invitation_code.dart';
import 'package:smart_fuel_station_innovation/services/company_invitation_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const invitationId = '123e4567-e89b-12d3-a456-426614174000';

  CompanyInvitationRepository repository({
    required CompanyInvitationRpcCaller caller,
    bool session = true,
  }) => CompanyInvitationRepository(
    SupabaseClient('https://example.invalid', 'test-anon-key'),
    rpcCaller: caller,
    sessionProvider: () => session,
  );

  test('requires a session before every invitation RPC', () async {
    var calls = 0;
    final anonymous = repository(
      session: false,
      caller: (_, _) async {
        calls += 1;
        return [];
      },
    );

    await expectLater(
      anonymous.listInvitations(),
      throwsA(isA<CompanyInvitationUnavailableException>()),
    );
    await expectLater(
      anonymous.createInvitation(
        CompanyInvitationCreateRequest(expiryDays: 7, maximumUses: 1),
      ),
      throwsA(isA<CompanyInvitationUnavailableException>()),
    );
    expect(calls, 0);
  });

  test('uses only fixed RPC names and narrow parameters', () async {
    final calls = <(String, Map<String, dynamic>)>[];
    final repo = repository(
      caller: (name, params) async {
        calls.add((name, params));
        return switch (name) {
          CompanyInvitationRepository.listRpcName => [listing()],
          CompanyInvitationRepository.createRpcName => [generated()],
          CompanyInvitationRepository.revokeRpcName => true,
          _ => throw StateError('Unexpected RPC'),
        };
      },
    );

    await repo.listInvitations();
    await repo.createInvitation(
      CompanyInvitationCreateRequest(expiryDays: 14, maximumUses: 2),
    );
    await repo.revokeInvitation(invitationId);

    expect(calls.map((call) => call.$1), [
      CompanyInvitationRepository.listRpcName,
      CompanyInvitationRepository.createRpcName,
      CompanyInvitationRepository.revokeRpcName,
    ]);
    expect(calls[0].$2, isEmpty);
    expect(calls[1].$2, {'p_expiry_days': 14, 'p_max_uses': 2});
    expect(calls[2].$2, {'p_invitation_id': invitationId});
  });

  test(
    'maps malformed and backend responses to one neutral exception',
    () async {
      final malformed = repository(
        caller: (_, _) async => {'unexpected': true},
      );
      final failed = repository(
        caller: (_, _) async => throw StateError('details'),
      );

      await expectLater(
        malformed.listInvitations(),
        throwsA(isA<CompanyInvitationUnavailableException>()),
      );
      await expectLater(
        failed.createInvitation(
          CompanyInvitationCreateRequest(expiryDays: 7, maximumUses: 1),
        ),
        throwsA(isA<CompanyInvitationUnavailableException>()),
      );
    },
  );
}

Map<String, dynamic> listing() => {
  'invitation_id': '123e4567-e89b-12d3-a456-426614174000',
  'code_hint': '••••-CDEF',
  'created_at': '2026-09-01T00:00:00.000Z',
  'expires_at': '2026-09-08T00:00:00.000Z',
  'max_uses': 1,
  'used_count': 0,
  'assigned_role': 'company_user',
  'revoked_at': null,
  'status': 'active',
};

Map<String, dynamic> generated() => {
  'invitation_id': '123e4567-e89b-12d3-a456-426614174000',
  'invitation_code': 'ABCDEF-123456-ABCDEF-123456',
  'expires_at': '2026-09-08T00:00:00.000Z',
  'max_uses': 2,
};
