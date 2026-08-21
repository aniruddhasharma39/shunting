import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/user_session.dart';
import 'dashboard_screen.dart';
// import 'reports_screen.dart';
import 'user_management_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/sessions_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  List<Widget> _getScreens() {
    final session = UserSession();
    final screens = <Widget>[
      const DashboardScreen(),
      // const ReportsScreen(),
      const SessionsScreen(),
    ];

    if (session.isSuperAdmin) {
      // Super Admin gets a 4th tab: User Management
      screens.add(const UserManagementScreen());
    } else {
      screens.add(const ProfileScreen());
    }

    return screens;
  }

  List<BottomNavigationBarItem> _getNavItems() {
    final session = UserSession();
    final items = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(
        icon: Icon(Icons.home_outlined),
        activeIcon: Icon(Icons.home),
        label: 'Home',
      ),
      // const BottomNavigationBarItem(
      //   icon: Icon(Icons.bar_chart),
      //   activeIcon: Icon(Icons.bar_chart),
      //   label: 'Reports',
      // ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.history_outlined),
        activeIcon: Icon(Icons.history),
        label: 'Sessions',
      ),
    ];

    if (session.isSuperAdmin) {
      items.add(const BottomNavigationBarItem(
        icon: Icon(Icons.admin_panel_settings_outlined),
        activeIcon: Icon(Icons.admin_panel_settings),
        label: 'Users',
      ));
    } else {
      items.add(const BottomNavigationBarItem(
        icon: Icon(Icons.person_outline),
        activeIcon: Icon(Icons.person),
        label: 'Profile',
      ));
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final screens = _getScreens();
    final navItems = _getNavItems();

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: AppTheme.primaryColor,
          unselectedItemColor: AppTheme.subtitleColor,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 12),
          items: navItems,
        ),
      ),
    );
  }
}
