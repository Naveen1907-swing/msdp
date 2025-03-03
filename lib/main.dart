import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import './signup_page.dart';
import './driver_dashboard.dart';
import './warehouse_dashboard.dart';
import './customer_dashboard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: 'https://waomzvxnwpfhnsqefmiw.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Indhb216dnhud3BmaG5zcWVmbWl3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDA4Njk0MzAsImV4cCI6MjA1NjQ0NTQzMH0.eG8k-TWlNEwcKW5whYAX-Pxr1p5MHZNVFUEaVumMe84',
  );
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Logistics Management',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );

      if (response.user != null) {
        // Fetch user role from users table
        final userData = await Supabase.instance.client
            .from('users')
            .select('role, full_name')
            .eq('id', response.user!.id)
            .single();
        
        final String userRole = userData['role'] as String;
        final String fullName = userData['full_name'] as String;

        if (!mounted) return;

        // Show welcome message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Welcome back, $fullName!')),
        );

        // Navigate based on user role
        switch (userRole) {
          case 'customer':
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => CustomerDashboard(userId: response.user!.id),
              ),
            );
            break;
          case 'driver':
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => DriverDashboard(userId: response.user!.id),
              ),
            );
            break;
          case 'warehouse_admin':
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => WarehouseDashboard(userId: response.user!.id),
              ),
            );
            break;
          default:
            setState(() {
              _errorMessage = 'Invalid user role: $userRole';
            });
        }
      }
    } catch (e) {
      print('Error during sign in: $e');
      setState(() {
        _errorMessage = e.toString();
      });
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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.local_shipping_outlined,
                    size: 64,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Logistics Management',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock),
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    enabled: !_isLoading,
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _signIn,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Sign In'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SignUpPage(),
                              ),
                            );
                          },
                    child: const Text('Create an Account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

class SignUp {
  const SignUp();
}
