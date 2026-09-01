import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuel_station_innovation/models/company_invitation_code.dart';

void main() {
  const invitationId = '123e4567-e89b-12d3-a456-426614174000';

  Map<String, dynamic> listing({
    String status = 'active',
    Object? maximumUses = 3,
    Object? usedCount = 1,
  }) => {
    'invitation_id': invitationId,
    'code_hint': '••••-CDEF',
    'created_at': '2026-09-01T00:00:00.000Z',
    'expires_at': '2026-09-08T00:00:00.000Z',
    'max_uses': maximumUses,
    'used_count': usedCount,
    'assigned_role': 'company_user',
    'revoked_at': null,
    'status': status,
  };

  test('strictly parses safe invitation listing metadata', () {
    final invitation = CompanyInvitationCode.fromRpc(listing());

    expect(invitation.id, invitationId);
    expect(invitation.codeHint, '••••-CDEF');
    expect(invitation.maximumUses, 3);
    expect(invitation.usedCount, 1);
    expect(invitation.role, CompanyInvitationRole.companyUser);
    expect(invitation.status, CompanyInvitationStatus.active);
    expect(invitation.canBeRevoked, isTrue);
  });

  test('maps all fixed statuses and rejects impossible usage values', () {
    expect(
      CompanyInvitationCode.fromRpc(listing(status: 'expired')).status,
      CompanyInvitationStatus.expired,
    );
    expect(
      CompanyInvitationCode.fromRpc(listing(status: 'used_up')).status,
      CompanyInvitationStatus.usedUp,
    );
    expect(
      CompanyInvitationCode.fromRpc(listing(status: 'revoked')).status,
      CompanyInvitationStatus.revoked,
    );
    expect(
      () =>
          CompanyInvitationCode.fromRpc(listing(maximumUses: 1, usedCount: 2)),
      throwsFormatException,
    );
    expect(
      () => CompanyInvitationCode.fromRpc(listing(usedCount: double.nan)),
      throwsFormatException,
    );
    expect(
      () => CompanyInvitationCode.fromRpc(listing(usedCount: double.infinity)),
      throwsFormatException,
    );
    expect(
      CompanyInvitationCode.fromRpc(listing(maximumUses: 100)).maximumUses,
      100,
    );
  });

  test('accepts a raw code only in the exact immediate-create response', () {
    final generated = GeneratedCompanyInvitationCode.fromRpc({
      'invitation_id': invitationId,
      'invitation_code': 'ABCDEF-123456-ABCDEF-123456',
      'expires_at': '2026-09-08T00:00:00.000Z',
      'max_uses': 1,
    });

    expect(generated.rawCode, 'ABCDEF-123456-ABCDEF-123456');
    expect(
      () => GeneratedCompanyInvitationCode.fromRpc({
        'invitation_id': invitationId,
        'invitation_code': 'not-a-secure-code',
        'expires_at': '2026-09-08T00:00:00.000Z',
        'max_uses': 1,
      }),
      throwsFormatException,
    );
  });

  test('rejects malformed maps and invalid create request bounds', () {
    expect(
      () => CompanyInvitationCode.fromRpc({
        ...listing(),
        'code_hash': 'must-not-be-present',
      }),
      throwsFormatException,
    );
    expect(
      () => CompanyInvitationCreateRequest(expiryDays: 0, maximumUses: 1),
      throwsArgumentError,
    );
    expect(
      () => CompanyInvitationCreateRequest(expiryDays: 7, maximumUses: 21),
      throwsArgumentError,
    );
  });
}
