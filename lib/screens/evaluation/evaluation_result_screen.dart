import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../services/business_evaluation_service.dart';

class EvaluationResultScreen extends StatelessWidget {
  final String stationName;
  final BusinessEvaluationResult result;

  const EvaluationResultScreen({
    super.key,
    required this.stationName,
    required this.result,
  });

  Color get categoryColor {
    switch (result.category) {
      case 'Profitable':
        return Colors.green;
      case 'Moderate Risk':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = categoryColor;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text('Business Evaluation'),
        backgroundColor: const Color(0xFF168C4B),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            stationName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          scoreCard(color),
          const SizedBox(height: 18),
          metricsGrid(),
          const SizedBox(height: 18),
          financialChart(),
          const SizedBox(height: 18),
          costChart(),
          const SizedBox(height: 18),
          informationCard(
            icon: Icons.recommend,
            title: 'Recommendation',
            content: result.recommendation,
            color: color,
          ),
          informationCard(
            icon: Icons.psychology,
            title: 'AI Explanation',
            content: result.explanation,
            color: const Color(0xFF168C4B),
          ),
          const SizedBox(height: 6),
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
              'Return to Evaluation History',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget scoreCard(Color color) {
    return Container(
      padding: const EdgeInsets.all(22),
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
            Icons.analytics,
            size: 54,
            color: color,
          ),
          const SizedBox(height: 10),
          Text(
            result.profitabilityScore.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const Text(
            'Profitability Score / 100',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 10),
          Text(
            result.category,
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget metricsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.45,
      children: [
        metricCard(
          'Monthly Revenue',
          'RM${result.monthlyRevenue.toStringAsFixed(2)}',
          Icons.payments_outlined,
        ),
        metricCard(
          'Monthly Profit',
          'RM${result.monthlyProfit.toStringAsFixed(2)}',
          Icons.trending_up,
        ),
        metricCard(
          'Profit Margin',
          '${result.profitMargin.toStringAsFixed(1)}%',
          Icons.percent,
        ),
        metricCard(
          'Annual ROI',
          '${result.roi.toStringAsFixed(1)}%',
          Icons.assessment_outlined,
        ),
        metricCard(
          'Sales Volume',
          '${result.monthlySalesVolume.toStringAsFixed(0)} L',
          Icons.local_gas_station_outlined,
        ),
        metricCard(
          'Break-even',
          result.breakEvenMonths == null
              ? 'Not achievable'
              : '${result.breakEvenMonths!.toStringAsFixed(1)} months',
          Icons.schedule,
        ),
      ],
    );
  }

  Widget metricCard(
      String title,
      String value,
      IconData icon,
      ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: const Color(0xFF168C4B),
            ),
            const SizedBox(height: 7),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget financialChart() {
    final maximum = math.max(
      result.monthlyRevenue,
      result.monthlyOperatingCost,
    );

    final chartMaximum = maximum <= 0 ? 100.0 : maximum * 1.2;
    final minimum = math.min(0.0, result.monthlyProfit);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Monthly Financial Comparison',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 240,
              child: BarChart(
                BarChartData(
                  minY: minimum,
                  maxY: chartMaximum,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 38,
                        getTitlesWidget: (value, meta) {
                          final labels = [
                            'Revenue',
                            'Cost',
                            'Profit',
                          ];

                          final index = value.toInt();

                          if (index < 0 || index >= labels.length) {
                            return const SizedBox.shrink();
                          }

                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              labels[index],
                              style: const TextStyle(fontSize: 11),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    chartBar(
                      0,
                      result.monthlyRevenue,
                      Colors.blue,
                    ),
                    chartBar(
                      1,
                      result.monthlyOperatingCost,
                      Colors.orange,
                    ),
                    chartBar(
                      2,
                      result.monthlyProfit,
                      result.monthlyProfit >= 0
                          ? Colors.green
                          : Colors.red,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  BarChartGroupData chartBar(
      int index,
      double value,
      Color color,
      ) {
    return BarChartGroupData(
      x: index,
      barRods: [
        BarChartRodData(
          toY: value,
          width: 30,
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
      ],
    );
  }

  Widget costChart() {
    final fuelCost = result.monthlyFuelCost;
    final fixedCost = math.max(
      0.0,
      result.monthlyOperatingCost - fuelCost,
    );

    if (result.monthlyOperatingCost <= 0) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Monthly Cost Composition',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 210,
              child: PieChart(
                PieChartData(
                  centerSpaceRadius: 45,
                  sectionsSpace: 3,
                  sections: [
                    PieChartSectionData(
                      value: fuelCost,
                      title: 'Fuel',
                      color: Colors.blue,
                      radius: 65,
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    PieChartSectionData(
                      value: fixedCost,
                      title: 'Operating',
                      color: Colors.orange,
                      radius: 65,
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget informationCard({
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
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
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