import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../widgets/app_drawer.dart';
import '../services/api_service.dart';
import '../services/user_session.dart';
import 'live_telemetry_screen.dart';
import 'package:open_file/open_file.dart';
import '../utils/download_helper.dart';
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  bool _isLoadingLive = true;
  bool _isLoadingHistory = true;
  bool _autoRefresh = true;
  Timer? _liveRefreshTimer;

  List<dynamic> _liveSessions = [];

  List<dynamic> _historySessions = [];
  List<dynamic> _filteredHistorySessions = [];

  // Filter State
  DateTimeRange? _filterDateRange;
  String _sortBy = 'Session Start'; // 'Session Start', 'Session End'
  bool _sortAscending = false;
  String? _filterYard;
  String? _filterPilot;
  String _filterDeviceId = '';
  double _filterDurationValue = 0; // minutes
  String _filterDurationOperator = '>'; // '>', '<', '='


  @override
  void initState() {
    super.initState();
    _fetchData();
    _startLiveTimer();
  }

  @override
  void dispose() {
    _liveRefreshTimer?.cancel();
    super.dispose();
  }

  void _startLiveTimer() {
    _liveRefreshTimer?.cancel();
    if (_autoRefresh) {
      _liveRefreshTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
        if (mounted) {
          _fetchLiveSessions(silent: true);
        }
      });
    }
  }


  void _applyFilters() {
    List<dynamic> filtered = List.from(_historySessions);

    if (_filterDateRange != null) {
      filtered = filtered.where((s) {
        try {
          final st = DateTime.parse(s['startTime'] ?? s['created_at'] ?? '').toLocal();
          return st.isAfter(_filterDateRange!.start) && st.isBefore(_filterDateRange!.end.add(const Duration(days: 1)));
        } catch (_) { return false; }
      }).toList();
    }

    if (_filterYard != null && _filterYard!.isNotEmpty) {
      filtered = filtered.where((s) => (s['yard'] ?? s['yard_name']) == _filterYard).toList();
    }
    
    if (_filterPilot != null && _filterPilot!.isNotEmpty) {
      filtered = filtered.where((s) => (s['holder'] ?? s['employee_name']) == _filterPilot).toList();
    }

    if (_filterDeviceId.isNotEmpty) {
      final search = _filterDeviceId.toLowerCase();
      filtered = filtered.where((s) {
        final rx = (s['ldDevice'] ?? s['rx_device_id'] ?? '').toString().toLowerCase();
        final tx = (s['deDevice'] ?? s['tx_device_id'] ?? '').toString().toLowerCase();
        return rx.contains(search) || tx.contains(search);
      }).toList();
    }

    if (_filterDurationValue > 0) {
      filtered = filtered.where((s) {
        double durationMins = 0;
        if (s['startTime'] != null && s['endTime'] != null) {
          try {
            final st = DateTime.parse(s['startTime']);
            final et = DateTime.parse(s['endTime']);
            durationMins = et.difference(st).inMinutes.toDouble();
          } catch (_) {}
        } else if (s['duration'] != null) {
           final durStr = s['duration'].toString();
           final hMatch = RegExp(r'(\d+)h').firstMatch(durStr);
           if (hMatch != null) durationMins += int.parse(hMatch.group(1)!) * 60;
           final mMatch = RegExp(r'(\d+)m').firstMatch(durStr);
           if (mMatch != null) durationMins += int.parse(mMatch.group(1)!);
        }

        if (_filterDurationOperator == '>') return durationMins > _filterDurationValue;
        if (_filterDurationOperator == '<') return durationMins < _filterDurationValue;
        if (_filterDurationOperator == '=') return (durationMins - _filterDurationValue).abs() <= 5;
        return true;
      }).toList();
    }

    filtered.sort((a, b) {
      DateTime timeA;
      DateTime timeB;
      if (_sortBy == 'Session End') {
        timeA = DateTime.tryParse(a['endTime'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        timeB = DateTime.tryParse(b['endTime'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      } else {
        timeA = DateTime.tryParse(a['startTime'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        timeB = DateTime.tryParse(b['startTime'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      }
      return _sortAscending ? timeA.compareTo(timeB) : timeB.compareTo(timeA);
    });

    setState(() {
      _filteredHistorySessions = filtered;
    });
  }

  Future<void> _fetchData() async {
    _fetchLiveSessions();
    _fetchHistorySessions();
  }

  Future<void> _fetchLiveSessions({bool silent = false}) async {
    if (!silent && _liveSessions.isEmpty) {
      setState(() => _isLoadingLive = true);
    }
    final result = await ApiService.fetchSessions(status: 'live');
    if (mounted) {
      if (result['success']) {
        final newLive = result['data'] ?? [];
        // If an active session disconnected/ended, trigger history refresh immediately
        if (_liveSessions.isNotEmpty && newLive.isEmpty) {
          _fetchHistorySessions();
        }
        final isSame = jsonEncode(_liveSessions) == jsonEncode(newLive);
        if (!isSame || _isLoadingLive) {
          setState(() {
            _liveSessions = newLive;
            _isLoadingLive = false;
          });
        }
      } else {
        if (_isLoadingLive) {
          setState(() => _isLoadingLive = false);
        }
      }
    }
  }

  Future<void> _fetchHistorySessions() async {
    setState(() => _isLoadingHistory = true);
    final result = await ApiService.fetchSessions(status: 'history');
    if (mounted) {
      if (result['success']) {
        final newHistory = result['data'] ?? [];
        final isSame = jsonEncode(_historySessions) == jsonEncode(newHistory);
        if (!isSame || _isLoadingHistory) {
          setState(() {
            _historySessions = newHistory;
            _isLoadingHistory = false;
          });
          _applyFilters();
        }
      } else {
        if (_isLoadingHistory) {
          setState(() => _isLoadingHistory = false);
        }
      }
    }
  }

  String _formatDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '--/--';
    try {
      final date = DateTime.parse(isoString).toLocal();
      return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
    } catch (_) {
      return "--/--";
    }
  }

  String _formatTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '--:--';
    try {
      final date = DateTime.parse(isoString).toLocal();
      final h = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
      final ampm = date.hour >= 12 ? 'PM' : 'AM';
      return "${h.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} $ampm";
    } catch (_) {
      return "--:--";
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A), // Dark modern backdrop
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.satellite_alt, color: Colors.lightBlueAccent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Live Operations & Sessions',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
              ),
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(_autoRefresh ? Icons.sync : Icons.sync_disabled, 
                         color: _autoRefresh ? Colors.cyanAccent : Colors.white60),
              tooltip: _autoRefresh ? 'Live Auto-Refresh (2s Active)' : 'Auto-Refresh Paused',
              onPressed: () {
                setState(() {
                  _autoRefresh = !_autoRefresh;
                  if (_autoRefresh) {
                    _startLiveTimer();
                  } else {
                    _liveRefreshTimer?.cancel();
                  }
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _fetchData,
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.cyanAccent,
            indicatorWeight: 3,
            labelColor: Colors.cyanAccent,
            unselectedLabelColor: Colors.white60,
            tabs: [
              Tab(icon: Icon(Icons.stream), text: 'LIVE OPERATIONS & PAIRING'),
              Tab(icon: Icon(Icons.history), text: 'SESSION HISTORY'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _isLoadingLive
                ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
                : RefreshIndicator(
                    onRefresh: () => _fetchLiveSessions(),
                    child: _buildLiveTab(),
                  ),
            _isLoadingHistory
                ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
                : RefreshIndicator(
                    onRefresh: _fetchHistorySessions,
                    child: _buildHistoryTab(),
                  ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 1. LIVE OPERATIONS & PAIRED SESSIONS TAB
  // ==========================================
  Widget _buildLiveTab() {
    if (_liveSessions.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.sensors_off, size: 64, color: Colors.white38),
                ),
                const SizedBox(height: 20),
                const Text(
                  'No Active Shunting Sessions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    'To begin a live operation, issue an available Loco Unit (Receiver) to a Loco Pilot in Issue & Return.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      itemCount: _liveSessions.length,
      itemBuilder: (context, index) {
        final session = _liveSessions[index];
        final distanceStr = session['distance'] ?? '--m';
        final distanceVal = session['distanceM'];
        final safetyStatus = session['safetyStatus'] ?? 'LIVE';
        final statusColor = _getSafetyColor(safetyStatus, distanceVal);

        return Container(
          margin: const EdgeInsets.only(bottom: 20.0),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor.withValues(alpha: 0.5), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: statusColor.withValues(alpha: 0.15),
                blurRadius: 16,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Status Header Banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    border: Border(bottom: BorderSide(color: statusColor.withValues(alpha: 0.3))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: statusColor, blurRadius: 6, spreadRadius: 1),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            safetyStatus.toUpperCase(),
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.cloud_done, size: 14, color: Colors.cyanAccent),
                            const SizedBox(width: 6),
                            Text(
                              session['session_code'] ?? 'SES-LIVE',
                              style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Main Cockpit Body
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      // 1. Dual Device Pairing HUD (Receiver <--> Transmitter)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            // RECEIVER (Loco Unit)
                            Expanded(
                              child: _buildDeviceNode(
                                title: 'RECEIVER (LOCO)',
                                deviceId: session['ldDevice'] ?? 'RX-01',
                                icon: Icons.train,
                                iconColor: Colors.lightBlueAccent,
                                battery: session['rxBattery'] ?? '95%',
                                signal: session['rxSignal'] ?? '-62 dBm',
                                subtitle: session['holder'] ?? 'Pilot Holder',
                              ),
                            ),

                            // PAIRED CLOUD LINK
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.cyanAccent.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.sync_alt, color: Colors.cyanAccent, size: 20),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'AWS IoT',
                                    style: TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                  const Text(
                                    '0ms Stream',
                                    style: TextStyle(color: Colors.white38, fontSize: 9),
                                  ),
                                ],
                              ),
                            ),

                            // TRANSMITTER (Dead-End)
                            Expanded(
                              child: _buildDeviceNode(
                                title: 'TRANSMITTER (DE)',
                                deviceId: session['deDevice'] ?? 'TX-01',
                                icon: Icons.sensors,
                                iconColor: Colors.amberAccent,
                                battery: session['txBattery'] ?? '--',
                                signal: session['txSignal'] ?? '--',
                                subtitle: session['yard'] != null ? '${session['yard']} • ${session['line'] ?? 'N/A'}' : 'No yard assigned',
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // 2. High-Impact Distance Radar Visualizer
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              statusColor.withValues(alpha: 0.15),
                              Colors.transparent,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'REAL-TIME BUFFER DISTANCE',
                              style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              distanceStr,
                              style: TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.w900,
                                color: statusColor,
                                letterSpacing: -1.0,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Distance Progress Bar / Safety Radar Gauge
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: _calculateDistanceProgress(distanceVal),
                                minHeight: 10,
                                backgroundColor: Colors.white12,
                                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: const [
                                Text('0m (Hazard)', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                Text('5m (Warning)', style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                Text('20m+ (Safe)', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 3. Operational Info Grid (Pilot, Speed, Yard, Shift)
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoTile(
                              icon: Icons.speed,
                              iconColor: Colors.purpleAccent,
                              label: 'Approach Speed',
                              value: session['speed'] ?? '0.0 km/h',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInfoTile(
                              icon: Icons.person,
                              iconColor: Colors.lightBlueAccent,
                              label: 'Loco Pilot (Holder)',
                              value: session['holder'] ?? 'Rajesh Kumar',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoTile(
                              icon: Icons.location_on,
                              iconColor: Colors.orangeAccent,
                              label: 'Yard & Pit Line',
                              value: '${session['yard']} | ${session['line']}',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInfoTile(
                              icon: Icons.access_time,
                              iconColor: Colors.tealAccent,
                              label: 'Connection Time',
                              value: _formatTime(session['startTime']),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Action buttons in Cockpit
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _showSessionSummaryDialog(session),
                              icon: const Icon(Icons.table_chart, size: 16, color: Colors.cyanAccent),
                              label: const Text('Tabular Logs', style: TextStyle(color: Colors.cyanAccent, fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.cyanAccent),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => LiveTelemetryScreen(
                                      deviceId: session['ldDevice'] ?? 'TX-01',
                                      initialTopic: 'devices/${session['ldDevice'] ?? 'TX-01'}/telemetry',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.terminal, size: 16, color: Colors.white),
                              label: const Text('Live Stream', style: TextStyle(color: Colors.white, fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0284C7),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // 2. SESSION HISTORY TAB
  // ==========================================
  Widget _buildHistoryTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: _buildFilterBar(),
        ),
        Expanded(
          child: _filteredHistorySessions.isEmpty
              ? const Center(
                  child: Text(
                    'No past shunting sessions found matching the criteria.',
                    style: TextStyle(color: Colors.white38),
                  ),
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  itemCount: _filteredHistorySessions.length,
                  itemBuilder: (context, index) {
                    return _buildHistorySessionItem(_filteredHistorySessions[index]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Date Range
          Expanded(
            child: InkWell(
              onTap: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now(),
                  initialDateRange: _filterDateRange,
                  builder: (context, child) => Theme(
                    data: ThemeData.dark().copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: Colors.cyanAccent,
                        onPrimary: Colors.black,
                        surface: Color(0xFF1E293B),
                      ),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) {
                  setState(() => _filterDateRange = picked);
                  _applyFilters();
                }
              },
              child: Row(
                children: [
                  const Icon(Icons.date_range, color: Colors.cyanAccent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _filterDateRange == null
                          ? 'Select Date Range'
                          : '${_filterDateRange!.start.day}/${_filterDateRange!.start.month} - ${_filterDateRange!.end.day}/${_filterDateRange!.end.month}',
                      style: TextStyle(color: _filterDateRange == null ? Colors.white54 : Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_filterDateRange != null)
                    GestureDetector(
                      onTap: () {
                        setState(() => _filterDateRange = null);
                        _applyFilters();
                      },
                      child: const Icon(Icons.clear, size: 16, color: Colors.white54),
                    ),
                ],
              ),
            ),
          ),
          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.filter_list, size: 22, color: Colors.white),
                onPressed: _showAdvancedFilterSheet,
                tooltip: 'Advanced Filters & Sorting',
              ),
              IconButton(
                icon: const Icon(Icons.picture_as_pdf, size: 22, color: Colors.redAccent),
                onPressed: () => _downloadFilteredReport(isExcel: false),
                tooltip: 'Download Filtered PDF',
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAdvancedFilterSheet() {
    final yards = _historySessions.map((s) => (s['yard'] ?? s['yard_name'])?.toString()).where((s) => s != null && s.isNotEmpty).toSet().toList();
    final pilots = _historySessions.map((s) => (s['holder'] ?? s['employee_name'])?.toString()).where((s) => s != null && s.isNotEmpty).toSet().toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Advanced Filters & Sorting', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const Divider(color: Colors.white24, height: 30),
                    
                    // Sort By
                    const Text('Sort By', style: TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _sortBy,
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              filled: true,
                              fillColor: const Color(0xFF1E293B),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                            ),
                            items: ['Session Start', 'Session End'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                            onChanged: (v) => setSheetState(() => _sortBy = v!),
                          ),
                        ),
                        const SizedBox(width: 10),
                        InkWell(
                          onTap: () => setSheetState(() => _sortAscending = !_sortAscending),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8)),
                            child: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, color: Colors.cyanAccent, size: 20),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Yard & Pilot
                    const Text('Attributes', style: TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      value: _filterYard,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Yard',
                        labelStyle: const TextStyle(color: Colors.white54),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('All Yards')),
                        ...yards.map((s) => DropdownMenuItem(value: s, child: Text(s!))),
                      ],
                      onChanged: (v) => setSheetState(() => _filterYard = v),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      value: _filterPilot,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Loco Pilot',
                        labelStyle: const TextStyle(color: Colors.white54),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('All Pilots')),
                        ...pilots.map((s) => DropdownMenuItem(value: s, child: Text(s!))),
                      ],
                      onChanged: (v) => setSheetState(() => _filterPilot = v),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: _filterDeviceId,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Device ID (e.g. RX-01)',
                        labelStyle: const TextStyle(color: Colors.white54),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                      onChanged: (v) => setSheetState(() => _filterDeviceId = v),
                    ),
                    const SizedBox(height: 20),

                    // Duration
                    const Text('Duration (Minutes)', style: TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        DropdownButton<String>(
                          value: _filterDurationOperator,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.cyanAccent, fontSize: 16, fontWeight: FontWeight.bold),
                          underline: const SizedBox(),
                          items: ['>', '<', '='].map((op) => DropdownMenuItem(value: op, child: Text(op))).toList(),
                          onChanged: (v) => setSheetState(() => _filterDurationOperator = v!),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Slider(
                            value: _filterDurationValue,
                            min: 0,
                            max: 240,
                            divisions: 24,
                            activeColor: Colors.cyanAccent,
                            inactiveColor: Colors.white24,
                            label: '${_filterDurationValue.toInt()} mins',
                            onChanged: (v) => setSheetState(() => _filterDurationValue = v),
                          ),
                        ),
                        Text('${_filterDurationValue.toInt()}m', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 30),
                    
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          setState(() {});
                          _applyFilters();
                          Navigator.pop(ctx);
                        },
                        child: const Text('Apply Filters', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _downloadFilteredReport({bool isExcel = false}) async {
    if (_filteredHistorySessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No sessions to download. Adjust filters.'), backgroundColor: Colors.orange));
      return;
    }
    
    DateTime? from = _filterDateRange?.start;
    DateTime? to = _filterDateRange?.end;
    
    if (from == null || to == null) {
       List<DateTime> dates = _filteredHistorySessions.map((s) {
         try {
           return DateTime.parse(s['startTime'] ?? s['created_at'] ?? '');
         } catch (_) { return DateTime.now(); }
       }).toList();
       if (dates.isNotEmpty) {
          dates.sort();
          from = dates.first;
          to = dates.last;
       } else {
          from = DateTime.now().subtract(const Duration(days: 1));
          to = DateTime.now();
       }
    }
    
    final fromStr = '${from.year}-${from.month.toString().padLeft(2,'0')}-${from.day.toString().padLeft(2,'0')}';
    final toStr = '${to.year}-${to.month.toString().padLeft(2,'0')}-${to.day.toString().padLeft(2,'0')}';
    
    String query = 'from_date=$fromStr&to_date=$toStr';
    if (_filterYard != null) query += '&yard=${Uri.encodeComponent(_filterYard!)}';
    if (_filterPilot != null) query += '&pilot=${Uri.encodeComponent(_filterPilot!)}';
    if (_filterDeviceId.isNotEmpty) query += '&device=${Uri.encodeComponent(_filterDeviceId)}';
    if (_filterDurationValue > 0) query += '&dur_op=${Uri.encodeComponent(_filterDurationOperator)}&dur_val=$_filterDurationValue';
    query += '&sort_by=${Uri.encodeComponent(_sortBy)}&sort_asc=$_sortAscending';

    // Instead of directly using ApiService logic, construct the correct report URL
    final token = await UserSession().token ?? '';
    final url = '${ApiService.baseUrl}/reports/range/pdf?$query&token=$token';
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF003580)),
            SizedBox(height: 16),
            Text('Downloading Report...'),
          ],
        ),
      ),
    );

    try {
      final response = await http.get(Uri.parse(url));
      if (context.mounted) Navigator.pop(context); // close dialog

      if (response.statusCode == 200) {
        await downloadAndOpenPdf(response.bodyBytes, 'SafeShunt_Sessions_${fromStr}_to_${toStr}.pdf');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Report Downloaded Successfully!'), backgroundColor: Colors.green),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: Server returned ${response.statusCode}'), backgroundColor: Colors.redAccent),
          );
        }
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context); // close dialog
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }


  Widget _buildHistorySessionItem(dynamic session) {
        final duration = session['duration'] ?? '--';
        final yard = session['yard'];
        final line = session['line'];
        final locationStr = yard != null ? '$yard${line != null ? ' · $line' : ''}' : 'Yard not assigned';

        return Container(
          margin: const EdgeInsets.only(bottom: 12.0),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _showSessionSummaryDialog(session),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.cyanAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle, color: Colors.cyanAccent, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                session['session_code'] ?? 'SES-HIST',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.cyanAccent, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _formatDate(session['startTime']),
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildHistoryDeviceTag(session['ldDevice'] ?? '--', Icons.train, Colors.lightBlueAccent, label: 'RECEIVER'),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: Icon(Icons.sync_alt, size: 16, color: Colors.cyanAccent),
                        ),
                        Expanded(
                          child: _buildHistoryDeviceTag(session['deDevice'] ?? 'N/A', Icons.sensors, Colors.amberAccent, label: 'TRANSMITTER'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Min Proximity', style: TextStyle(fontSize: 10, color: Colors.white38)),
                              const SizedBox(height: 2),
                              Text(
                                session['minDistance'] ?? '--',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orangeAccent, fontSize: 14),
                              ),
                            ],
                          ),
                          const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white24),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('Final Placement', style: TextStyle(fontSize: 10, color: Colors.white38)),
                              const SizedBox(height: 2),
                              Text(
                                session['finalPlacement'] ?? session['distance'] ?? '--',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent, fontSize: 14),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 20, color: Colors.white10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(Icons.location_on_outlined, size: 13, color: Colors.white38),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  locationStr,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: yard != null ? Colors.white60 : Colors.white24,
                                    fontStyle: yard == null ? FontStyle.italic : FontStyle.normal,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.timer_outlined, size: 13, color: Colors.white38),
                            const SizedBox(width: 4),
                            Text(
                              duration != '--' ? duration : '${_formatTime(session['startTime'])} - ${_formatTime(session['endTime'])}',
                              style: const TextStyle(fontSize: 11, color: Colors.white60),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.chevron_right, size: 14, color: Colors.white24),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
  }

  void _showSessionSummaryDialog(dynamic session) {
    showDialog(
      context: context,
      builder: (dialogCtx) => SessionAuditDialog(session: session),
    );
  }

  // ==========================================
  // HELPER WIDGETS
  // ==========================================
  Widget _buildDeviceNode({
    required String title,
    required String deviceId,
    required IconData icon,
    required Color iconColor,
    required String battery,
    required String signal,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                deviceId,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 11), overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.battery_charging_full, size: 12, color: Colors.greenAccent),
            const SizedBox(width: 2),
            Text(battery, style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            Icon(Icons.wifi, size: 12, color: Colors.cyanAccent),
            const SizedBox(width: 2),
            Text(signal, style: const TextStyle(color: Colors.cyanAccent, fontSize: 10)),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryDeviceTag(String deviceId, IconData icon, Color color, {String? label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null)
            Text(label, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 9, fontWeight: FontWeight.bold)),
          if (label != null) const SizedBox(height: 4),
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Flexible(child: Text(deviceId, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)),
            ],
          ),
        ],
      ),
    );
  }

  Color _getSafetyColor(String status, dynamic distanceM) {
    if (distanceM != null) {
      final d = _parseNum(distanceM);
      if (d < 5.0) return const Color(0xFFEF4444); // Red Hazard
      if (d <= 20.0) return const Color(0xFFF59E0B); // Amber Warning
      return const Color(0xFF10B981); // Green Safe
    }
    if (status.contains('HAZARD')) return const Color(0xFFEF4444);
    if (status.contains('WARNING') || status.contains('APPROACHING')) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }

  double _calculateDistanceProgress(dynamic distanceM) {
    if (distanceM == null) return 0.5;
    try {
      final d = (distanceM as num).toDouble();
      if (d <= 0) return 0.05;
      if (d >= 30.0) return 1.0;
      return d / 30.0;
    } catch (_) {
      return 0.5;
    }
  }

  num _parseNum(dynamic val) {
    if (val is num) return val;
    return num.tryParse(val.toString()) ?? 0;
  }
}

// =========================================================================
// SESSION AUDIT & TABULAR LOGS DIALOG
// =========================================================================
class SessionAuditDialog extends StatefulWidget {
  final dynamic session;

  const SessionAuditDialog({super.key, required this.session});

  @override
  State<SessionAuditDialog> createState() => _SessionAuditDialogState();
}

class _SessionAuditDialogState extends State<SessionAuditDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoadingLogs = true;
  List<dynamic> _tabularLogs = [];
  Map<String, dynamic> _sessionDetail = {};
  String _searchFilter = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _sessionDetail = Map<String, dynamic>.from(widget.session);
    _loadSessionDetailsAndLogs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSessionDetailsAndLogs() async {
    final sessionId = widget.session['id']?.toString() ?? widget.session['session_code']?.toString();
    if (sessionId == null) {
      setState(() => _isLoadingLogs = false);
      return;
    }

    final res = await ApiService.fetchSessionDetailsWithLogs(sessionId);
    if (mounted) {
      if (res['success'] == true) {
        setState(() {
          _sessionDetail = res['session'] ?? _sessionDetail;
          _tabularLogs = res['tabularLogs'] ?? [];
          _isLoadingLogs = false;
        });
      } else {
        setState(() => _isLoadingLogs = false);
      }
    }
  }

  Future<void> _exportPdf() async {
    final sessionId = widget.session['id']?.toString() ?? widget.session['session_code']?.toString();
    if (sessionId == null) return;
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Downloading PDF Report...'), backgroundColor: Colors.cyan, duration: Duration(seconds: 2)),
      );
    }

    final url = ApiService.getSessionPdfUrl(sessionId);
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
         final tempDir = await getTemporaryDirectory();
         final file = File('${tempDir.path}/Session_Report_$sessionId.pdf');
         await file.writeAsBytes(response.bodyBytes);
         
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Report Downloaded. Opening...'), backgroundColor: Colors.green),
           );
         }
         
         await OpenFile.open(file.path);
      } else {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to download PDF'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error downloading PDF: $e')));
    }
  }

  Future<void> _exportExcel() async {
    final sessionId = widget.session['id']?.toString() ?? widget.session['session_code']?.toString();
    if (sessionId == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Downloading Excel Report...'), backgroundColor: Colors.cyan, duration: Duration(seconds: 2)),
      );
    }

    final url = ApiService.getSessionExcelUrl(sessionId);
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
         final tempDir = await getTemporaryDirectory();
         final file = File('${tempDir.path}/Session_Report_$sessionId.xlsx');
         await file.writeAsBytes(response.bodyBytes);
         
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Report Downloaded. Opening...'), backgroundColor: Colors.green),
           );
         }
         
         await OpenFile.open(file.path);
      } else {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to download Excel'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error downloading Excel: $e')));
    }
  }

  Future<void> _sharePdf() async {
    final sessionId = widget.session['id']?.toString() ?? widget.session['session_code']?.toString();
    if (sessionId == null) return;
    
    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preparing PDF for sharing...'), backgroundColor: Colors.cyan, duration: Duration(seconds: 2)));
    }
    
    final url = ApiService.getSessionPdfUrl(sessionId);
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
         final tempDir = await getTemporaryDirectory();
         final file = File('${tempDir.path}/Session_Report_$sessionId.pdf');
         await file.writeAsBytes(response.bodyBytes);
         await Share.shareXFiles([XFile(file.path)], text: 'SafeShunt Session Report: $sessionId');
      } else {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to generate PDF for sharing'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error sharing PDF: $e')));
    }
  }

  String _formatTime(dynamic val) {
    if (val == null) return '--:--';
    try {
      final d = DateTime.parse(val.toString()).toLocal();
      final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
      final ampm = d.hour >= 12 ? 'PM' : 'AM';
      return "${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $ampm";
    } catch (_) {
      return val.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionCode = _sessionDetail['session_code'] ?? widget.session['session_code'] ?? 'SES-DETAIL';
    final status = _sessionDetail['status'] ?? widget.session['status'] ?? 'Completed';
    final isLive = status.toString().toUpperCase().contains('LIVE');

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Colors.cyanAccent, width: 1.5),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: MediaQuery.of(context).size.width >= 800 ? 800 : MediaQuery.of(context).size.width * 0.95,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          children: [
            // Top Header
            Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.analytics_outlined, color: Colors.cyanAccent, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                sessionCode,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isLive ? Colors.redAccent.withValues(alpha: 0.2) : Colors.greenAccent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: isLive ? Colors.redAccent : Colors.greenAccent, width: 0.8),
                              ),
                              child: Text(
                                isLive ? 'LIVE' : 'COMPLETED',
                                style: TextStyle(
                                  color: isLive ? Colors.redAccent : Colors.greenAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_sessionDetail['ldDevice'] ?? 'RX'} <--> ${_sessionDetail['deDevice'] ?? 'TX'} • ${_sessionDetail['yard'] ?? 'Yard'}',
                          style: const TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share, color: Colors.blueAccent, size: 22),
                    tooltip: 'Share Report',
                    onPressed: _sharePdf,
                  ),
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 22),
                    tooltip: 'Export PDF Report',
                    onPressed: _exportPdf,
                  ),
                  IconButton(
                    icon: const Icon(Icons.table_view, color: Colors.greenAccent, size: 22),
                    tooltip: 'Export Excel Report',
                    onPressed: _exportExcel,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Tab Bar
            Container(
              color: const Color(0xFF1E293B),
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.cyanAccent,
                labelColor: Colors.cyanAccent,
                unselectedLabelColor: Colors.white60,
                tabs: [
                  const Tab(icon: Icon(Icons.info_outline, size: 16), text: 'METADATA & SUMMARY'),
                  Tab(
                    icon: const Icon(Icons.list_alt, size: 16),
                    text: 'TABULAR LOGS (${_tabularLogs.length})',
                  ),
                ],
              ),
            ),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewTab(),
                  _buildTabularLogsTab(),
                ],
              ),
            ),

            // Bottom Actions Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _exportPdf,
                      icon: const Icon(Icons.picture_as_pdf, size: 14, color: Colors.redAccent),
                      label: const Text('PDF', style: TextStyle(color: Colors.white, fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _exportExcel,
                      icon: const Icon(Icons.table_view, size: 14, color: Colors.greenAccent),
                      label: const Text('Excel', style: TextStyle(color: Colors.white, fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.greenAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _sharePdf,
                      icon: const Icon(Icons.share, size: 14, color: Colors.blueAccent),
                      label: const Text('Share', style: TextStyle(color: Colors.white, fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.blueAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent.shade700,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pairing HUD
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('RECEIVER (LOCO)', style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.train, color: Colors.lightBlueAccent, size: 16),
                        const SizedBox(width: 4),
                        Text(_sessionDetail['ldDevice'] ?? 'RX', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                  ],
                ),
                const Icon(Icons.sync_alt, color: Colors.cyanAccent, size: 20),
                Column(
                  children: [
                    const Text('TRANSMITTER (DE)', style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.sensors, color: Colors.amberAccent, size: 16),
                        const SizedBox(width: 4),
                        Text(_sessionDetail['deDevice'] ?? 'TX', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          _buildSummaryRow('Final Placement Distance', _sessionDetail['finalPlacement'] ?? _sessionDetail['distance'] ?? '--', isHighlight: true),
          _buildSummaryRow('Minimum Proximity Reached', _sessionDetail['minDistance'] ?? '--'),
          _buildSummaryRow('Operation Duration', _sessionDetail['duration'] ?? '--'),
          _buildSummaryRow('Session Start (IST)', _formatTime(_sessionDetail['startTime'])),
          _buildSummaryRow('Session End (IST)', _sessionDetail['endTime'] != null ? _formatTime(_sessionDetail['endTime']) : 'LIVE'),
          _buildSummaryRow('Assigned Yard', _sessionDetail['yard'] ?? 'Not Assigned'),
          _buildSummaryRow('Track / Pit Line', _sessionDetail['line'] ?? 'Not Assigned'),
          _buildSummaryRow('Loco Pilot / Holder', _sessionDetail['holder'] != null ? '${_sessionDetail['holder']} (${_sessionDetail['holderEmployeeId'] ?? '--'})' : 'Not Assigned'),
          _buildSummaryRow('Total Logged Data Points', '${_tabularLogs.length} Telemetry Records'),
          if (_sessionDetail['remarks'] != null && _sessionDetail['remarks'].toString().isNotEmpty)
            _buildSummaryRow('Close Reason', _sessionDetail['remarks'].toString()),
        ],
      ),
    );
  }

  Widget _buildTabularLogsTab() {
    if (_isLoadingLogs) {
      return const Center(child: CircularProgressIndicator(color: Colors.cyanAccent));
    }

    if (_tabularLogs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.data_usage, color: Colors.cyanAccent, size: 48),
              ),
              const SizedBox(height: 20),
              const Text('Process Log Unavailable', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              const Text(
                'Granular telemetry logs for this session have been archived or were not recorded. The session data was successfully aggregated into the Final Placement summary in the Overview tab.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.5),
              ),
            ],
          ),
        ),
      );
    }

    final filteredLogs = _tabularLogs.where((log) {
      if (_searchFilter.isEmpty) return true;
      final s = _searchFilter.toLowerCase();
      return (log['time']?.toString().toLowerCase().contains(s) ?? false) ||
             (log['distance_display']?.toString().toLowerCase().contains(s) ?? false) ||
             (log['safety_status']?.toString().toLowerCase().contains(s) ?? false);
    }).toList();

    return Column(
      children: [
        // Quick filter box
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: SizedBox(
            height: 36,
            child: TextField(
              onChanged: (v) => setState(() => _searchFilter = v),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Search logs (time, distance, status)...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon: const Icon(Icons.search, color: Colors.cyanAccent, size: 16),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),

        // Scrollable Table
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 38,
                dataRowMinHeight: 34,
                dataRowMaxHeight: 38,
                headingRowColor: WidgetStateProperty.all(const Color(0xFF1E293B)),
                columns: const [
                  DataColumn(label: Text('#', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11))),
                  DataColumn(label: Text('Time (IST)', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11))),
                  DataColumn(label: Text('Distance', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11))),
                  DataColumn(label: Text('Speed', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11))),
                  DataColumn(label: Text('Battery', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11))),
                  DataColumn(label: Text('Signal', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11))),
                  DataColumn(label: Text('Safety Status', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11))),
                ],
                rows: filteredLogs.map<DataRow>((log) {
                  final dist = log['distance_display'] ?? (log['distance_m'] != null ? '${log['distance_m']}m' : '--m');
                  final status = log['safety_status'] ?? 'NORMAL';
                  Color statusColor = Colors.greenAccent;
                  if (status == 'CRITICAL HAZARD') {
                    statusColor = Colors.redAccent;
                  } else if (status == 'APPROACHING') {
                    statusColor = Colors.amberAccent;
                  }


                  return DataRow(
                    cells: [
                      DataCell(Text(log['index']?.toString() ?? '-', style: const TextStyle(color: Colors.white54, fontSize: 11))),
                      DataCell(Text(log['time']?.toString() ?? '--', style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'))),
                      DataCell(Text(dist, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12))),
                      DataCell(Text(log['speed_display'] ?? '0.0 km/h', style: const TextStyle(color: Colors.white70, fontSize: 11))),
                      DataCell(Text(log['rx_battery'] ?? '95%', style: const TextStyle(color: Colors.greenAccent, fontSize: 11))),
                      DataCell(Text(log['signal_rssi'] ?? '-65 dBm', style: const TextStyle(color: Colors.cyanAccent, fontSize: 11))),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: statusColor.withValues(alpha: 0.4), width: 0.8),
                          ),
                          child: Text(status, style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                color: isHighlight ? Colors.greenAccent : Colors.white,
                fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
                fontSize: isHighlight ? 14 : 12,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

