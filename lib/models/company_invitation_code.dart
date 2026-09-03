enum CompanyInvitationStatus { active, expired, usedUp, revoked }

enum CompanyInvitationRole { companyUser, companyAdmin }

class CompanyInvitationCode {
  final String id;
  final String codeHint;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final int? maximumUses;
  final int usedCount;
  final CompanyInvitationRole role;
  final DateTime? revokedAt;
  final CompanyInvitationStatus status;

  const CompanyInvitationCode({
    required this.id,
    required this.codeHint,
    required this.createdAt,
    required this.expiresAt,
    required this.maximumUses,
    required this.usedCount,
    required this.role,
    required this.revokedAt,
    required this.status,
  });

  bool get canBeRevoked => status == CompanyInvitationStatus.active;

  factory CompanyInvitationCode.fromRpc(Object? value) {
    final map = _exactMap(value, const [
      'invitation_id',
      'code_hint',
      'created_at',
      'expires_at',
      'max_uses',
      'used_count',
      'assigned_role',
      'revoked_at',
      'status',
    ]);
    final maximumUses = _nullableBoundedInteger(map['max_uses'], 1, 1 << 31);
    final usedCount = _boundedInteger(map['used_count'], 0, 1 << 31);
    if (maximumUses != null && usedCount > maximumUses) {
      throw const FormatException('Invitation usage is invalid.');
    }

    return CompanyInvitationCode(
      id: _uuid(map['invitation_id']),
      codeHint: _boundedString(map['code_hint'], 1, 32),
      createdAt: _timestamp(map['created_at']),
      expiresAt: _nullableTimestamp(map['expires_at']),
      maximumUses: maximumUses,
      usedCount: usedCount,
      role: _role(map['assigned_role']),
      revokedAt: _nullableTimestamp(map['revoked_at']),
      status: _status(map['status']),
    );
  }
}

class GeneratedCompanyInvitationCode {
  final String invitationId;
  final String rawCode;
  final DateTime expiresAt;
  final int maximumUses;

  const GeneratedCompanyInvitationCode({
    required this.invitationId,
    required this.rawCode,
    required this.expiresAt,
    required this.maximumUses,
  });

  factory GeneratedCompanyInvitationCode.fromRpc(Object? value) {
    final map = _exactMap(value, const [
      'invitation_id',
      'invitation_code',
      'expires_at',
      'max_uses',
    ]);
    final rawCode = _invitationCode(map['invitation_code']);
    return GeneratedCompanyInvitationCode(
      invitationId: _uuid(map['invitation_id']),
      rawCode: rawCode,
      expiresAt: _timestamp(map['expires_at']),
      maximumUses: _boundedInteger(map['max_uses'], 1, 20),
    );
  }
}

class CompanyInvitationCreateRequest {
  final int expiryDays;
  final int maximumUses;

  CompanyInvitationCreateRequest({
    required this.expiryDays,
    required this.maximumUses,
  }) {
    if (expiryDays < 1 || expiryDays > 30) {
      throw ArgumentError.value(expiryDays, 'expiryDays', 'Must be 1 to 30.');
    }
    if (maximumUses < 1 || maximumUses > 20) {
      throw ArgumentError.value(maximumUses, 'maximumUses', 'Must be 1 to 20.');
    }
  }
}

Map<String, dynamic> _exactMap(Object? value, List<String> keys) {
  if (value is! Map) {
    throw const FormatException('Invitation response is invalid.');
  }
  final map = Map<String, dynamic>.from(value);
  final actual = map.keys.toSet();
  if (actual.length != keys.length || !actual.containsAll(keys)) {
    throw const FormatException('Invitation response is invalid.');
  }
  return map;
}

String _uuid(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false,
      ).hasMatch(value)) {
    throw const FormatException('Invitation identifier is invalid.');
  }
  return value.toLowerCase();
}

String _boundedString(Object? value, int minimum, int maximum) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.length < minimum ||
      value.length > maximum) {
    throw const FormatException('Invitation response is invalid.');
  }
  return value;
}

int _boundedInteger(Object? value, int minimum, int maximum) {
  if (value is! num ||
      !value.isFinite ||
      (value is double && value != value.truncateToDouble()) ||
      value < minimum ||
      value > maximum) {
    throw const FormatException('Invitation usage is invalid.');
  }
  return value.toInt();
}

String _invitationCode(Object? value) {
  final code = _boundedString(value, 27, 27);
  if (!RegExp(r'^[A-F0-9]{6}(?:-[A-F0-9]{6}){3}$').hasMatch(code)) {
    throw const FormatException('Invitation code is invalid.');
  }
  return code;
}

int? _nullableBoundedInteger(Object? value, int minimum, int maximum) =>
    value == null ? null : _boundedInteger(value, minimum, maximum);

DateTime _timestamp(Object? value) {
  if (value is! String || value.length > 64) {
    throw const FormatException('Invitation timestamp is invalid.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const FormatException('Invitation timestamp is invalid.');
  }
  return parsed.toUtc();
}

DateTime? _nullableTimestamp(Object? value) =>
    value == null ? null : _timestamp(value);

CompanyInvitationRole _role(Object? value) => switch (value) {
  'company_user' => CompanyInvitationRole.companyUser,
  'company_admin' => CompanyInvitationRole.companyAdmin,
  _ => throw const FormatException('Invitation role is invalid.'),
};

CompanyInvitationStatus _status(Object? value) => switch (value) {
  'active' => CompanyInvitationStatus.active,
  'expired' => CompanyInvitationStatus.expired,
  'used_up' => CompanyInvitationStatus.usedUp,
  'revoked' => CompanyInvitationStatus.revoked,
  _ => throw const FormatException('Invitation status is invalid.'),
};
