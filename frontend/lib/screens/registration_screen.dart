import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _fullNameController = TextEditingController();
  final _employeeIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _selectedDesignation;

  final List<String> _designations = [
    'Super Administrator',
    'Yard Administrator',
    'Hardware Engineer',
    'Maintenance User',
    'Viewer / Control Room User'
  ];

  @override
  void dispose() {
    _fullNameController.dispose();
    _employeeIdController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    final fullName = _fullNameController.text.trim();
    final employeeId = _employeeIdController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (fullName.isEmpty || employeeId.isEmpty || email.isEmpty || password.isEmpty || _selectedDesignation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final result = await ApiService.registerUser(
      fullName: fullName,
      employeeId: employeeId,
      email: email,
      designation: _selectedDesignation!,
      password: password,
    );

    setState(() {
      _isLoading = false;
    });

    if (!mounted) return;

    if (result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['data']['message'] ?? 'Registration Successful!'), backgroundColor: Colors.green),
      );
      Navigator.pop(context); // Go back to login screen
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message']), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.primaryColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Create Account'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon and Title Row
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.manage_accounts_outlined, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Join the Safety Network',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Complete your profile to access rail shunting operations and safety logs.',
              style: TextStyle(color: AppTheme.subtitleColor, fontSize: 14),
            ),
            const SizedBox(height: 32),
            
            // Form Fields
            const Text('Full Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.subtitleColor)),
            const SizedBox(height: 8),
            TextField(
              controller: _fullNameController,
              decoration: const InputDecoration(
                hintText: 'John Doe',
              ),
            ),
            const SizedBox(height: 16),
            
            const Text('Employee ID', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.subtitleColor)),
            const SizedBox(height: 8),
            TextField(
              controller: _employeeIdController,
              decoration: const InputDecoration(
                hintText: 'RS-10294',
              ),
            ),
            const SizedBox(height: 16),
            
            const Text('Email Address', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.subtitleColor)),
            const SizedBox(height: 8),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                hintText: 'name@railway.gov',
              ),
            ),
            const SizedBox(height: 16),
            
            const Text('Designation', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.subtitleColor)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                hintText: 'Select position',
              ),
              icon: const Icon(Icons.keyboard_arrow_down),
              initialValue: (_selectedDesignation != null && _designations.contains(_selectedDesignation)) ? _selectedDesignation : null,
              items: _designations.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  _selectedDesignation = newValue;
                });
              },
            ),
            const SizedBox(height: 16),
            
            const Text('Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.subtitleColor)),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                hintText: '••••••••',
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            const Text('Confirm Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.subtitleColor)),
            const SizedBox(height: 8),
            TextField(
              controller: _confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: '••••••••',
              ),
            ),
            const SizedBox(height: 24),
            
            // Terms
            RichText(
              textAlign: TextAlign.center,
              text: const TextSpan(
                style: TextStyle(color: AppTheme.subtitleColor, fontSize: 12),
                children: [
                  TextSpan(text: 'By registering, you agree to our '),
                  TextSpan(text: 'Safety Protocols', style: TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline, color: AppTheme.primaryColor)),
                  TextSpan(text: ' and '),
                  TextSpan(text: 'Data Privacy Policy', style: TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline, color: AppTheme.primaryColor)),
                  TextSpan(text: '.'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            ElevatedButton(
              onPressed: _isLoading ? null : _handleRegister,
              child: _isLoading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Register'),
            ),
            const SizedBox(height: 24),
            
            const SizedBox(height: 16),
            
            // Footer
            Center(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: RichText(
                  text: const TextSpan(
                    style: TextStyle(color: AppTheme.subtitleColor, fontSize: 14),
                    children: [
                      TextSpan(text: 'Already have an account? '),
                      TextSpan(text: 'Log in here.', style: TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline, color: AppTheme.primaryColor)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: const Text('System v2.4.1 | Server: Active', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
