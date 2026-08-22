import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/official_fuel_price.dart';
import '../../models/station_assessment.dart';
import '../../services/business_evaluation_service.dart';
import '../../services/official_fuel_price_repository.dart';
import '../../services/station_assessment_repository.dart';
import 'evaluation_result_screen.dart';

typedef CompanyAssessmentLoader = Future<List<StationAssessment>> Function();
typedef OfficialFuelPriceLoader = Future<OfficialFuelPrice> Function();

class AddEvaluationScreen extends StatefulWidget {
  final CompanyAssessmentLoader? assessmentLoader;
  final OfficialFuelPriceLoader? officialFuelPriceLoader;

  const AddEvaluationScreen({
    super.key,
    this.assessmentLoader,
    this.officialFuelPriceLoader,
  });

  @override
  State<AddEvaluationScreen> createState() =>
      _AddEvaluationScreenState();
}

class _AddEvaluationScreenState
    extends State<AddEvaluationScreen> {
  final stationNameController = TextEditingController();
  final fuelPriceController = TextEditingController();
  final fuelCostController = TextEditingController();
  final dailyCustomersController = TextEditingController();
  final averageLitresController = TextEditingController();
  final rentalController = TextEditingController();
  final salaryController = TextEditingController();
  final utilitiesController = TextEditingController();
  final maintenanceController = TextEditingController();
  final otherCostController = TextEditingController();
  final investmentController = TextEditingController();

  late final CompanyAssessmentLoader assessmentLoader;
  late final OfficialFuelPriceLoader officialFuelPriceLoader;
  List<StationAssessment> assessments = const [];
  StationAssessment? selectedAssessment;
  bool isLoadingAssessments = true;
  String? assessmentLoadError;
  OfficialFuelPrice? officialFuelPrice;
  OfficialFuelProduct selectedFuelProduct = OfficialFuelProduct.ron95;
  bool isLoadingOfficialFuelPrice = true;
  bool officialFuelPriceUnavailable = false;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    assessmentLoader =
        widget.assessmentLoader ??
        StationAssessmentRepository(
          Supabase.instance.client,
        ).fetchCompanyAssessments;
    officialFuelPriceLoader =
        widget.officialFuelPriceLoader ?? OfficialFuelPriceRepository().loadLatest;
    loadAssessments();
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
        if (fuelPriceController.text.trim().isEmpty) {
          fuelPriceController.text = _selectedOfficialPrice.toStringAsFixed(2);
        }
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

  /// Loads only the RLS-visible assessments. Company ownership is resolved by
  /// PostgreSQL; this form intentionally supplies no client-side ownership
  /// filter and selection is context/prefill, not a persisted relationship.
  Future<void> loadAssessments() async {
    try {
      final loadedAssessments = await assessmentLoader();
      if (!mounted) return;
      setState(() {
        assessments = loadedAssessments;
        isLoadingAssessments = false;
        assessmentLoadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isLoadingAssessments = false;
        assessmentLoadError =
            'Assessment sites are unavailable. You can continue manually.';
      });
    }
  }

  Future<void> runEvaluation() async {
    final user = Supabase.instance.client.auth.currentUser;
    final stationName = stationNameController.text.trim();

    final fuelPrice = parseDouble(fuelPriceController);
    final fuelCost = parseDouble(fuelCostController);
    final dailyCustomers = int.tryParse(
      dailyCustomersController.text.trim(),
    );
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
      showMessage(
        'Values cannot be negative',
        isError: true,
      );
      return;
    }

    if (![fuelPrice, fuelCost, averageLitres, rental, salary, utilities,
          maintenance, otherCost, investment].every((value) => value.isFinite)) {
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
          .insert({
        'user_id': user.id,
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
        'monthly_operating_cost':
        result.monthlyOperatingCost,
        'monthly_profit': result.monthlyProfit,
        'profit_margin': result.profitMargin,
        'roi': result.roi,
        'break_even_months': result.breakEvenMonths,
        'profitability_score': result.profitabilityScore,
        'profitability_category': result.category,
        'recommendation': result.recommendation,
        'explanation': result.explanation,
      });

      if (!mounted) return;

      final completed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => EvaluationResultScreen(
            stationName: stationName,
            result: result,
          ),
        ),
      );

      if (!mounted) return;

      if (completed == true) {
        Navigator.pop(context, true);
      }
    } on PostgrestException {
      if (!mounted) return;
      showMessage('Unable to save the evaluation. Please try again.', isError: true);
    } catch (_) {
      if (!mounted) return;
      showMessage(
        'Unable to save the evaluation. Please try again.',
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
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text('New Profitability Evaluation'),
        backgroundColor: const Color(0xFF168C4B),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          assessmentSelector(),
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

  Widget assessmentSelector() {
    if (isLoadingAssessments) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Loading assessment sites...'),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (assessmentLoadError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              assessmentLoadError!,
              style: const TextStyle(color: Colors.black54),
            ),
          ),
        DropdownButtonFormField<String>(
          value: selectedAssessment?.id ?? '',
          isExpanded: true,
          itemHeight: 72,
          decoration: const InputDecoration(
            labelText: 'Assessment Site',
            helperText: 'Optional prefill/context; not a saved relationship.',
            prefixIcon: Icon(Icons.location_searching_outlined),
          ),
          items: [
            const DropdownMenuItem(
              value: '',
              child: Text('Manual / No assessment'),
            ),
            for (final assessment in assessments)
              DropdownMenuItem(
                value: assessment.id,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assessment.locationName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      assessmentOptionLabel(assessment),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: (assessmentId) {
            final selected = assessmentId == null || assessmentId.isEmpty
                ? null
                : assessments.firstWhere((item) => item.id == assessmentId);
            setState(() {
              selectedAssessment = selected;
              if (selected != null) {
                stationNameController.text = selected.locationName;
              }
            });
          },
        ),
        if (selectedAssessment != null) assessmentContextCard(selectedAssessment!),
        const SizedBox(height: 8),
      ],
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
                  Text('Effective: ${_formatEffectiveDate(price.effectiveDate)}'),
                  TextButton(
                    onPressed: _openOfficialSource,
                    child: const Text(
                      'Fuel price source: Ministry of Finance Malaysia via data.gov.my',
                    ),
                  ),
                  const Text('Weekly official retail price data.'),
                  const Text('Manual override is allowed for scenario analysis.'),
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

  String assessmentOptionLabel(StationAssessment assessment) {
    final territory = assessment.confirmedTerritory?.displayLabel;
    final geographicStatus =
        assessment.geographicValidationStatus ==
            StationAssessmentGeographicStatus.inside
        ? 'Geographically validated${territory == null ? '' : ' · $territory'}'
        : 'Not geographically validated';
    return '${assessment.suitabilityCategory} '
        '${assessment.finalScore.toStringAsFixed(1)}/100 · $geographicStatus';
  }

  Widget assessmentContextCard(StationAssessment assessment) {
    final territory = assessment.confirmedTerritory?.displayLabel ?? 'None';
    final isValidated =
        assessment.geographicValidationStatus ==
        StationAssessmentGeographicStatus.inside;
    return Card(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      color: const Color(0xFFE8F5EE),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selected assessment context',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text('${assessment.suitabilityCategory} · ${assessment.finalScore.toStringAsFixed(1)}/100'),
            Text('Territory: $territory'),
            Text(
              isValidated
                  ? 'Geographically validated'
                  : 'Not geographically validated',
            ),
            Text('Nearby fuel stations: ${assessment.nearbyFuelStations}'),
            Text(
              'Competitor distance: ${assessment.competitorDistanceKm.toStringAsFixed(2)} km',
            ),
            const SizedBox(height: 4),
            const Text(
              'This is prefill/context only and is not a permanent database relationship.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(
        top: 8,
        bottom: 16,
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
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
            ? const TextInputType.numberWithOptions(
          decimal: true,
        )
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
