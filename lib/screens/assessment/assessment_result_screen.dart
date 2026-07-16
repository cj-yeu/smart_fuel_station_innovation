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
      backgroundColor: const Color(0xFFF4F7F6),
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
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: color.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  categoryIcon,
                  size: 64,
                  color: color,
                ),
                const SizedBox(height: 14),
                Text(
                  result.finalScore.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const Text(
                  'out of 100',
                  style: TextStyle(color: Colors.black54),
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
            Icon(
              icon,
              color: color,
              size: 30,
            ),
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
                  Text(
                    content,
                    style: const TextStyle(height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}