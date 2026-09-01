import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/station_assessment_ai_explanation.dart';
import '../../services/station_assessment_ai_explanation_repository.dart';
import '../../services/station_assessment_service.dart';

typedef StationAssessmentAiExplanationGenerator =
    Future<StationAssessmentAiExplanation> Function(String assessmentId);

class AssessmentResultScreen extends StatefulWidget {
  final String locationName;
  final AssessmentResult result;
  final String? assessmentId;
  final StationAssessmentAiExplanationGenerator? aiExplanationGenerator;

  const AssessmentResultScreen({
    super.key,
    required this.locationName,
    required this.result,
    this.assessmentId,
    this.aiExplanationGenerator,
  });

  @override
  State<AssessmentResultScreen> createState() => _AssessmentResultScreenState();
}

class _AssessmentResultScreenState extends State<AssessmentResultScreen> {
  bool isLoadingAiExplanation = false;
  String? generatedAiExplanation;
  bool aiExplanationUnavailable = false;

  @override
  void initState() {
    super.initState();
    if (widget.assessmentId != null) {
      generateAiExplanation();
    }
  }

  Future<void> generateAiExplanation() async {
    final assessmentId = widget.assessmentId;
    if (assessmentId == null || isLoadingAiExplanation) return;

    setState(() {
      isLoadingAiExplanation = true;
      aiExplanationUnavailable = false;
    });

    try {
      final generator =
          widget.aiExplanationGenerator ??
          StationAssessmentAiExplanationRepository(
            Supabase.instance.client,
          ).generateExplanation;
      final explanation = await generator(assessmentId);
      if (!mounted) return;
      setState(() {
        generatedAiExplanation = explanation.explanation;
      });
    } on StationAssessmentAiExplanationUnavailableException {
      if (!mounted) return;
      setState(() {
        aiExplanationUnavailable = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        aiExplanationUnavailable = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoadingAiExplanation = false;
        });
      }
    }
  }

  Color get categoryColor {
    switch (widget.result.category) {
      case 'Good':
        return Colors.green;
      case 'Moderate':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  IconData get categoryIcon {
    switch (widget.result.category) {
      case 'Good':
        return Icons.check_circle;
      case 'Moderate':
        return Icons.warning_amber_rounded;
      default:
        return Icons.cancel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = categoryColor;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Assessment Result'),
        backgroundColor: const Color(0xFF168C4B),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            widget.locationName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                Icon(categoryIcon, size: 64, color: color),
                const SizedBox(height: 14),
                Text(
                  widget.result.finalScore.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  'out of 100',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.result.category,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          calculationCard(context),
          const SizedBox(height: 16),
          resultCard(
            icon: Icons.recommend,
            title: 'Recommendation',
            content: widget.result.recommendation,
            color: color,
          ),
          aiExplanationCard(),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: const Color(0xFF168C4B),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.history),
            label: const Text(
              'Return to Assessment History',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget calculationCard(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.calculate_outlined),
        title: const Text(
          'How the suitability score is calculated',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Tap to see the 0–100 scoring weights.'),
        trailing: const Icon(Icons.info_outline),
        onTap: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Suitability score'),
            content: const SingleChildScrollView(
              child: Text(
                'Each factor is converted to a 0–100 score, then weighted:\n\n'
                '• Population density: 15% (10,000 people/km² = 100)\n'
                '• Traffic level: 20% (manual rating 1–5)\n'
                '• Registered vehicle count: 15% (manual local estimate; 100,000 = 100)\n'
                '• Competition: 15% (nearby-station count and nearest competitor distance combined)\n'
                '• Road accessibility: 15%\n'
                '• Commercial activity: 10%\n'
                '• Residential activity: 5%\n'
                '• Land-accessibility proxy: 5%\n\n'
                'Ratings 1–5 are multiplied by 20. A score of 70+ is Good, 45–69.9 is Moderate, and below 45 is Poor.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget resultCard({
    required IconData icon,
    required String title,
    required String content,
    required Color color,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(content, style: const TextStyle(height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget aiExplanationCard() {
    final textColor = const Color(0xFF168C4B);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.psychology, color: textColor, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AI Explanation',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (isLoadingAiExplanation)
                    const Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Expanded(child: Text('Generating AI explanation...')),
                      ],
                    )
                  else ...[
                    Text(
                      generatedAiExplanation ?? widget.result.explanation,
                      style: const TextStyle(height: 1.4),
                    ),
                    if (aiExplanationUnavailable) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'AI explanation is currently unavailable. The deterministic assessment result above remains valid.',
                      ),
                      if (widget.assessmentId != null)
                        TextButton.icon(
                          key: const ValueKey('retry-ai-explanation-button'),
                          onPressed: generateAiExplanation,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry AI Explanation'),
                        ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
