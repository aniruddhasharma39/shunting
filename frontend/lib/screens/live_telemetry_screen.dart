import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class LiveTelemetryScreen extends StatefulWidget {
  final String deviceId;
  final String? deviceCode;

  const LiveTelemetryScreen({
    super.key,
    required this.deviceId,
    this.deviceCode,
  });

  @override
  State<LiveTelemetryScreen> createState() => _LiveTelemetryScreenState();
}

class _LiveTelemetryScreenState extends State<LiveTelemetryScreen> {
  Timer? _pollingTimer;
  bool _isLoading = true;
  List<dynamic> _telemetryLogs = [];
  Map<String, dynamic>? _latestTelemetry;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _fetchData(isPolling: true);
    });
  }

  Future<void> _fetchData({bool isPolling = false}) async {
    if (!isPolling) {
      setState(() => _isLoading = true);
    }

    final result = await ApiService.fetchTelemetryAudit(widget.deviceId);

    if (mounted) {
      if (result['success']) {
        setState(() {
          _telemetryLogs = result['data'] ?? [];
          if (_telemetryLogs.isNotEmpty) {
            _latestTelemetry = _telemetryLogs.first;
          }
          _isLoading = false;
        });
      } else {
        if (!isPolling) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'Failed to load telemetry')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(
          widget.deviceCode != null ? 'Telemetry: ${widget.deviceCode}' : 'Live Telemetry',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
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
      ),
      body: _isLoading && _telemetryLogs.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildLatestTelemetryView(),
                const Divider(),
                Expanded(child: _buildAuditLogList()),
              ],
            ),
    );
  }

  Widget _buildLatestTelemetryView() {
    if (_latestTelemetry == null) {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Center(
          child: Text('No telemetry data available for this device.',
              style: TextStyle(color: AppTheme.subtitleColor)),
        ),
      );
    }

    final payload = _latestTelemetry!['payload'] ?? {};
    final signal = payload['signal'] ?? 'N/A';
    final distanceShow = payload['distance_show'] ?? 'N/A';
    final location = payload['location'] ?? 'N/A';
    final pitLane = payload['pit_lane'] ?? 'N/A';
    final recordedAt = _latestTelemetry!['recorded_at'] != null 
        ? _formatDate(_latestTelemetry!['recorded_at'])
        : 'N/A';

    return Container(
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Current Status',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor),
              ),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('LIVE',
                      style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold)),
                ],
              )
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildStatCard('Signal', signal.toString(), Icons.wifi)),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard('Distance', distanceShow.toString(), Icons.straighten)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatCard('Pit Lane', pitLane.toString(), Icons.train)),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard('Location', location.toString(), Icons.location_on)),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Last updated: $recordedAt',
            style: const TextStyle(fontSize: 12, color: AppTheme.subtitleColor),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 20),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 12, color: AppTheme.subtitleColor)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor)),
        ],
      ),
    );
  }

  Widget _buildAuditLogList() {
    if (_telemetryLogs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: Text(
            'Telemetry Audit Log (Last 20)',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: _telemetryLogs.length,
            itemBuilder: (context, index) {
              final log = _telemetryLogs[index];
              final payload = log['payload'] ?? {};
              final recordedAt = log['recorded_at'] != null 
                  ? _formatDate(log['recorded_at'])
                  : 'Unknown time';

              return Card(
                elevation: 1,
                margin: const EdgeInsets.only(bottom: 8.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListTile(
                  title: Text(
                    'Dist: ${payload['distance_show'] ?? 'N/A'} | Sig: ${payload['signal'] ?? 'N/A'}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(
                    recordedAt,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Text(
                    'Loc: ${payload['location'] ?? 'N/A'}',
                    style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 12),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatDate(String isoString) {
    try {
      final date = DateTime.parse(isoString).toLocal();
      return "${date.day}/${date.month} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}";
    } catch (e) {
      return "Invalid date";
    }
  }
}
