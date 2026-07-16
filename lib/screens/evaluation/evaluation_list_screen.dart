import 'edit_evaluation_screen.dart';
import 'add_evaluation_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/business_evaluation.dart';

class EvaluationListScreen extends StatefulWidget {
  const EvaluationListScreen({super.key});

  @override
  State<EvaluationListScreen> createState() =>
      _EvaluationListScreenState();
}

class _EvaluationListScreenState
    extends State<EvaluationListScreen> {
  List<BusinessEvaluation> evaluations = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    loadEvaluations();
  }

  Future<void> loadEvaluations() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      setState(() {
        isLoading = false;
        errorMessage = 'No logged-in user found';
      });
      return;
    }

    try {
      final data = await Supabase.instance.client
          .from('business_evaluations')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final loadedEvaluations = data
          .map<BusinessEvaluation>(
            (item) => BusinessEvaluation.fromMap(item),
      )
          .toList();

      if (!mounted) return;

      setState(() {
        evaluations = loadedEvaluations;
        isLoading = false;
        errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        errorMessage = 'Unable to load evaluations';
      });
    }
  }

  Color categoryColor(String category) {
    switch (category) {
      case 'Profitable':
        return Colors.green;
      case 'Moderate Risk':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  Future<void> deleteEvaluation(
      BusinessEvaluation evaluation,
      ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Evaluation'),
          content: Text(
            'Delete the evaluation for '
                '${evaluation.stationName}?',
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
          .from('business_evaluations')
          .delete()
          .eq('id', evaluation.id)
          .eq('user_id', user.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Evaluation deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );

      setState(() {
        isLoading = true;
      });

      await loadEvaluations();
    } on PostgrestException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: Colors.red,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to delete evaluation'),
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
        title: const Text('Business Evaluations'),
        backgroundColor: const Color(0xFF168C4B),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final added = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => const AddEvaluationScreen(),
            ),
          );

          if (added == true) {
            setState(() {
              isLoading = true;
            });

            await loadEvaluations();
          }
        },
        backgroundColor: const Color(0xFF168C4B),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Evaluation'),
      ),
      body: buildBody(),
    );
  }

  Widget buildBody() {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 60,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(errorMessage!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    isLoading = true;
                    errorMessage = null;
                  });

                  loadEvaluations();
                },
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (evaluations.isEmpty) {
      return RefreshIndicator(
        onRefresh: loadEvaluations,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 140),
            Icon(
              Icons.bar_chart_outlined,
              size: 90,
              color: Colors.black26,
            ),
            SizedBox(height: 20),
            Text(
              'No evaluations yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Create an evaluation to estimate profitability.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: loadEvaluations,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: evaluations.length,
        itemBuilder: (context, index) {
          final evaluation = evaluations[index];
          final color = categoryColor(
            evaluation.profitabilityCategory,
          );

          return Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: ListTile(
              onTap: () async {
                final updated = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EditEvaluationScreen(
                      evaluation: evaluation,
                    ),
                  ),
                );

                if (updated == true) {
                  setState(() {
                    isLoading = true;
                  });

                  await loadEvaluations();
                }
              },
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(
                  Icons.local_gas_station,
                  color: color,
                ),
              ),
              title: Text(
                evaluation.stationName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Score: '
                      '${evaluation.profitabilityScore.toStringAsFixed(1)}/100\n'
                      'Monthly Profit: '
                      'RM${evaluation.monthlyProfit.toStringAsFixed(2)}\n'
                      '${evaluation.profitabilityCategory}',
                ),
              ),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: 'Delete Evaluation',
                onPressed: () => deleteEvaluation(evaluation),
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}