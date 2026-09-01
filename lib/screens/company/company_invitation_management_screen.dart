import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/company_invitation_code.dart';
import '../../services/company_invitation_repository.dart';

class CompanyInvitationManagementScreen extends StatefulWidget {
  final CompanyInvitationRepository? repository;

  const CompanyInvitationManagementScreen({super.key, this.repository});

  @override
  State<CompanyInvitationManagementScreen> createState() =>
      _CompanyInvitationManagementScreenState();
}

class _CompanyInvitationManagementScreenState
    extends State<CompanyInvitationManagementScreen> {
  late final CompanyInvitationRepository repository;
  List<CompanyInvitationCode> invitations = const [];
  bool isLoading = true;
  String? loadError;
  final Set<String> revokingIds = <String>{};

  @override
  void initState() {
    super.initState();
    repository =
        widget.repository ??
        CompanyInvitationRepository(Supabase.instance.client);
    loadInvitations();
  }

  Future<void> loadInvitations() async {
    setState(() {
      isLoading = true;
      loadError = null;
    });
    try {
      final loaded = await repository.listInvitations();
      if (!mounted) return;
      setState(() {
        invitations = loaded;
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        loadError = 'Unable to load company invitations.';
      });
    }
  }

  Future<void> showGenerateInvitation() async {
    final generated = await showDialog<GeneratedCompanyInvitationCode>(
      context: context,
      builder: (context) => _GenerateInvitationDialog(repository: repository),
    );
    if (!mounted || generated == null) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _OneTimeCodeDialog(generated: generated),
    );
    if (mounted) await loadInvitations();
  }

  Future<void> confirmRevoke(CompanyInvitationCode invitation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke invitation?'),
        content: const Text(
          'Unclaimed registrations can no longer use this code. People who have already joined are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || revokingIds.contains(invitation.id)) {
      return;
    }

    setState(() => revokingIds.add(invitation.id));
    try {
      await repository.revokeInvitation(invitation.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invitation revoked.')));
      await loadInvitations();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to revoke the invitation. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => revokingIds.remove(invitation.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Company Invitations')),
    floatingActionButton: FloatingActionButton.extended(
      key: const ValueKey('generate-company-invitation'),
      onPressed: isLoading ? null : showGenerateInvitation,
      icon: const Icon(Icons.add),
      label: const Text('Generate Code'),
    ),
    body: SafeArea(child: buildBody()),
  );

  Widget buildBody() {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44),
              const SizedBox(height: 12),
              Text(loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: loadInvitations,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: loadInvitations,
      child: invitations.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: const [
                SizedBox(height: 100),
                Icon(Icons.key_outlined, size: 52),
                SizedBox(height: 14),
                Text(
                  'No invitation codes yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Generate a secure company invitation code to share with an employee.',
                  textAlign: TextAlign.center,
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: invitations.length,
              itemBuilder: (context, index) {
                final invitation = invitations[index];
                return _InvitationCard(
                  invitation: invitation,
                  isRevoking: revokingIds.contains(invitation.id),
                  onRevoke: invitation.canBeRevoked
                      ? () => confirmRevoke(invitation)
                      : null,
                );
              },
            ),
    );
  }
}

class _GenerateInvitationDialog extends StatefulWidget {
  final CompanyInvitationRepository repository;

  const _GenerateInvitationDialog({required this.repository});

  @override
  State<_GenerateInvitationDialog> createState() =>
      _GenerateInvitationDialogState();
}

class _GenerateInvitationDialogState extends State<_GenerateInvitationDialog> {
  static const expiryOptions = <int>[1, 7, 14, 30];
  int expiryDays = 7;
  final maximumUsesController = TextEditingController(text: '1');
  bool isSubmitting = false;
  String? error;

  @override
  void dispose() {
    maximumUsesController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (isSubmitting) return;
    final maximumUses = int.tryParse(maximumUsesController.text.trim());
    if (maximumUses == null || maximumUses < 1 || maximumUses > 20) {
      setState(
        () => error = 'Maximum uses must be a whole number from 1 to 20.',
      );
      return;
    }
    setState(() {
      isSubmitting = true;
      error = null;
    });
    try {
      final generated = await widget.repository.createInvitation(
        CompanyInvitationCreateRequest(
          expiryDays: expiryDays,
          maximumUses: maximumUses,
        ),
      );
      if (mounted) Navigator.pop(context, generated);
    } catch (_) {
      if (mounted) {
        setState(() {
          isSubmitting = false;
          error = 'Unable to generate an invitation code. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Generate Invitation Code'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Role: Company User'),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: expiryDays,
            decoration: const InputDecoration(labelText: 'Expires after'),
            items: expiryOptions
                .map(
                  (days) => DropdownMenuItem(
                    value: days,
                    child: Text('$days day${days == 1 ? '' : 's'}'),
                  ),
                )
                .toList(growable: false),
            onChanged: isSubmitting
                ? null
                : (value) => setState(() => expiryDays = value ?? expiryDays),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: maximumUsesController,
            enabled: !isSubmitting,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Maximum uses',
              helperText: 'Choose a whole number from 1 to 20.',
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: isSubmitting ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('generate-invitation-code-button'),
        onPressed: isSubmitting ? null : submit,
        child: isSubmitting
            ? const SizedBox(
                key: ValueKey('generate-invitation-code-loading'),
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Generate'),
      ),
    ],
  );
}

class _OneTimeCodeDialog extends StatelessWidget {
  final GeneratedCompanyInvitationCode generated;

  const _OneTimeCodeDialog({required this.generated});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Invitation Code'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(
            generated.rawCode,
            key: const ValueKey('one-time-invitation-code'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Save this code now. For security, it cannot be viewed again.',
          ),
          const SizedBox(height: 10),
          Text('Expires: ${_date(generated.expiresAt)}'),
          Text('Maximum uses: ${generated.maximumUses}'),
        ],
      ),
    ),
    actions: [
      Tooltip(
        message: 'Copy invitation code',
        child: TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: generated.rawCode));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invitation code copied.')),
              );
            }
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copy'),
        ),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

class _InvitationCard extends StatelessWidget {
  final CompanyInvitationCode invitation;
  final bool isRevoking;
  final VoidCallback? onRevoke;

  const _InvitationCard({
    required this.invitation,
    required this.isRevoking,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                invitation.codeHint,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              _StatusChip(status: invitation.status),
              Chip(
                label: Text(
                  invitation.role == CompanyInvitationRole.companyUser
                      ? 'Company User'
                      : 'Company Admin (legacy)',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Created: ${_date(invitation.createdAt)}'),
          Text(
            'Expires: ${invitation.expiresAt == null ? 'No expiry' : _date(invitation.expiresAt!)}',
          ),
          Text(
            'Usage: ${invitation.usedCount} / ${invitation.maximumUses ?? 'Unlimited'}',
          ),
          if (invitation.revokedAt != null)
            Text('Revoked: ${_date(invitation.revokedAt!)}'),
          if (onRevoke != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Tooltip(
                message: 'Revoke invitation code',
                child: TextButton.icon(
                  onPressed: isRevoking ? null : onRevoke,
                  icon: isRevoking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.block_outlined),
                  label: const Text('Revoke'),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  final CompanyInvitationStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      CompanyInvitationStatus.active => ('Active', Colors.green),
      CompanyInvitationStatus.expired => ('Expired', Colors.orange),
      CompanyInvitationStatus.usedUp => ('Used up', Colors.blueGrey),
      CompanyInvitationStatus.revoked => ('Revoked', Colors.red),
    };
    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.12),
    );
  }
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
