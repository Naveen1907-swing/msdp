import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  
  // Additional controllers for role-specific details
  final _warehouseNameController = TextEditingController();
  final _warehouseAddressController = TextEditingController();
  final _vehicleNumberController = TextEditingController();
  final _licenseNumberController = TextEditingController();

  String _selectedRole = 'customer';
  bool _isLoading = false;

  Future<void> _signUp() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Create auth user
      final authResponse = await Supabase.instance.client.auth.signUp(
        email: _emailController.text,
        password: _passwordController.text,
      );

      if (authResponse.user == null) throw 'Signup failed';

      // 2. Insert into users table
      await Supabase.instance.client.from('users').insert({
        'id': authResponse.user!.id,
        'email': _emailController.text,
        'role': _selectedRole,
        'full_name': _fullNameController.text,
        'phone_number': _phoneController.text,
      });

      // 3. Insert role-specific details
      if (_selectedRole == 'warehouse_admin') {
        await Supabase.instance.client.from('warehouse_details').insert({
          'user_id': authResponse.user!.id,
          'warehouse_name': _warehouseNameController.text,
          'address': _warehouseAddressController.text,
        });
      } else if (_selectedRole == 'driver') {
        await Supabase.instance.client.from('driver_details').insert({
          'user_id': authResponse.user!.id,
          'vehicle_number': _vehicleNumberController.text,
          'license_number': _licenseNumberController.text,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign up successful! Please verify your email.')),
        );
        Navigator.pop(context); // Return to login page
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign Up'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Basic Information
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _fullNameController,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone Number'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),

            // Role Selection
            DropdownButtonFormField<String>(
              value: _selectedRole,
              decoration: const InputDecoration(labelText: 'Select Role'),
              items: const [
                DropdownMenuItem(value: 'customer', child: Text('Customer')),
                DropdownMenuItem(value: 'driver', child: Text('Driver')),
                DropdownMenuItem(value: 'warehouse_admin', child: Text('Warehouse Admin')),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedRole = value!;
                });
              },
            ),
            const SizedBox(height: 16),

            // Conditional Fields based on role
            if (_selectedRole == 'warehouse_admin') ...[
              TextField(
                controller: _warehouseNameController,
                decoration: const InputDecoration(labelText: 'Warehouse Name'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _warehouseAddressController,
                decoration: const InputDecoration(labelText: 'Warehouse Address'),
                maxLines: 3,
              ),
            ] else if (_selectedRole == 'driver') ...[
              TextField(
                controller: _vehicleNumberController,
                decoration: const InputDecoration(labelText: 'Vehicle Number'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _licenseNumberController,
                decoration: const InputDecoration(labelText: 'License Number'),
              ),
            ],
            const SizedBox(height: 24),

            // Submit Button
            ElevatedButton(
              onPressed: _isLoading ? null : _signUp,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Sign Up'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    _warehouseNameController.dispose();
    _warehouseAddressController.dispose();
    _vehicleNumberController.dispose();
    _licenseNumberController.dispose();
    super.dispose();
  }
} 