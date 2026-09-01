import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/company_invitation_code.dart';

typedef CompanyInvitationRpcCaller =
    Future<dynamic> Function(String functionName, Map<String, dynamic> params);
typedef CompanyInvitationSessionProvider = bool Function();

class CompanyInvitationUnavailableException implements Exception {
  const CompanyInvitationUnavailableException();

  @override
  String toString() => 'Company invitations are currently unavailable.';
}

abstract class CompanyInvitationRepository {
  static const createRpcName = 'create_company_invitation_code';
  static const listRpcName = 'list_company_invitation_codes';
  static const revokeRpcName = 'revoke_company_invitation_code';

  factory CompanyInvitationRepository(
    SupabaseClient client, {
    CompanyInvitationRpcCaller? rpcCaller,
    CompanyInvitationSessionProvider? sessionProvider,
  }) => _CompanyInvitationRepository(client, rpcCaller, sessionProvider);

  Future<List<CompanyInvitationCode>> listInvitations();
  Future<GeneratedCompanyInvitationCode> createInvitation(
    CompanyInvitationCreateRequest request,
  );
  Future<void> revokeInvitation(String invitationId);
}

class _CompanyInvitationRepository implements CompanyInvitationRepository {
  final SupabaseClient _client;
  final CompanyInvitationRpcCaller? _rpcCaller;
  final CompanyInvitationSessionProvider? _sessionProvider;

  const _CompanyInvitationRepository(
    this._client,
    this._rpcCaller,
    this._sessionProvider,
  );

  @override
  Future<List<CompanyInvitationCode>> listInvitations() async {
    _requireSession();
    try {
      final response = await _rpc(CompanyInvitationRepository.listRpcName, {});
      if (response is! List) {
        throw const FormatException('Invitation list is invalid.');
      }
      return List.unmodifiable(
        response.map(CompanyInvitationCode.fromRpc).toList(growable: false),
      );
    } catch (_) {
      throw const CompanyInvitationUnavailableException();
    }
  }

  @override
  Future<GeneratedCompanyInvitationCode> createInvitation(
    CompanyInvitationCreateRequest request,
  ) async {
    _requireSession();
    try {
      final response = await _rpc(CompanyInvitationRepository.createRpcName, {
        'p_expiry_days': request.expiryDays,
        'p_max_uses': request.maximumUses,
      });
      if (response is! List || response.length != 1) {
        throw const FormatException('Invitation creation response is invalid.');
      }
      return GeneratedCompanyInvitationCode.fromRpc(response.single);
    } catch (_) {
      throw const CompanyInvitationUnavailableException();
    }
  }

  @override
  Future<void> revokeInvitation(String invitationId) async {
    _requireSession();
    if (!_isUuid(invitationId)) {
      throw ArgumentError.value(
        invitationId,
        'invitationId',
        'Must be a UUID.',
      );
    }
    try {
      final response = await _rpc(CompanyInvitationRepository.revokeRpcName, {
        'p_invitation_id': invitationId,
      });
      if (response != true) {
        throw const FormatException('Invitation revoke response is invalid.');
      }
    } catch (_) {
      throw const CompanyInvitationUnavailableException();
    }
  }

  Future<dynamic> _rpc(String functionName, Map<String, dynamic> params) =>
      _rpcCaller?.call(functionName, params) ??
      _client.rpc(functionName, params: params);

  void _requireSession() {
    if (!(_sessionProvider?.call() ?? _client.auth.currentSession != null)) {
      throw const CompanyInvitationUnavailableException();
    }
  }
}

bool _isUuid(String value) => RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
).hasMatch(value);
