import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/station_assessment.dart';
import '../../services/station_assessment_repository.dart';
import 'add_assessment_screen.dart';
import 'edit_assessment_screen.dart';

typedef AssessmentLoader = Future<List<StationAssessment>> Function();
typedef CurrentUserIdProvider = String? Function();

class AssessmentListScreen extends StatefulWidget {
  final AssessmentLoader? assessmentLoader;
  final CurrentUserIdProvider? currentUserIdProvider;

  const AssessmentListScreen({
    super.key,
    this.assessmentLoader,
    this.currentUserIdProvider,
  });

  @override
  State<AssessmentListScreen> createState() => _AssessmentListScreenState();
}

class _AssessmentListScreenState extends State<AssessmentListScreen> {
  late final AssessmentLoader assessmentLoader;
  late final CurrentUserIdProvider currentUserIdProvider;

  List<StationAssessment> assessments = [];
  String? currentUserId;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();

    final injectedLoader = widget.assessmentLoader;
    final injectedUserIdProvider = widget.currentUserIdProvider;

    if (injectedLoader != null && injectedUserIdProvider != null) {
      assessmentLoader = injectedLoader;
      currentUserIdProvider = injectedUserIdProvider;
    } else {
      final client = Supabase.instance.client;
      assessmentLoader =
          injectedLoader ??
          StationAssessmentRepository(client).fetchCompanyAssessments;
      currentUserIdProvider =
          injectedUserIdProvider ?? () => client.auth.currentUser?.id;
    }

    loadAssessments();
  }

  Future<void> loadAssessments() async {
    final userId = currentUserIdProvider();

    if (userId == null) {
      setState(() {
        currentUserId = null;
        isLoading = false;
        errorMessage = 'No logged-in user found';
      });
      return;
    }

    try {
      final loadedAssessments = await assessmentLoader();

      if (!mounted) return;

      setState(() {
        assessments = loadedAssessments;
        currentUserId = userId;
        isLoading = false;
        errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
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

    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) return;

    try {
      await Supabase.instance.client
          .from('station_assessments')
          .delete()
          .eq('id', assessment.id)
          .eq('user_id', user.id);

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
    } on PostgrestException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: Colors.red),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to delete assessment'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
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
          children: const [
            SizedBox(height: 140),
            Icon(Icons.analytics_outlined, size: 90, color: Colors.black26),
            SizedBox(height: 20),
            Text(
              'No assessments yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Create an assessment to evaluate a location.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
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
          final isOwnAssessment = assessment.userId == currentUserId;

          return Card(
            key: ValueKey('assessment-card-${assessment.id}'),
            margin: const EdgeInsets.only(bottom: 14),
            child: ListTile(
              key: ValueKey('assessment-row-${assessment.id}'),
              onTap: isOwnAssessment
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
                  '${isOwnAssessment ? 'Your assessment' : 'Company assessment • Read-only'}',
                ),
              ),
              isThreeLine: true,
              trailing: isOwnAssessment
                  ? IconButton(
                      key: ValueKey('delete-assessment-${assessment.id}'),
                      tooltip: 'Delete Assessment',
                      onPressed: () => deleteAssessment(assessment),
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                    )
                  : Icon(
                      Icons.lock_outline,
                      key: ValueKey('read-only-assessment-${assessment.id}'),
                      color: Colors.black45,
                    ),
            ),
          );
        },
      ),
    );
  }
}
