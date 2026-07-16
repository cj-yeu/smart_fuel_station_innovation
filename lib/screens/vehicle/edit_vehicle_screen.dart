import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/vehicle.dart';

class EditVehicleScreen extends StatefulWidget {
  final Vehicle vehicle;

  const EditVehicleScreen({
    super.key,
    required this.vehicle,
  });

  @override
  State<EditVehicleScreen> createState() => _EditVehicleScreenState();
}

class _EditVehicleScreenState extends State<EditVehicleScreen> {
  late final TextEditingController plateNumberController;
  late final TextEditingController vehicleModelController;
  late final TextEditingController registrationYearController;

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

  late String selectedVehicleType;
  late String selectedFuelType;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();

    plateNumberController = TextEditingController(
      text: widget.vehicle.plateNumber,
    );

    vehicleModelController = TextEditingController(
      text: widget.vehicle.vehicleModel,
    );

    registrationYearController = TextEditingController(
      text: widget.vehicle.registrationYear.toString(),
    );

    selectedVehicleType = widget.vehicle.vehicleType;
    selectedFuelType = widget.vehicle.fuelType;
  }

  Future<void> updateVehicle() async {
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
      await Supabase.instance.client
          .from('vehicles')
          .update({
        'plate_number': plateNumber,
        'vehicle_type': selectedVehicleType,
        'vehicle_model': vehicleModel,
        'fuel_type': selectedFuelType,
        'registration_year': registrationYear,
      })
          .eq('id', widget.vehicle.id)
          .eq('user_id', user.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vehicle updated successfully'),
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
        'Unable to update vehicle. Please try again.',
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
        title: const Text('Edit Vehicle'),
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
              decoration: const InputDecoration(
                labelText: 'Plate Number',
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
                if (value != null) {
                  setState(() {
                    selectedVehicleType = value;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: vehicleModelController,
              decoration: const InputDecoration(
                labelText: 'Vehicle Model',
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
                if (value != null) {
                  setState(() {
                    selectedFuelType = value;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: registrationYearController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Registration Year',
                prefixIcon: Icon(Icons.calendar_month),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: isSaving ? null : updateVehicle,
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
                'Save Changes',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}