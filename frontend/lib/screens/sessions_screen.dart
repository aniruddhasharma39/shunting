import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import '../services/api_service.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  bool _isLoadingLive = true;
  bool _isLoadingHistory = true;
  List<dynamic> _liveSessions = [];
  List<dynamic> _historySessions = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    _fetchLiveSessions();
    _fetchHistorySessions();
  }

  Future<void> _fetchLiveSessions() async {
    setState(() => _isLoadingLive = true);
    final result = await ApiService.fetchSessions(status: 'live');
    if (mounted) {
      if (result['success']) {
        setState(() {
          _liveSessions = result['data'];
          _isLoadingLive = false;
        });
      } else {
        setState(() => _isLoadingLive = false);
      }
    }
  }

  Future<void> _fetchHistorySessions() async {
    setState(() => _isLoadingHistory = true);
    final result = await ApiService.fetchSessions(status: 'history');
    if (mounted) {
      if (result['success']) {
        setState(() {
          _historySessions = result['data'];
          _isLoadingHistory = false;
        });
      } else {
        setState(() => _isLoadingHistory = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: const Text('Live Operations & Sessions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          iconTheme: const IconThemeData(color: Colors.white),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A2A42), Color(0xFF0F172A)],
              ),
            ),
          ),
          bottom: const TabBar(
            indicatorColor: Colors.blueAccent,
            indicatorWeight: 4,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            tabs: [
              Tab(icon: Icon(Icons.satellite_alt), text: 'LIVE OPERATIONS'),
              Tab(icon: Icon(Icons.history), text: 'SESSION HISTORY'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _isLoadingLive ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: _fetchLiveSessions, child: _buildLiveTab()),
            _isLoadingHistory ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: _fetchHistorySessions, child: _buildHistoryTab()),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveTab() {
    if (_liveSessions.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
           SizedBox(height: 100),
           Center(child: Text('No active shunting sessions.', style: TextStyle(color: AppTheme.subtitleColor)))
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      itemCount: _liveSessions.length,
      itemBuilder: (context, index) {
        final session = _liveSessions[index];
        final isWarning = session['status'] == 'Warning';

        return Card(
          margin: const EdgeInsets.only(bottom: 16.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isWarning ? Colors.orangeAccent : AppTheme.borderColor),
          ),
          elevation: isWarning ? 4 : 2,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isWarning ? Colors.orange.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(isWarning ? Icons.warning_amber_rounded : Icons.check_circle_outline, 
                               color: isWarning ? Colors.orange : Colors.green, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            session['status'].toUpperCase(),
                            style: TextStyle(
                              color: isWarning ? Colors.orange : Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: Text(
                        'SES-${session['id'].toString().length > 8 ? session['id'].toString().substring(0, 8) : session['id']}',
                        style: const TextStyle(color: AppTheme.subtitleColor, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricBlock('Distance', session['distance'] ?? 'N/A', isWarning ? Colors.orange : AppTheme.primaryColor, 24),
                    ),
                    Expanded(
                      child: _buildMetricBlock('Start Time', _formatTime(session['startTime']), AppTheme.primaryColor, 18),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildDeviceLink(session['ldDevice'] ?? 'Unknown', Icons.train),
                    const Icon(Icons.sync_alt, color: AppTheme.subtitleColor),
                    _buildDeviceLink(session['deDevice'] ?? 'Unknown', Icons.stop_circle_outlined),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 16, color: AppTheme.subtitleColor),
                    const SizedBox(width: 4),
                    if (session['exactLocation'] != null && session['exactLocation'] != 'Unknown')
                      Text("Loc: ${session['exactLocation']} | Pit: ${session['pitLane'] ?? 'N/A'}", style: const TextStyle(fontSize: 12, color: AppTheme.subtitleColor, fontWeight: FontWeight.w500))
                    else
                      Text("${session['yard']} • ${session['line']}", style: const TextStyle(fontSize: 12, color: AppTheme.subtitleColor)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.person, size: 16, color: AppTheme.subtitleColor),
                    const SizedBox(width: 4),
                    Text("Holder: ${session['holder']}", style: const TextStyle(fontSize: 12, color: AppTheme.subtitleColor)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryTab() {
    if (_historySessions.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
           SizedBox(height: 100),
           Center(child: Text('No past shunting sessions found.', style: TextStyle(color: AppTheme.subtitleColor)))
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      itemCount: _historySessions.length,
      itemBuilder: (context, index) {
        final session = _historySessions[index];

        return Card(
          margin: const EdgeInsets.only(bottom: 12.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'SES-${session['id'].toString().length > 8 ? session['id'].toString().substring(0, 8) : session['id']}', 
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(_formatDate(session['startTime']), style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${_formatTime(session['startTime'])} - ${_formatTime(session['endTime'])}', style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildDeviceBadge(session['ldDevice'] ?? 'Unknown'),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Icon(Icons.arrow_forward_ios, size: 12, color: AppTheme.borderColor),
                    ),
                    _buildDeviceBadge(session['deDevice'] ?? 'Unknown'),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Final Placement', style: TextStyle(fontSize: 10, color: AppTheme.subtitleColor)),
                        Text(session['distance'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (session['exactLocation'] != null && session['exactLocation'] != 'Unknown')
                  Text("Loc: ${session['exactLocation']} | Pit: ${session['pitLane'] ?? 'N/A'}", style: const TextStyle(fontSize: 12, color: AppTheme.subtitleColor, fontWeight: FontWeight.w500))
                else
                  Text("${session['yard']} • ${session['line']}", style: const TextStyle(fontSize: 12, color: AppTheme.subtitleColor)),
                const SizedBox(height: 4),
                Text("Holder: ${session['holder']}", style: const TextStyle(fontSize: 12, color: AppTheme.subtitleColor)),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '--:--';
    try {
      final date = DateTime.parse(isoString).toLocal();
      return "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return "--:--";
    }
  }

  String _formatDate(String? isoString) {
    if (isoString == null) return '--/--';
    try {
      final date = DateTime.parse(isoString).toLocal();
      return "${date.day}/${date.month}/${date.year}";
    } catch (e) {
      return "--/--";
    }
  }

  Widget _buildMetricBlock(String label, String value, Color color, double valueSize) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontSize: valueSize, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildDeviceLink(String deviceId, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryColor),
          const SizedBox(width: 8),
          Text(deviceId, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
        ],
      ),
    );
  }

  Widget _buildDeviceBadge(String deviceId) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(deviceId, style: const TextStyle(fontSize: 12, color: Colors.blueAccent, fontWeight: FontWeight.w600)),
    );
  }
}
