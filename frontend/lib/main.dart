import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'services/user_session.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final isLoggedIn = await UserSession().loadFromPreferences();
  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, this.isLoggedIn = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shunting Safety Device',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, child) {
        return SafeArea(
          top: false,
          bottom: true,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: isLoggedIn ? const MainScreen() : const LoginScreen(),
    );
  }
}
