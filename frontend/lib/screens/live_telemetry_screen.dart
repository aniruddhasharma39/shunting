import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import '../services/api_service.dart';

class LiveTelemetryScreen extends StatefulWidget {
  final String? deviceId;
  final String? deviceCode;
  final String? initialTopic;

  const LiveTelemetryScreen({
    super.key,
    this.deviceId,
    this.deviceCode,
    this.initialTopic,
  });

  @override
  State<LiveTelemetryScreen> createState() => _LiveTelemetryScreenState();
}

class _LiveTelemetryScreenState extends State<LiveTelemetryScreen> {
  bool _isLoading = true;
  bool _autoRefresh = true;
  Timer? _timer;

  List<dynamic> _telemetryLogs = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _expandedPayloadIds = {};

  String _targetDeviceId = 'TX-01';
  String _activeTopicSubscription = 'devices/TX-01/telemetry';

  @override
  void initState() {
    super.initState();
    if (widget.deviceId != null && widget.deviceId!.isNotEmpty) {
      _targetDeviceId = widget.deviceId!;
    } else if (widget.deviceCode != null && widget.deviceCode!.isNotEmpty) {
      _targetDeviceId = widget.deviceCode!;
    }

    if (widget.initialTopic != null && widget.initialTopic!.isNotEmpty) {
      _activeTopicSubscription = widget.initialTopic!;
    } else {
      _activeTopicSubscription = 'devices/$_targetDeviceId/telemetry';
    }

    _fetchLiveTelemetry();
    _startSubscriptionTimer();
  }

  @override
  void dispose() {
    _stopSubscriptionTimer();
    _searchController.dispose();
    super.dispose();
  }

  void _startSubscriptionTimer() {
    _timer?.cancel();
    if (_autoRefresh) {
      _timer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (mounted) {
          _fetchLiveTelemetry(silent: true);
        }
      });
    }
  }

  void _stopSubscriptionTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _fetchLiveTelemetry({bool silent = false}) async {
    if (!silent && _telemetryLogs.isEmpty) {
      setState(() => _isLoading = true);
    }

    final result = await ApiService.fetchLiveTelemetry(
      deviceId: _targetDeviceId,
      topic: _activeTopicSubscription,
      limit: 60,
    );

    if (mounted) {
      if (result['success']) {
        setState(() {
          _telemetryLogs = result['data'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Failed to load telemetry stream'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  void _clearLocalLogs() {
    setState(() {
      _telemetryLogs.clear();
      _expandedPayloadIds.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Display cleared'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatToIST(dynamic timestamp) {
    if (timestamp == null || timestamp.toString().trim().isEmpty) {
      return 'N/A';
    }
    try {
      final dt = DateTime.parse(timestamp.toString());
      final ist = dt.toUtc().add(const Duration(hours: 5, minutes: 30));

      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final day = ist.day.toString().padLeft(2, '0');
      final month = months[ist.month - 1];
      final year = ist.year;

      int hour = ist.hour;
      final ampm = hour >= 12 ? 'PM' : 'AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;
      final hourStr = hour.toString().padLeft(2, '0');
      final minuteStr = ist.minute.toString().padLeft(2, '0');
      final secondStr = ist.second.toString().padLeft(2, '0');

      final nowIst = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
      final diff = nowIst.difference(ist);
      String relTime;
      if (diff.inSeconds <= 0) {
        relTime = 'just now';
      } else if (diff.inSeconds < 30) {
        relTime = '${diff.inSeconds}s ago (ONLINE)';
      } else if (diff.inSeconds < 60) {
        relTime = '${diff.inSeconds}s ago';
      } else if (diff.inMinutes < 60) {
        relTime = '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        relTime = '${diff.inHours}h ago';
      } else {
        relTime = '${diff.inDays}d ago';
      }

      return '$day $month $year, $hourStr:$minuteStr:$secondStr $ampm IST ($relTime)';
    } catch (_) {
      return timestamp.toString();
    }
  }

  void _copyToClipboard(String text, BuildContext ctx) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(
        content: Text('MQTT JSON Payload copied to clipboard!'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredLogs = _telemetryLogs.where((log) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final devId = (log['device_id'] ?? '').toString().toLowerCase();
      final topic = (log['topic'] ?? '').toString().toLowerCase();
      final payloadStr = (log['payload'] ?? '').toString().toLowerCase();
      return devId.contains(q) || topic.contains(q) || payloadStr.contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Live MQTT Stream: $_targetDeviceId',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            Text(
              _activeTopicSubscription,
              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontFamily: 'Courier'),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            ),
          ),
        ),
        elevation: 3,
        actions: [
          // Auto-polling LIVE badge
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _autoRefresh ? const Color(0xFF064E3B) : Colors.black45,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _autoRefresh ? const Color(0xFF10B981) : Colors.grey,
                ),
              ),
              child: InkWell(
                onTap: () {
                  setState(() => _autoRefresh = !_autoRefresh);
                  if (_autoRefresh) {
                    _startSubscriptionTimer();
                  } else {
                    _stopSubscriptionTimer();
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _autoRefresh ? const Color(0xFF10B981) : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _autoRefresh ? 'STREAMING (2s)' : 'PAUSED',
                      style: TextStyle(
                        color: _autoRefresh ? const Color(0xFF34D399) : Colors.white60,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _autoRefresh ? Icons.pause_circle_outline : Icons.play_circle_outline,
                      size: 13,
                      color: Colors.white70,
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh, color: Colors.white, size: 20),
            tooltip: 'Fetch Now',
            onPressed: () => _fetchLiveTelemetry(),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white70, size: 20),
            tooltip: 'Clear Messages',
            onPressed: _clearLocalLogs,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetchLiveTelemetry(),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _buildDeviceHeaderCard(),
            const SizedBox(height: 10),
            _buildSearchAndFilterBar(filteredLogs.length),
            const SizedBox(height: 10),
            if (_isLoading && _telemetryLogs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filteredLogs.isEmpty)
              _buildEmptyState()
            else
              ...filteredLogs.asMap().entries.map((entry) {
                final index = entry.key;
                final log = entry.value;
                final logId = log['id']?.toString() ?? index.toString();
                final isPayloadExpanded = _expandedPayloadIds.contains(logId);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildMqttMessageCard(log, logId, isPayloadExpanded),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceHeaderCard() {
    final hasPackets = _telemetryLogs.isNotEmpty;
    final latestTime = hasPackets ? _telemetryLogs[0]['recorded_at'] : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'DEVICE: $_targetDeviceId',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF064E3B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF10B981)),
                ),
                child: const Text(
                  'AWS IoT CORE CONNECTED',
                  style: TextStyle(color: Color(0xFF34D399), fontSize: 9.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0xFF334155)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SUBSCRIBED TOPIC', style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      _activeTopicSubscription,
                      style: const TextStyle(color: Color(0xFFFF9900), fontSize: 11, fontFamily: 'Courier', fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('LATEST TELEMETRY', style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    latestTime != null ? _formatToIST(latestTime) : 'Waiting for packets...',
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilterBar(int packetCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.stream, size: 16, color: Color(0xFF0284C7)),
              const SizedBox(width: 6),
              Text(
                'Stream ($packetCount packets)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textColor),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search within payload JSON...',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                  prefixIcon: const Icon(Icons.search, size: 15, color: Color(0xFF0284C7)),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 14),
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppTheme.borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppTheme.borderColor),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0284C7).withValues(alpha: 0.1),
              ),
              child: const Icon(Icons.radar, size: 40, color: Color(0xFF0284C7)),
            ),
            const SizedBox(height: 12),
            Text(
              'Listening to topic "$_activeTopicSubscription"',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Incoming telemetry packets from AWS IoT Core will appear here automatically every 10 seconds.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMqttMessageCard(Map<String, dynamic> log, String logId, bool isPayloadExpanded) {
    final deviceId = log['device_id']?.toString() ?? _targetDeviceId;
    final topic = log['topic']?.toString() ?? _activeTopicSubscription;
    final recordedAt = log['recorded_at'];

    // Parse payload object
    dynamic rawPayload = log['payload'];
    Map<String, dynamic> payloadMap = {};
    String rawJsonString = '{}';

    if (rawPayload is Map) {
      payloadMap = Map<String, dynamic>.from(rawPayload);
      rawJsonString = const JsonEncoder.withIndent('  ').convert(payloadMap);
    } else if (rawPayload != null) {
      try {
        final parsed = jsonDecode(rawPayload.toString());
        if (parsed is Map) {
          payloadMap = Map<String, dynamic>.from(parsed);
        }
        rawJsonString = const JsonEncoder.withIndent('  ').convert(parsed);
      } catch (_) {
        rawJsonString = rawPayload.toString();
      }
    }

    // Extract nested fields from STM32 payload
    final diag = payloadMap['diagnostics'] is Map ? payloadMap['diagnostics'] : {};
    final readings = payloadMap['readings'] is Map ? payloadMap['readings'] : {};

    final battery = diag['battery_pct'] ?? payloadMap['battery_pct'] ?? log['battery_level'];
    final rssi = diag['gsm_rssi'] ?? payloadMap['gsm_rssi'] ?? log['signal_rssi'];
    final distanceCm = readings['distance_cm'] ?? payloadMap['distance_cm'] ?? log['distance_cm'];
    final uptime = payloadMap['uptime_s'];
    final linkState = diag['link_state'] ?? payloadMap['link_state'];
    final status = diag['status'] ?? payloadMap['status'] ?? 'ONLINE';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Topic and QoS Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF10B981),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.tag, size: 13, color: Color(0xFFFF9900)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    topic,
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                      color: Color(0xFF38BDF8),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Text('QoS 0', style: TextStyle(color: Colors.white70, fontSize: 8.5)),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF064E3B),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status.toString().toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF34D399),
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Device & IST Timestamp Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        deviceId,
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                      ),
                    ),
                  ],
                ),
                Text(
                  _formatToIST(recordedAt),
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF0369A1)),
                ),
              ],
            ),
          ),

          // Sensor Highlights Strip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (distanceCm != null)
                  _buildMetricPill(
                    icon: Icons.straighten,
                    label: 'Distance: ${distanceCm}cm (${_toMeters(distanceCm)}m)',
                    color: const Color(0xFFE11D48),
                  ),
                if (rssi != null)
                  _buildMetricPill(
                    icon: Icons.cell_tower,
                    label: 'GSM RSSI: $rssi dBm',
                    color: const Color(0xFF3B82F6),
                  ),
                if (battery != null)
                  _buildMetricPill(
                    icon: Icons.battery_charging_full,
                    label: 'Battery: $battery%',
                    color: const Color(0xFF10B981),
                  ),
                if (uptime != null)
                  _buildMetricPill(
                    icon: Icons.timer,
                    label: 'Uptime: ${uptime}s',
                    color: const Color(0xFFD97706),
                  ),
                if (linkState != null)
                  _buildMetricPill(
                    icon: Icons.link,
                    label: 'Link: $linkState',
                    color: const Color(0xFF0284C7),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // AWS MQTT Formatted JSON Box
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0A101D),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F172A),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.data_object, size: 12, color: Color(0xFFFF9900)),
                            SizedBox(width: 4),
                            Text(
                              'MQTT JSON PAYLOAD',
                              style: TextStyle(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () => _copyToClipboard(rawJsonString, context),
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.copy, size: 10, color: Color(0xFF38BDF8)),
                                    SizedBox(width: 3),
                                    Text(
                                      'Copy',
                                      style: TextStyle(fontSize: 9.5, color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  if (isPayloadExpanded) {
                                    _expandedPayloadIds.remove(logId);
                                  } else {
                                    _expandedPayloadIds.add(logId);
                                  }
                                });
                              },
                              child: Icon(
                                isPayloadExpanded ? Icons.expand_less : Icons.expand_more,
                                size: 16,
                                color: Colors.white60,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      rawJsonString,
                      maxLines: isPayloadExpanded ? null : 8,
                      overflow: isPayloadExpanded ? null : TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 10.5,
                        color: Color(0xFF34D399),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _toMeters(dynamic cm) {
    try {
      final double val = double.parse(cm.toString());
      return (val / 100).toStringAsFixed(2);
    } catch (_) {
      return '0.00';
    }
  }

  Widget _buildMetricPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
