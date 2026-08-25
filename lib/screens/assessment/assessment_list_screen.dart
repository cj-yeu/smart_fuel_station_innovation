import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/station_assessment.dart';
import '../../services/profile_service.dart';
import '../../services/station_assessment_repository.dart';
import 'add_assessment_screen.dart';
import 'edit_assessment_screen.dart';

typedef AssessmentLoader = Future<List<StationAssessment>> Function();
typedef AssessmentDeleter = Future<void> Function(String assessmentId);
typedef AssessmentAccessLoader = Future<AssessmentAccessContext> Function();

class AssessmentAccessContext {
  final String userId;
  final bool isCompanyAdmin;
  final bool hasCompany;

  const AssessmentAccessContext({
    required this.userId,
    required this.isCompanyAdmin,
    required this.hasCompany,
  });
}

class AssessmentListScreen extends StatefulWidget {
  final AssessmentLoader? assessmentLoader;
  final AssessmentDeleter? assessmentDeleter;
  final AssessmentAccessLoader? accessLoader;

  const AssessmentListScreen({
    super.key,
    this.assessmentLoader,
    this.assessmentDeleter,
    this.accessLoader,
  });

  @override
  State<AssessmentListScreen> createState() => _AssessmentListScreenState();
}

class _AssessmentListScreenState extends State<AssessmentListScreen> {
  late final AssessmentLoader assessmentLoader;
  late final AssessmentDeleter assessmentDeleter;
  late final AssessmentAccessLoader accessLoader;

  List<StationAssessment> assessments = [];
  AssessmentAccessContext? accessContext;
  bool isLoading = true;
  String? errorMessage;
  int loadGeneration = 0;

  @override
  void initState() {
    super.initState();

    final injectedLoader = widget.assessmentLoader;
    final injectedDeleter = widget.assessmentDeleter;
    final injectedAccessLoader = widget.accessLoader;

    if (injectedLoader != null &&
        injectedDeleter != null &&
        injectedAccessLoader != null) {
      assessmentLoader = injectedLoader;
      assessmentDeleter = injectedDeleter;
      accessLoader = injectedAccessLoader;
    } else {
      final client = Supabase.instance.client;
      final repository = StationAssessmentRepository(client);
      final profileService = ProfileService(client: client);
      assessmentLoader = injectedLoader ?? repository.fetchCompanyAssessments;
      assessmentDeleter = injectedDeleter ?? repository.deleteAssessment;
      accessLoader =
          injectedAccessLoader ??
          () async {
            final profile = await profileService.fetchCurrentProfile();
            return AssessmentAccessContext(
              userId: profile.userId,
              isCompanyAdmin: profile.isCompanyAdmin,
              hasCompany: profile.companyId?.trim().isNotEmpty == true,
            );
          };
    }

    loadAssessments();
  }

  Future<void> loadAssessments() async {
    final requestGeneration = ++loadGeneration;

    try {
      final loadedAccess = await accessLoader();
      if (loadedAccess.userId.trim().isEmpty || !loadedAccess.hasCompany) {
        throw StateError('Authoritative company access is unavailable.');
      }

      final loadedAssessments = await assessmentLoader();

      if (!mounted || requestGeneration != loadGeneration) return;

      setState(() {
        assessments = loadedAssessments;
        accessContext = loadedAccess;
        isLoading = false;
        errorMessage = null;
      });
    } catch (error) {
      if (!mounted || requestGeneration != loadGeneration) return;

      setState(() {
        accessContext = null;
        isLoading = false;
        errorMessage = 'Unable to load assessments';
      });
    }
  }

  Color categoryColor(String category) {
    switch (category) {
      case 'Good':
        return Colors.green;
      case 'Moderate':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  Future<void> deleteAssessment(StationAssessment assessment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Assessment'),
          content: Text(
            'Delete the assessment for '
            '${assessment.locationName}?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await assessmentDeleter(assessment.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Assessment deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );

      setState(() {
        isLoading = true;
      });

      await loadAssessments();
    } on AssessmentDeleteRejectedException {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Assessment could not be deleted. It may be unavailable or you '
            'may not have permission.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to delete assessment. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Station Assessments'),
        backgroundColor: const Color(0xFF168C4B),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final added = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => const AddAssessmentScreen(),
            ),
          );

          if (added == true) {
            setState(() {
              isLoading = true;
            });

            await loadAssessments();
          }
        },
        backgroundColor: const Color(0xFF168C4B),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Assessment'),
      ),
      body: buildBody(),
    );
  }

  Widget buildBody() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 60, color: Colors.red),
              const SizedBox(height: 16),
              Text(errorMessage!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    isLoading = true;
                    errorMessage = null;
                  });

                  loadAssessments();
                },
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (assessments.isEmpty) {
      return RefreshIndicator(
        onRefresh: loadAssessments,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 140),
            Icon(
              Icons.analytics_outlined,
              size: 90,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 20),
            const Text(
              'No assessments yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Create an assessment to evaluate a location.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: loadAssessments,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: assessments.length,
        itemBuilder: (context, index) {
          final assessment = assessments[index];
          final color = categoryColor(assessment.suitabilityCategory);
          final currentAccess = accessContext!;
          final isOwnAssessment = assessment.userId == currentAccess.userId;
          final canManage = isOwnAssessment || currentAccess.isCompanyAdmin;

          return Card(
            key: ValueKey('assessment-card-${assessment.id}'),
            margin: const EdgeInsets.only(bottom: 14),
            child: ListTile(
              key: ValueKey('assessment-row-${assessment.id}'),
              onTap: canManage
                  ? () async {
                      final updated = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              EditAssessmentScreen(assessment: assessment),
                        ),
                      );

                      if (updated == true) {
                        setState(() {
                          isLoading = true;
                        });

                        await loadAssessments();
                      }
                    }
                  : null,
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(Icons.location_on, color: color),
              ),
              title: Text(
                assessment.locationName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Score: ${assessment.finalScore.toStringAsFixed(1)}/100\n'
                  '${assessment.suitabilityCategory}\n'
                  '${isOwnAssessment
                      ? 'Your assessment'
                      : currentAccess.isCompanyAdmin
                      ? 'Company assessment • Admin access'
                      : 'Company assessment • Read-only'}',
                ),
              ),
              isThreeLine: true,
              trailing: canManage
                  ? IconButton(
                      key: ValueKey('delete-assessment-${assessment.id}'),
                      tooltip: 'Delete Assessment',
                      onPressed: () => deleteAssessment(assessment),
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                    )
                  : Icon(
                      Icons.lock_outline,
                      key: ValueKey('read-only-assessment-${assessment.id}'),
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
            ),
          );
        },
      ),
    );
  }
}
