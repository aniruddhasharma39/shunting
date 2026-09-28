import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'services/user_session.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<bool> _initializeSession() async {
    // Add a slight delay for splash screen visibility and smooth transition
    await Future.delayed(const Duration(milliseconds: 800));
    return await UserSession().loadFromPreferences();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeShunt',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, child) {
        return SafeArea(
          top: false,
          bottom: true,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: FutureBuilder<bool>(
        future: _initializeSession(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SplashScreen();
          }
          final isLoggedIn = snapshot.data ?? false;
          return isLoggedIn ? const MainScreen() : const LoginScreen();
        },
      ),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withAlpha(80),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(Icons.shield_outlined, color: Colors.white, size: 64),
            ),
            const SizedBox(height: 24),
            const Text(
              'SafeShunt',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Initializing System...',
              style: TextStyle(color: AppTheme.subtitleColor, fontSize: 14),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(color: AppTheme.primaryColor),
          ],
        ),
      ),
    );
  }
}
