import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import '../services/user_session.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'device_inventory_screen.dart';
import 'sessions_screen.dart';
import 'issue_return_screen.dart';
// import 'reports_screen.dart';
import 'profile_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<Map<String, dynamic>> _dashboardDataFuture;

  @override
  void initState() {
    super.initState();
    _dashboardDataFuture = ApiService.fetchDashboardSummary();
  }

  Future<void> _refreshData() async {
    setState(() {
      _dashboardDataFuture = ApiService.fetchDashboardSummary();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = UserSession();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      drawer: const AppDrawer(),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A2A42), Color(0xFF0F172A)], // Rich deep blue gradient
            ),
          ),
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text('Live Operations', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle, color: Colors.white),
            onSelected: (value) {
              if (value == 'profile') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                );
              } else if (value == 'logout') {
                UserSession().clear();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'profile',
                child: Text('View Profile'),
              ),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Text('Logout'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _dashboardDataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError || !snapshot.hasData || snapshot.data!['success'] == false) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      snapshot.data?['message'] ?? 'Failed to load dashboard data',
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _refreshData,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            final data = snapshot.data!['data'];
            return _buildBodyForRole(context, session, data);
          },
        ),
      ),
    );
  }

  Widget _buildBodyForRole(BuildContext context, UserSession session, Map<String, dynamic> data) {
    if (session.isSuperAdmin) {
      return _buildSuperAdminBody(context, data);
    } else if (session.isYardAdmin) {
      return _buildYardAdminBody(context, session, data);
    } else {
      return _buildViewerBody(context, data);
    }
  }

  // ==========================================
  // SUPER ADMIN DASHBOARD
  // ==========================================
  Widget _buildSuperAdminBody(BuildContext context, Map<String, dynamic> data) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSuperAdminBanner(),
          _buildCriticalAlertsBanner(data['criticalAlert']),
          const SizedBox(height: 24),
          _buildSectionTitle('LIVE ACTIVE SESSIONS', Icons.radar),
          _buildLiveSessionsCarousel(context, data['liveSessions'] ?? []),
          const SizedBox(height: 16),
          _buildSectionTitle('GLOBAL YARD HEALTH SUMMARY', Icons.health_and_safety_outlined),
          _buildHealthSummaryGrid(
            context: context, 
            healthData: data['health'] ?? {},
            title1: 'Total Active\nDevices', 
            title2: 'Devices\nOffline', 
            title3: 'Total Sessions\nToday', 
            title4: 'System\nStatus'
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ==========================================
  // YARD ADMIN DASHBOARD
  // ==========================================
  Widget _buildYardAdminBody(BuildContext context, UserSession session, Map<String, dynamic> data) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildYardAdminBanner(session),
          _buildYardAdminQuickActions(),
          _buildCriticalAlertsBanner(data['criticalAlert']),
          const SizedBox(height: 24),
          _buildSectionTitle('LIVE ACTIVE SESSIONS (MY YARDS)', Icons.radar),
          _buildLiveSessionsCarousel(context, data['liveSessions'] ?? []),
          const SizedBox(height: 16),
          _buildSectionTitle('MY YARDS HEALTH SUMMARY', Icons.health_and_safety_outlined),
          _buildHealthSummaryGrid(
            context: context, 
            healthData: data['health'] ?? {},
            title1: 'Active Devices\n(My Yards)', 
            title2: 'Devices Offline\n(My Yards)', 
            title3: 'My Sessions\nToday', 
            title4: 'My Yards\nStatus'
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ==========================================
  // VIEWER / CONTROL ROOM DASHBOARD
  // ==========================================
  Widget _buildViewerBody(BuildContext context, Map<String, dynamic> data) {
    final liveSessions = (data['liveSessions'] as List<dynamic>?) ?? [];
    
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCriticalAlertsBanner(data['criticalAlert']),
          const SizedBox(height: 16),
          _buildSectionTitle('HEALTH SUMMARY', Icons.health_and_safety_outlined),
          _buildHealthSummaryGrid(
            context: context, 
            healthData: data['health'] ?? {},
            title1: 'Total Active\nDevices', 
            title2: 'Devices\nOffline', 
            title3: 'Total Sessions\nToday', 
            title4: 'System\nStatus'
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('LIVE OPERATIONS FEED', Icons.radar),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: liveSessions.map<Widget>((sessionData) => _buildLiveGlowingCard(
                context: context,
                yard: sessionData['yard'] ?? 'Unknown Yard',
                line: sessionData['line'] ?? 'Unknown Line',
                ldDevice: sessionData['ldDevice'] ?? 'LD-???',
                deDevice: sessionData['deDevice'] ?? 'DE-???',
                distance: sessionData['distance'] ?? '--m',
                isClosing: sessionData['isClosing'] ?? false,
                isExpanded: true,
              )).toList(),
            ),
          ),
          if (liveSessions.isEmpty)
             const Padding(
               padding: EdgeInsets.all(32.0),
               child: Center(child: Text('No active sessions found.', style: TextStyle(color: Colors.white54))),
             ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ==========================================
  // COMMON WIDGETS
  // ==========================================

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.subtitleColor),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: AppTheme.subtitleColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuperAdminBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFDC2626).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: const [
          Icon(Icons.admin_panel_settings, color: Color(0xFFDC2626), size: 18),
          SizedBox(width: 8),
          Text(
            'Super Administrator – Viewing All Yards',
            style: TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildYardAdminBanner(UserSession session) {
    final yardNames = session.assignedYardNames;
    final hasYards = yardNames.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasYards
              ? [const Color(0xFF1E3A5F), const Color(0xFF16325B)]
              : [Colors.orange.shade700, Colors.orange.shade900],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              hasYards ? Icons.location_city : Icons.warning_amber_rounded,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasYards ? 'Yard Administrator' : 'No Yards Assigned',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasYards
                        ? 'Viewing: ${yardNames.join(", ")}'
                        : 'Contact Super Administrator to assign yards.',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildYardAdminQuickActions() {
    return Builder(
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const IssueReturnScreen()));
                },
                icon: const Icon(Icons.output, size: 16, color: Colors.white),
                label: const Text('Issue', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const IssueReturnScreen()));
                },
                icon: const Icon(Icons.keyboard_return, size: 16, color: Colors.white),
                label: const Text('Return', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const DeviceInventoryScreen()));
                },
                icon: const Icon(Icons.build, size: 16, color: Colors.white),
                label: const Text('Maint.', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCriticalAlertsBanner(dynamic alertData) {
    if (alertData == null) {
        return const SizedBox.shrink(); // Hide if no alerts
    }

    return Builder(
      builder: (context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16.0),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SessionsScreen()));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alertData['alert_type'] ?? 'CRITICAL ALERT',
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          alertData['message'] ?? 'Device offline',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.red, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiveSessionsCarousel(BuildContext context, List<dynamic> liveSessions) {
    if (liveSessions.isEmpty) {
        return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
            child: Text('No active sessions right now.', style: TextStyle(color: AppTheme.subtitleColor)),
        );
    }

    return SizedBox(
      height: 120,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        children: liveSessions.map<Widget>((sessionData) => _buildLiveGlowingCard(
          context: context,
          yard: sessionData['yard'] ?? 'Unknown',
          line: sessionData['line'] ?? 'Unknown',
          ldDevice: sessionData['ldDevice'] ?? 'LD',
          deDevice: sessionData['deDevice'] ?? 'DE',
          distance: sessionData['distance'] ?? '--m',
          isClosing: sessionData['isClosing'] ?? false,
          isExpanded: false,
        )).toList(),
      ),
    );
  }

  Widget _buildLiveGlowingCard({
    required BuildContext context,
    required String yard,
    required String line,
    required String ldDevice,
    required String deDevice,
    required String distance,
    required bool isClosing,
    required bool isExpanded,
  }) {
    return Container(
      width: isExpanded ? double.infinity : 240,
      margin: EdgeInsets.only(right: isExpanded ? 0 : 12.0, bottom: isExpanded ? 12.0 : 8.0),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isClosing ? Colors.redAccent.withValues(alpha: 0.8) : Colors.blueAccent.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isClosing ? Colors.redAccent.withValues(alpha: 0.3) : Colors.blueAccent.withValues(alpha: 0.1),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const SessionsScreen()));
          },
          child: Stack(
            children: [
              Positioned(
                top: -15,
                right: -15,
                child: Icon(
                  Icons.radar,
                  size: isExpanded ? 80 : 60,
                  color: Colors.white.withValues(alpha: 0.03),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$yard • $line',
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Colors.greenAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text('LIVE', style: TextStyle(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: isExpanded ? 24 : 16), // Spacer equivalent
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Pairing', style: TextStyle(color: Colors.white54, fontSize: 10)),
                              const SizedBox(height: 2),
                              Text(
                                '$ldDevice ↔ $deDevice',
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              isClosing ? 'HAZARD - TOO CLOSE' : 'Approaching',
                              style: TextStyle(
                                color: isClosing ? Colors.redAccent : Colors.blueAccent,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              distance,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHealthSummaryGrid({
    required BuildContext context,
    required Map<String, dynamic> healthData,
    required String title1, 
    required String title2, 
    required String title3, 
    required String title4
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.6,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildHealthCard(
            context: context, 
            title: title1, 
            value: healthData['activeDevices']?.toString() ?? '0', 
            icon: Icons.memory, 
            color: Colors.blue,
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const DeviceInventoryScreen()));
            },
          ),
          _buildHealthCard(
            context: context, 
            title: title2, 
            value: healthData['offlineDevices']?.toString() ?? '0', 
            icon: Icons.wifi_off, 
            color: Colors.red,
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const DeviceInventoryScreen()));
            },
          ),
          _buildHealthCard(
            context: context, 
            title: title3, 
            value: healthData['totalSessionsToday']?.toString() ?? '0', 
            icon: Icons.history, 
            color: Colors.purple,
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SessionsScreen()));
            },
          ),
          _buildHealthCard(
            context: context, 
            title: title4, 
            value: healthData['systemStatus']?.toString() ?? 'Unknown', 
            icon: Icons.check_circle_outline, 
            color: Colors.green,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildHealthCard({
    required BuildContext context, 
    required String title, 
    required String value, 
    required IconData icon, 
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppTheme.subtitleColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                  ],
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: AppTheme.primaryColor,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
