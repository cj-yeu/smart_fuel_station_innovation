import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddVehicleScreen extends StatefulWidget {
  const AddVehicleScreen({super.key});

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  final plateNumberController = TextEditingController();
  final vehicleModelController = TextEditingController();
  final registrationYearController = TextEditingController();

  final vehicleTypes = [
    'Car',
    'Motorcycle',
    'Van',
    'Truck',
    'Bus',
    'Other',
  ];

  final fuelTypes = [
    'Petrol',
    'Diesel',
    'Hybrid',
    'Electric',
    'Other',
  ];

  String? selectedVehicleType;
  String? selectedFuelType;
  bool isSaving = false;

  Future<void> addVehicle() async {
    final user = Supabase.instance.client.auth.currentUser;
    final plateNumber = plateNumberController.text.trim().toUpperCase();
    final vehicleModel = vehicleModelController.text.trim();
    final registrationYear = int.tryParse(
      registrationYearController.text.trim(),
    );

    if (user == null) {
      showMessage('No logged-in user found', isError: true);
      return;
    }

    if (plateNumber.isEmpty ||
        vehicleModel.isEmpty ||
        selectedVehicleType == null ||
        selectedFuelType == null ||
        registrationYear == null) {
      showMessage('Please fill in all fields', isError: true);
      return;
    }

    final currentYear = DateTime.now().year;

    if (registrationYear < 1950 ||
        registrationYear > currentYear + 1) {
      showMessage(
        'Please enter a valid registration year',
        isError: true,
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      await Supabase.instance.client.from('vehicles').insert({
        'user_id': user.id,
        'plate_number': plateNumber,
        'vehicle_type': selectedVehicleType,
        'vehicle_model': vehicleModel,
        'fuel_type': selectedFuelType,
        'registration_year': registrationYear,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vehicle registered successfully'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true);
    } on PostgrestException catch (error) {
      if (!mounted) return;

      if (error.code == '23505') {
        showMessage(
          'This plate number is already registered',
          isError: true,
        );
      } else {
        showMessage(error.message, isError: true);
      }
    } catch (error) {
      if (!mounted) return;

      showMessage(
        'Unable to register vehicle. Please try again.',
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
    plateNumberController.dispose();
    vehicleModelController.dispose();
    registrationYearController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text('Add Vehicle'),
        backgroundColor: const Color(0xFF168C4B),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: plateNumberController,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Plate Number',
                hintText: 'Example: VAB1234',
                prefixIcon: Icon(Icons.pin),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: selectedVehicleType,
              decoration: const InputDecoration(
                labelText: 'Vehicle Type',
                prefixIcon: Icon(Icons.directions_car),
              ),
              items: vehicleTypes.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type),
                );
              }).toList(),
              onChanged: isSaving
                  ? null
                  : (value) {
                setState(() {
                  selectedVehicleType = value;
                });
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: vehicleModelController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Vehicle Model',
                hintText: 'Example: Perodua Myvi',
                prefixIcon: Icon(Icons.car_repair),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: selectedFuelType,
              decoration: const InputDecoration(
                labelText: 'Fuel Type',
                prefixIcon: Icon(Icons.local_gas_station),
              ),
              items: fuelTypes.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type),
                );
              }).toList(),
              onChanged: isSaving
                  ? null
                  : (value) {
                setState(() {
                  selectedFuelType = value;
                });
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: registrationYearController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Registration Year',
                hintText: 'Example: 2023',
                prefixIcon: Icon(Icons.calendar_month),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: isSaving ? null : addVehicle,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: const Color(0xFF168C4B),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.green.shade200,
              ),
              child: isSaving
                  ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Text(
                'Register Vehicle',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}