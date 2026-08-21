import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/user_session.dart';
import 'registration_screen.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _employeeIdController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _employeeIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final employeeId = _employeeIdController.text.trim();
    final password = _passwordController.text;

    if (employeeId.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final result = await ApiService.loginUser(
      loginId: employeeId,
      password: password,
    );

    setState(() {
      _isLoading = false;
    });

    if (!mounted) return;

    if (result['success']) {
      final session = UserSession();
      final roleMessage = session.isYardAdmin && session.assignedYards.isEmpty
          ? 'Login Successful! No yards assigned yet. Contact Super Admin.'
          : 'Login Successful! Role: ${session.displayRole}';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(roleMessage), backgroundColor: Colors.green),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainScreen()),
      );
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
        title: Row(
          children: const [
            Icon(Icons.directions_railway, color: AppTheme.primaryColor),
            SizedBox(width: 8),
            Text('SafeShunt'),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: AppTheme.borderColor, height: 1.0),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Column(
          children: [
            // Logo Icon Placeholder
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.shield_outlined, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'Shunting Safety',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
            ),
            const SizedBox(height: 8),
            const Text(
              'Secure Personnel Authentication',
              style: TextStyle(color: AppTheme.subtitleColor, fontSize: 14),
            ),
            const SizedBox(height: 32),
            
            // Login Card
            Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: AppTheme.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Employee ID / Email', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.subtitleColor)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _employeeIdController,
                    decoration: const InputDecoration(
                      hintText: 'EMP-001 or name@email.com',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.subtitleColor)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      hintText: '••••••••',
                      prefixIcon: const Icon(Icons.lock_outline),
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
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    child: _isLoading 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('LOGIN'),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const RegistrationScreen()),
                        );
                      },
                      child: const Text('Need an account? Register', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w600)),
                    ),
                  )
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Footer
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Text('System v2.4.1', style: TextStyle(fontSize: 12, color: AppTheme.subtitleColor)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text('|', style: TextStyle(color: AppTheme.borderColor)),
                ),
                Text('App Version 1.0', style: TextStyle(fontSize: 12, color: AppTheme.subtitleColor)),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
