import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/business_evaluation.dart';
import '../../models/official_fuel_price.dart';
import '../../models/station_assessment.dart';
import '../../services/business_evaluation_service.dart';
import '../../services/official_fuel_price_repository.dart';
import '../../services/station_assessment_repository.dart';
import '../../utils/evaluation_number_format.dart';
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
  State<AddEvaluationScreen> createState() => _AddEvaluationScreenState();
}

class _AddEvaluationScreenState extends State<AddEvaluationScreen> {
  static const _numericMaximums = <String, num>{
    'Selling Price per Litre (RM)': 100,
    'Purchase Cost per Litre (RM)': 100,
    'Estimated Daily Customers': 100000,
    'Average Litres per Customer': 1000,
    'Rental or Land Cost (RM)': 100000000,
    'Staff Salary (RM)': 100000000,
    'Utilities (RM)': 100000000,
    'Maintenance (RM)': 100000000,
    'Other Operating Cost (RM)': 100000000,
    'Initial Investment (RM)': 1000000000,
  };

  static const _numericMaximumLengths = <String, int>{
    'Selling Price per Litre (RM)': 6,
    'Purchase Cost per Litre (RM)': 6,
    'Estimated Daily Customers': 6,
    'Average Litres per Customer': 7,
    'Rental or Land Cost (RM)': 12,
    'Staff Salary (RM)': 12,
    'Utilities (RM)': 12,
    'Maintenance (RM)': 12,
    'Other Operating Cost (RM)': 12,
    'Initial Investment (RM)': 13,
  };

  static const _numericRangeHints = <String, String>{
    'Selling Price per Litre (RM)': 'Allowed: RM0–RM100 per litre',
    'Purchase Cost per Litre (RM)': 'Allowed: RM0–RM100 per litre',
    'Estimated Daily Customers': 'Allowed: 0–100,000 customers/day',
    'Average Litres per Customer': 'Allowed: 0–1,000 litres/customer',
    'Rental or Land Cost (RM)': 'Allowed: RM0–RM100,000,000 per month',
    'Staff Salary (RM)': 'Allowed: RM0–RM100,000,000 per month',
    'Utilities (RM)': 'Allowed: RM0–RM100,000,000 per month',
    'Maintenance (RM)': 'Allowed: RM0–RM100,000,000 per month',
    'Other Operating Cost (RM)': 'Allowed: RM0–RM100,000,000 per month',
    'Initial Investment (RM)': 'Allowed: RM0–RM1,000,000,000',
  };

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
  Map<String, String> fieldErrors = const {};

  @override
  void initState() {
    super.initState();
    assessmentLoader =
        widget.assessmentLoader ??
        StationAssessmentRepository(
          Supabase.instance.client,
        ).fetchCompanyAssessments;
    officialFuelPriceLoader =
        widget.officialFuelPriceLoader ??
        OfficialFuelPriceRepository().loadLatest;
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

    final missingOrInvalidFields = <String, String>{};
    void requireText(String label, String value) {
      if (value.isEmpty) {
        missingOrInvalidFields[label] = 'Required — enter a value.';
      }
    }

    void requireNumber(
      String label,
      TextEditingController controller,
      num? value,
    ) {
      final rawValue = controller.text.trim();
      if (rawValue.isEmpty) {
        missingOrInvalidFields[label] = 'Required — enter a value.';
      } else if (value == null || !value.isFinite) {
        missingOrInvalidFields[label] = 'Enter a valid number.';
      } else if (value > _numericMaximums[label]!) {
        missingOrInvalidFields[label] =
            'Enter a value within ${_numericRangeHints[label]!.replaceFirst('Allowed: ', '')}.';
      }
    }

    requireText('Station Name', stationName);
    requireNumber(
      'Selling Price per Litre (RM)',
      fuelPriceController,
      fuelPrice,
    );
    requireNumber('Purchase Cost per Litre (RM)', fuelCostController, fuelCost);
    requireNumber(
      'Estimated Daily Customers',
      dailyCustomersController,
      dailyCustomers,
    );
    requireNumber(
      'Average Litres per Customer',
      averageLitresController,
      averageLitres,
    );
    requireNumber('Rental or Land Cost (RM)', rentalController, rental);
    requireNumber('Staff Salary (RM)', salaryController, salary);
    requireNumber('Utilities (RM)', utilitiesController, utilities);
    requireNumber('Maintenance (RM)', maintenanceController, maintenance);
    requireNumber('Other Operating Cost (RM)', otherCostController, otherCost);
    requireNumber('Initial Investment (RM)', investmentController, investment);

    if (missingOrInvalidFields.isNotEmpty) {
      setState(() {
        fieldErrors = missingOrInvalidFields;
      });
      showMessage('Please fill in all fields', isError: true);
      return;
    }

    final validFuelPrice = fuelPrice!;
    final validFuelCost = fuelCost!;
    final validDailyCustomers = dailyCustomers!;
    final validAverageLitres = averageLitres!;
    final validRental = rental!;
    final validSalary = salary!;
    final validUtilities = utilities!;
    final validMaintenance = maintenance!;
    final validOtherCost = otherCost!;
    final validInvestment = investment!;

    if (validFuelPrice < 0 ||
        validFuelCost < 0 ||
        validDailyCustomers < 0 ||
        validAverageLitres < 0 ||
        validRental < 0 ||
        validSalary < 0 ||
        validUtilities < 0 ||
        validMaintenance < 0 ||
        validOtherCost < 0 ||
        validInvestment < 0) {
      final valuesByLabel = <String, num>{
        'Selling Price per Litre (RM)': validFuelPrice,
        'Purchase Cost per Litre (RM)': validFuelCost,
        'Estimated Daily Customers': validDailyCustomers,
        'Average Litres per Customer': validAverageLitres,
        'Rental or Land Cost (RM)': validRental,
        'Staff Salary (RM)': validSalary,
        'Utilities (RM)': validUtilities,
        'Maintenance (RM)': validMaintenance,
        'Other Operating Cost (RM)': validOtherCost,
        'Initial Investment (RM)': validInvestment,
      };
      for (final entry in valuesByLabel.entries) {
        if (entry.value < 0) {
          missingOrInvalidFields[entry.key] = 'Value cannot be negative.';
        }
      }
      setState(() {
        fieldErrors = missingOrInvalidFields;
      });
      showMessage('Correct the highlighted values', isError: true);
      return;
    }

    if (![
      validFuelPrice,
      validFuelCost,
      validAverageLitres,
      validRental,
      validSalary,
      validUtilities,
      validMaintenance,
      validOtherCost,
      validInvestment,
    ].every((value) => value.isFinite)) {
      showMessage('Values must be finite numbers', isError: true);
      return;
    }

    if (validFuelPrice <= validFuelCost) {
      showMessage(
        'Selling price must be greater than purchase cost',
        isError: true,
      );
      return;
    }

    setState(() {
      isSaving = true;
      fieldErrors = const {};
    });

    try {
      final result = BusinessEvaluationService.calculate(
        fuelPrice: validFuelPrice,
        fuelPurchaseCost: validFuelCost,
        dailyCustomers: validDailyCustomers,
        averageLitres: validAverageLitres,
        monthlyRental: validRental,
        monthlyStaffSalary: validSalary,
        monthlyUtilities: validUtilities,
        monthlyMaintenance: validMaintenance,
        monthlyOtherCost: validOtherCost,
        initialInvestment: validInvestment,
      );

      final savedRow = await Supabase.instance.client
          .from('business_evaluations')
          .insert({
            'user_id': user.id,
            'station_name': stationName,
            'fuel_price': validFuelPrice,
            'fuel_purchase_cost': validFuelCost,
            'daily_customers': validDailyCustomers,
            'average_litres': validAverageLitres,
            'monthly_rental': validRental,
            'monthly_staff_salary': validSalary,
            'monthly_utilities': validUtilities,
            'monthly_maintenance': validMaintenance,
            'monthly_other_cost': validOtherCost,
            'initial_investment': validInvestment,
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
          .select('id,updated_at')
          .single();

      final savedId = savedRow['id'];
      final savedUpdatedAt = savedRow['updated_at'];
      if (savedId is! String || savedUpdatedAt is! String) {
        throw const FormatException('Saved evaluation response is invalid.');
      }
      final savedTimestamp = DateTime.parse(savedUpdatedAt);
      final savedEvaluation = BusinessEvaluation.fromCalculatedValues(
        id: savedId,
        userId: user.id,
        stationName: stationName,
        fuelPrice: validFuelPrice,
        fuelPurchaseCost: validFuelCost,
        dailyCustomers: validDailyCustomers,
        averageLitres: validAverageLitres,
        monthlyRental: validRental,
        monthlyStaffSalary: validSalary,
        monthlyUtilities: validUtilities,
        monthlyMaintenance: validMaintenance,
        monthlyOtherCost: validOtherCost,
        initialInvestment: validInvestment,
        result: result,
        createdAt: savedTimestamp,
        updatedAt: savedTimestamp,
      );

      if (!mounted) return;

      final completed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) =>
              EvaluationResultScreen.fromEvaluation(savedEvaluation),
        ),
      );

      if (!mounted) return;

      if (completed == true) {
        Navigator.pop(context, true);
      }
    } on PostgrestException {
      if (!mounted) return;
      showMessage(
        'Unable to save the evaluation. Please try again.',
        isError: true,
      );
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
            maxLength: 100,
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
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        DropdownButtonFormField<String>(
          initialValue: selectedAssessment?.id ?? '',
          isExpanded: true,
          itemHeight: null,
          decoration: const InputDecoration(
            labelText: 'Assessment Site',
            helperText: 'Optional context only. Enter Station Name manually.',
            prefixIcon: Icon(Icons.location_searching_outlined),
          ),
          selectedItemBuilder: (context) => [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Manual / No assessment',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (final assessment in assessments)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  assessment.locationName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
          ],
          items: [
            const DropdownMenuItem(
              value: '',
              child: Text('Manual / No assessment'),
            ),
            for (final assessment in assessments)
              DropdownMenuItem(
                value: assessment.id,
                child: SizedBox(
                  height: 56,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        assessment.locationName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        assessmentOptionLabel(assessment),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          onChanged: (assessmentId) {
            final selected = assessmentId == null || assessmentId.isEmpty
                ? null
                : assessments.firstWhere((item) => item.id == assessmentId);
            setState(() {
              selectedAssessment = selected;
            });
          },
        ),
        if (selectedAssessment != null)
          assessmentContextCard(selectedAssessment!),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget officialFuelPriceCard() {
    final price = officialFuelPrice;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Theme.of(context).colorScheme.primaryContainer,
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
              initialValue: selectedFuelProduct,
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
                    'Official weekly retail price: '
                    '${EvaluationNumberFormat.currency(_selectedOfficialPrice)} '
                    '/ litre',
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
    } catch (_) {}
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
      color: Theme.of(context).colorScheme.primaryContainer,
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
            Text(
              '${assessment.suitabilityCategory} · ${assessment.finalScore.toStringAsFixed(1)}/100',
            ),
            Text('Territory: $territory'),
            Text(
              isValidated
                  ? 'Geographically validated'
                  : 'Not geographically validated',
            ),
            Text(
              'Nearby fuel stations: '
              '${EvaluationNumberFormat.wholeNumber(assessment.nearbyFuelStations)}',
            ),
            Text(
              'Competitor distance: ${assessment.competitorDistanceKm.toStringAsFixed(2)} km',
            ),
            const SizedBox(height: 4),
            Text(
              'This is context only and is not a permanent database relationship.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
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

  Widget inputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool number = false,
    bool decimal = false,
    int? maxLength,
  }) {
    final errorText = fieldErrors[label];
    final maximum = _numericMaximums[label];
    final inputMaxLength = maxLength ?? _numericMaximumLengths[label];
    final inputFormatters = <TextInputFormatter>[
      if (inputMaxLength != null)
        LengthLimitingTextInputFormatter(inputMaxLength),
      if (maximum != null)
        TextInputFormatter.withFunction((oldValue, newValue) {
          final entered = double.tryParse(newValue.text);
          return entered == null || entered <= maximum ? newValue : oldValue;
        }),
      if (decimal)
        TextInputFormatter.withFunction((oldValue, newValue) {
          return newValue.text.isEmpty ||
                  RegExp(
                    r'^(?:0|[1-9]\d*)(?:\.\d{0,2})?$',
                  ).hasMatch(newValue.text)
              ? newValue
              : oldValue;
        }),
      if (number)
        TextInputFormatter.withFunction((oldValue, newValue) {
          return newValue.text.isEmpty ||
                  RegExp(r'^(?:0|[1-9]\d*)$').hasMatch(newValue.text)
              ? newValue
              : oldValue;
        }),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        onChanged: (_) {
          if (!fieldErrors.containsKey(label)) return;
          setState(() {
            fieldErrors = Map.of(fieldErrors)..remove(label);
          });
        },
        inputFormatters: inputFormatters.isEmpty ? null : inputFormatters,
        keyboardType: decimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : number
            ? TextInputType.number
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: errorText,
          prefixIcon: Icon(icon),
        ),
      ),
    );
  }
}
