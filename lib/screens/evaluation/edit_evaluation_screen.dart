import '../../models/business_evaluation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/official_fuel_price.dart';
import '../../services/business_evaluation_service.dart';
import '../../services/official_fuel_price_repository.dart';
import 'evaluation_result_screen.dart';

typedef EditOfficialFuelPriceLoader = Future<OfficialFuelPrice> Function();

class EditEvaluationScreen extends StatefulWidget {
  final BusinessEvaluation evaluation;
  final EditOfficialFuelPriceLoader? officialFuelPriceLoader;

  const EditEvaluationScreen({
    super.key,
    required this.evaluation,
    this.officialFuelPriceLoader,
  });

  @override
  State<EditEvaluationScreen> createState() => _EditEvaluationScreenState();
}

class _EditEvaluationScreenState extends State<EditEvaluationScreen> {
  late final TextEditingController stationNameController;
  late final TextEditingController fuelPriceController;
  late final TextEditingController fuelCostController;
  late final TextEditingController dailyCustomersController;
  late final TextEditingController averageLitresController;
  late final TextEditingController rentalController;
  late final TextEditingController salaryController;
  late final TextEditingController utilitiesController;
  late final TextEditingController maintenanceController;
  late final TextEditingController otherCostController;
  late final TextEditingController investmentController;
  late final EditOfficialFuelPriceLoader officialFuelPriceLoader;

  OfficialFuelPrice? officialFuelPrice;
  OfficialFuelProduct selectedFuelProduct = OfficialFuelProduct.ron95;
  bool isLoadingOfficialFuelPrice = true;
  bool officialFuelPriceUnavailable = false;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();

    final evaluation = widget.evaluation;
    officialFuelPriceLoader =
        widget.officialFuelPriceLoader ??
        OfficialFuelPriceRepository().loadLatest;

    stationNameController = TextEditingController(text: evaluation.stationName);

    fuelPriceController = TextEditingController(
      text: evaluation.fuelPrice.toString(),
    );

    fuelCostController = TextEditingController(
      text: evaluation.fuelPurchaseCost.toString(),
    );

    dailyCustomersController = TextEditingController(
      text: evaluation.dailyCustomers.toString(),
    );

    averageLitresController = TextEditingController(
      text: evaluation.averageLitres.toString(),
    );

    rentalController = TextEditingController(
      text: evaluation.monthlyRental.toString(),
    );

    salaryController = TextEditingController(
      text: evaluation.monthlyStaffSalary.toString(),
    );

    utilitiesController = TextEditingController(
      text: evaluation.monthlyUtilities.toString(),
    );

    maintenanceController = TextEditingController(
      text: evaluation.monthlyMaintenance.toString(),
    );

    otherCostController = TextEditingController(
      text: evaluation.monthlyOtherCost.toString(),
    );

    investmentController = TextEditingController(
      text: evaluation.initialInvestment.toString(),
    );
    loadOfficialFuelPrice();
  }

  Future<void> loadOfficialFuelPrice() async {
    setState(() {
      isLoadingOfficialFuelPrice = true;
      officialFuelPriceUnavailable = false;
    });

    try {
      final loadedPrice = await officialFuelPriceLoader();
      if (!mounted) return;
      setState(() {
        officialFuelPrice = loadedPrice;
        isLoadingOfficialFuelPrice = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isLoadingOfficialFuelPrice = false;
        officialFuelPriceUnavailable = true;
      });
    }
  }

  double get _selectedOfficialPrice {
    final price = officialFuelPrice;
    if (price == null) {
      throw StateError('Official fuel price is unavailable.');
    }
    return price.priceFor(selectedFuelProduct);
  }

  void useOfficialPrice() {
    fuelPriceController.text = _selectedOfficialPrice.toStringAsFixed(2);
  }

  Future<void> runEvaluation() async {
    final user = Supabase.instance.client.auth.currentUser;
    final stationName = stationNameController.text.trim();

    final fuelPrice = parseDouble(fuelPriceController);
    final fuelCost = parseDouble(fuelCostController);
    final dailyCustomers = int.tryParse(dailyCustomersController.text.trim());
    final averageLitres = parseDouble(averageLitresController);
    final rental = parseDouble(rentalController);
    final salary = parseDouble(salaryController);
    final utilities = parseDouble(utilitiesController);
    final maintenance = parseDouble(maintenanceController);
    final otherCost = parseDouble(otherCostController);
    final investment = parseDouble(investmentController);

    if (user == null) {
      showMessage('No logged-in user found', isError: true);
      return;
    }

    if (stationName.isEmpty ||
        fuelPrice == null ||
        fuelCost == null ||
        dailyCustomers == null ||
        averageLitres == null ||
        rental == null ||
        salary == null ||
        utilities == null ||
        maintenance == null ||
        otherCost == null ||
        investment == null) {
      showMessage('Please fill in all fields', isError: true);
      return;
    }

    if (fuelPrice < 0 ||
        fuelCost < 0 ||
        dailyCustomers < 0 ||
        averageLitres < 0 ||
        rental < 0 ||
        salary < 0 ||
        utilities < 0 ||
        maintenance < 0 ||
        otherCost < 0 ||
        investment < 0) {
      showMessage('Values cannot be negative', isError: true);
      return;
    }

    if (![
      fuelPrice,
      fuelCost,
      averageLitres,
      rental,
      salary,
      utilities,
      maintenance,
      otherCost,
      investment,
    ].every((value) => value.isFinite)) {
      showMessage('Values must be finite numbers', isError: true);
      return;
    }

    if (fuelPrice <= fuelCost) {
      showMessage(
        'Selling price must be greater than purchase cost',
        isError: true,
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final result = BusinessEvaluationService.calculate(
        fuelPrice: fuelPrice,
        fuelPurchaseCost: fuelCost,
        dailyCustomers: dailyCustomers,
        averageLitres: averageLitres,
        monthlyRental: rental,
        monthlyStaffSalary: salary,
        monthlyUtilities: utilities,
        monthlyMaintenance: maintenance,
        monthlyOtherCost: otherCost,
        initialInvestment: investment,
      );

      await Supabase.instance.client
          .from('business_evaluations')
          .update({
            'station_name': stationName,
            'fuel_price': fuelPrice,
            'fuel_purchase_cost': fuelCost,
            'daily_customers': dailyCustomers,
            'average_litres': averageLitres,
            'monthly_rental': rental,
            'monthly_staff_salary': salary,
            'monthly_utilities': utilities,
            'monthly_maintenance': maintenance,
            'monthly_other_cost': otherCost,
            'initial_investment': investment,
            'monthly_sales_volume': result.monthlySalesVolume,
            'monthly_revenue': result.monthlyRevenue,
            'monthly_fuel_cost': result.monthlyFuelCost,
            'monthly_operating_cost': result.monthlyOperatingCost,
            'monthly_profit': result.monthlyProfit,
            'profit_margin': result.profitMargin,
            'roi': result.roi,
            'break_even_months': result.breakEvenMonths,
            'profitability_score': result.profitabilityScore,
            'profitability_category': result.category,
            'recommendation': result.recommendation,
            'explanation': result.explanation,
          })
          .eq('id', widget.evaluation.id)
          .eq('user_id', user.id);

      if (!mounted) return;

      final completed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) =>
              EvaluationResultScreen(stationName: stationName, result: result),
        ),
      );

      if (!mounted) return;

      if (completed == true) {
        Navigator.pop(context, true);
      }
    } on PostgrestException {
      if (!mounted) return;
      showMessage(
        'Unable to update the evaluation. Please try again.',
        isError: true,
      );
    } catch (_) {
      if (!mounted) return;
      showMessage(
        'Unable to update the evaluation. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  double? parseDouble(TextEditingController controller) {
    return double.tryParse(controller.text.trim());
  }

  void showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  void dispose() {
    stationNameController.dispose();
    fuelPriceController.dispose();
    fuelCostController.dispose();
    dailyCustomersController.dispose();
    averageLitresController.dispose();
    rentalController.dispose();
    salaryController.dispose();
    utilitiesController.dispose();
    maintenanceController.dispose();
    otherCostController.dispose();
    investmentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Update Profitability Evaluation'),
        backgroundColor: const Color(0xFF168C4B),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          sectionTitle('Station and Fuel'),
          inputField(
            controller: stationNameController,
            label: 'Station Name',
            hint: 'Example: Setapak Smart Fuel Station',
            icon: Icons.local_gas_station,
          ),
          officialFuelPriceCard(),
          inputField(
            controller: fuelPriceController,
            label: 'Selling Price per Litre (RM)',
            hint: 'Example: 2.05',
            icon: Icons.sell_outlined,
            decimal: true,
          ),
          inputField(
            controller: fuelCostController,
            label: 'Purchase Cost per Litre (RM)',
            hint: 'Example: 1.80',
            icon: Icons.shopping_cart_outlined,
            decimal: true,
          ),
          sectionTitle('Customer Demand'),
          inputField(
            controller: dailyCustomersController,
            label: 'Estimated Daily Customers',
            hint: 'Example: 500',
            icon: Icons.groups_outlined,
            number: true,
          ),
          inputField(
            controller: averageLitresController,
            label: 'Average Litres per Customer',
            hint: 'Example: 30',
            icon: Icons.water_drop_outlined,
            decimal: true,
          ),
          sectionTitle('Monthly Operating Costs'),
          inputField(
            controller: rentalController,
            label: 'Rental or Land Cost (RM)',
            hint: 'Example: 15000',
            icon: Icons.location_city,
            decimal: true,
          ),
          inputField(
            controller: salaryController,
            label: 'Staff Salary (RM)',
            hint: 'Example: 30000',
            icon: Icons.badge_outlined,
            decimal: true,
          ),
          inputField(
            controller: utilitiesController,
            label: 'Utilities (RM)',
            hint: 'Example: 5000',
            icon: Icons.electric_bolt_outlined,
            decimal: true,
          ),
          inputField(
            controller: maintenanceController,
            label: 'Maintenance (RM)',
            hint: 'Example: 4000',
            icon: Icons.build_outlined,
            decimal: true,
          ),
          inputField(
            controller: otherCostController,
            label: 'Other Operating Cost (RM)',
            hint: 'Example: 3000',
            icon: Icons.receipt_long_outlined,
            decimal: true,
          ),
          sectionTitle('Initial Investment'),
          inputField(
            controller: investmentController,
            label: 'Initial Investment (RM)',
            hint: 'Example: 1500000',
            icon: Icons.account_balance_outlined,
            decimal: true,
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: isSaving ? null : runEvaluation,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: const Color(0xFF168C4B),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.green.shade200,
            ),
            icon: isSaving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.calculate),
            label: Text(
              isSaving ? 'Calculating...' : 'Calculate Profitability',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Text(
        title,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget officialFuelPriceCard() {
    final price = officialFuelPrice;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: const Color(0xFFE8F5EE),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Official Weekly Fuel Price',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<OfficialFuelProduct>(
              value: selectedFuelProduct,
              decoration: const InputDecoration(
                labelText: 'Fuel Product',
                isDense: true,
              ),
              items: OfficialFuelProduct.values
                  .map(
                    (product) => DropdownMenuItem(
                      value: product,
                      child: Text(product.displayLabel),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (product) {
                if (product != null) {
                  setState(() => selectedFuelProduct = product);
                }
              },
            ),
            const SizedBox(height: 8),
            if (isLoadingOfficialFuelPrice)
              const Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Loading official weekly price...'),
                ],
              )
            else if (officialFuelPriceUnavailable)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Official fuel price is currently unavailable.'),
                  const Text('Enter the selling price manually.'),
                  TextButton.icon(
                    onPressed: loadOfficialFuelPrice,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              )
            else if (price != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Official weekly retail price: RM '
                    '${_selectedOfficialPrice.toStringAsFixed(2)} / litre',
                  ),
                  Text(
                    'Effective: ${_formatEffectiveDate(price.effectiveDate)}',
                  ),
                  TextButton(
                    onPressed: _openOfficialSource,
                    child: const Text(
                      'Fuel price source: Ministry of Finance Malaysia via data.gov.my',
                    ),
                  ),
                  const Text('Weekly official retail price data.'),
                  const Text(
                    'Manual override is allowed for scenario analysis.',
                  ),
                  const SizedBox(height: 4),
                  OutlinedButton(
                    onPressed: useOfficialPrice,
                    child: const Text('Use Official Price'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openOfficialSource() async {
    try {
      await launchUrl(
        Uri.parse('https://data.gov.my/data-catalogue/fuelprice'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Attribution remains visible even when the host cannot open a browser.
    }
  }

  String _formatEffectiveDate(DateTime date) {
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day.toString().padLeft(2, '0')} '
        '${monthNames[date.month - 1]} ${date.year}';
  }

  Widget inputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool number = false,
    bool decimal = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        keyboardType: decimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : number
            ? TextInputType.number
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon),
        ),
      ),
    );
  }
}
