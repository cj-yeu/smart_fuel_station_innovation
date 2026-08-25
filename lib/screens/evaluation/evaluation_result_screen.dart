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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Profitability Evaluation'),
        backgroundColor: const Color(0xFF168C4B),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            stationName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          scoreCard(color),
          const SizedBox(height: 18),
          metricsGrid(),
          const SizedBox(height: 18),
          financialChart(context),
          const SizedBox(height: 18),
          costChart(context),
          const SizedBox(height: 18),
          informationCard(
            icon: Icons.recommend,
            title: 'Recommendation',
            content: result.recommendation,
            color: color,
          ),
          informationCard(
            icon: Icons.psychology,
            title: 'Evaluation Explanation',
            content: result.explanation,
            color: const Color(0xFF168C4B),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Estimates are for decision-support purposes and depend on the assumptions entered.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
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
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Icon(Icons.analytics, size: 54, color: color),
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
              ? 'Not currently profitable'
              : '${result.breakEvenMonths!.toStringAsFixed(1)} months',
          Icons.schedule,
        ),
      ],
    );
  }

  Widget metricCard(String title, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF168C4B)),
            const SizedBox(height: 7),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget financialChart(BuildContext context) {
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
            chartTitle(
              context,
              title: 'Monthly Financial Comparison',
              informationTitle: 'Monthly financial comparison',
              information:
                  'Monthly revenue = monthly sales volume × fuel price.\n\n'
                  'Monthly operating cost = fuel cost + rent + staff salaries + '
                  'utilities + maintenance + other entered costs.\n\n'
                  'Monthly profit = monthly revenue − monthly operating cost. '
                  'These values use the assumptions entered for this evaluation.',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                chartLegendItem(Colors.blue, 'Revenue', result.monthlyRevenue),
                chartLegendItem(
                  Colors.orange,
                  'Cost',
                  result.monthlyOperatingCost,
                ),
                chartLegendItem(
                  result.monthlyProfit >= 0 ? Colors.green : Colors.red,
                  'Profit',
                  result.monthlyProfit,
                ),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 240,
              child: BarChart(
                BarChartData(
                  minY: minimum,
                  maxY: chartMaximum,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: chartMaximum / 4,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.black12,
                      strokeWidth: value == 0 ? 1.2 : 0.7,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 54,
                        interval: chartMaximum / 4,
                        getTitlesWidget: (value, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(
                            formatAxisCurrency(value),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
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
                          final labels = ['Revenue', 'Cost', 'Profit'];

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
                    chartBar(0, result.monthlyRevenue, Colors.blue),
                    chartBar(1, result.monthlyOperatingCost, Colors.orange),
                    chartBar(
                      2,
                      result.monthlyProfit,
                      result.monthlyProfit >= 0 ? Colors.green : Colors.red,
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

  BarChartGroupData chartBar(int index, double value, Color color) {
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

  Widget costChart(BuildContext context) {
    final fuelCost = result.monthlyFuelCost;
    final fixedCost = math.max(0.0, result.monthlyOperatingCost - fuelCost);

    if (result.monthlyOperatingCost <= 0) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            chartTitle(
              context,
              title: 'Monthly Cost Composition',
              informationTitle: 'Monthly cost composition',
              information:
                  'Fuel cost = monthly sales volume × fuel purchase '
                  'cost. Other operating cost combines rent, staff salaries, '
                  'utilities, maintenance and other entered costs. The pie chart '
                  'shows each portion of total monthly operating cost.',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                chartLegendItem(
                  Colors.blue,
                  'Fuel cost',
                  fuelCost,
                  result.monthlyOperatingCost,
                ),
                chartLegendItem(
                  Colors.orange,
                  'Other operating cost',
                  fixedCost,
                  result.monthlyOperatingCost,
                ),
              ],
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
                      title: percentageText(
                        fuelCost,
                        result.monthlyOperatingCost,
                      ),
                      color: Colors.blue,
                      radius: 65,
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    PieChartSectionData(
                      value: fixedCost,
                      title: percentageText(
                        fixedCost,
                        result.monthlyOperatingCost,
                      ),
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

  Widget chartTitle(
    BuildContext context, {
    required String title,
    required String informationTitle,
    required String information,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          tooltip: 'How this is calculated',
          icon: const Icon(Icons.info_outline),
          onPressed: () => showInformationDialog(
            context,
            title: informationTitle,
            message: information,
          ),
        ),
      ],
    );
  }

  Widget chartLegendItem(
    Color color,
    String label,
    double value, [
    double? total,
  ]) {
    final percentage = total == null || total <= 0
        ? ''
        : ' (${(value / total * 100).toStringAsFixed(1)}%)';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          '$label: RM${value.toStringAsFixed(2)}$percentage',
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  String percentageText(double value, double total) =>
      total <= 0 ? '0%' : '${(value / total * 100).toStringAsFixed(0)}%';

  String formatAxisCurrency(double value) {
    if (value.abs() >= 1000) {
      return 'RM${(value / 1000).toStringAsFixed(0)}k';
    }
    return 'RM${value.toStringAsFixed(0)}';
  }

  void showInformationDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
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
