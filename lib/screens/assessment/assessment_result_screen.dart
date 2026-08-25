import 'package:flutter/material.dart';

import '../../services/station_assessment_service.dart';

class AssessmentResultScreen extends StatelessWidget {
  final String locationName;
  final AssessmentResult result;

  const AssessmentResultScreen({
    super.key,
    required this.locationName,
    required this.result,
  });

  Color get categoryColor {
    switch (result.category) {
      case 'Good':
        return Colors.green;
      case 'Moderate':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  IconData get categoryIcon {
    switch (result.category) {
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
            locationName,
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
                  result.finalScore.toStringAsFixed(1),
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
                  result.category,
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
            content: result.recommendation,
            color: color,
          ),
          resultCard(
            icon: Icons.psychology,
            title: 'AI Explanation',
            content: result.explanation,
            color: const Color(0xFF168C4B),
          ),
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
}
