import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import '../services/api_service.dart';
import '../services/user_session.dart';
import 'live_telemetry_screen.dart';

class DeviceInventoryScreen extends StatefulWidget {
  const DeviceInventoryScreen({super.key});

  @override
  State<DeviceInventoryScreen> createState() => _DeviceInventoryScreenState();
}

class _DeviceInventoryScreenState extends State<DeviceInventoryScreen> {
  bool _isLoading = true;
  List<dynamic> _allDevices = [];
  Map<String, dynamic> _summary = {
    'totalDevices': 0,
    'onlineCount': 0,
    'offlineCount': 0,
    'totalSensors': 0,
  };

  // Search & Filters
  final TextEditingController _searchController = TextEditingController();
  String _selectedType = 'ALL';
  String _selectedStatus = 'ALL';
  String? _expandedDeviceId;

  final List<String> _typeFilters = [
    'ALL',
    'Loco Unit',
    'Dead-End',
    'Portable',
    'Coupling'
  ];

  final List<String> _healthStatuses = ['ALL', 'ONLINE', 'OFFLINE'];

  @override
  void initState() {
    super.initState();
    _fetchInventory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatToIST(dynamic timestamp) {
    if (timestamp == null || timestamp.toString().trim().isEmpty || timestamp.toString() == 'N/A') {
      return 'No telemetry recorded';
    }
    try {
      final str = timestamp.toString();
      DateTime dt = DateTime.parse(str);
      // Ensure converted to IST (UTC + 5:30)
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

      // Calculate relative time
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

  Future<void> _fetchInventory() async {
    setState(() => _isLoading = true);

    final result = await ApiService.fetchDeviceRegistry(
      search: _searchController.text,
      productType: _selectedType,
      healthStatus: _selectedStatus,
    );

    if (mounted) {
      if (result['success']) {
        setState(() {
          _allDevices = result['data'] ?? [];
          _summary = Map<String, dynamic>.from(result['summary'] ?? {});
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Failed to load device inventory'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _toggleExpanded(String deviceId) {
    setState(() {
      if (_expandedDeviceId == deviceId) {
        _expandedDeviceId = null;
      } else {
        _expandedDeviceId = deviceId;
      }
    });
  }

  Future<void> _confirmDeleteDevice(BuildContext context, dynamic device) async {
    final deviceId = device['device_id'] ?? device['device_code'] ?? 'Unknown';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.red.shade900, width: 1.5),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 24),
            ),
            const SizedBox(width: 12),
            const Text(
              'Delete Device',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete device "$deviceId"?',
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'This will permanently remove the device, all its historical MQTT telemetry, and line assignments from the database.',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogCtx, true),
            icon: const Icon(Icons.delete, size: 16, color: Colors.white),
            label: const Text('Delete Permanently', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              const SizedBox(width: 12),
              Text('Deleting $deviceId...'),
            ],
          ),
          duration: const Duration(seconds: 1),
        ),
      );

      final res = await ApiService.deleteDeviceRegistry(deviceId.toString());
      if (mounted) {
        if (res['success']) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(res['message'] ?? 'Device deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchInventory();
        } else {
          messenger.showSnackBar(
            SnackBar(
              content: Text(res['message'] ?? 'Failed to delete device'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = UserSession();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF0EA5E9).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.inventory_2, color: Color(0xFF38BDF8), size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'Device Inventory',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B192C), Color(0xFF1E3E62)],
            ),
          ),
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
        elevation: 4,
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh Inventory',
            onPressed: _isLoading ? null : _fetchInventory,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchInventory,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildMetricsSummary(),
              const SizedBox(height: 16),
              _buildSearchBar(),
              const SizedBox(height: 12),
              _buildFilterChips(),
              const SizedBox(height: 16),
              _buildDeviceListHeader(),
              const SizedBox(height: 8),
              _isLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _buildDeviceCardsList(session),
            ],
          ),
        ),
      ),
      floatingActionButton: (session.canManageDevices)
          ? FloatingActionButton.extended(
              onPressed: () => _showAddDeviceModal(context),
              backgroundColor: const Color(0xFF0284C7),
              icon: const Icon(Icons.add_circle_outline, color: Colors.white),
              label: const Text(
                'Register IoT Device',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
  }

  Widget _buildMetricsSummary() {
    final total = _summary['totalDevices'] ?? _allDevices.length;
    final online = _summary['onlineCount'] ?? 0;
    final offline = _summary['offlineCount'] ?? 0;
    final sensors = _summary['totalSensors'] ?? 0;

    return Row(
      children: [
        _buildStatCard(
          title: 'Total Things',
          value: total.toString(),
          icon: Icons.devices_other,
          color: const Color(0xFF3B82F6),
          gradientColors: [const Color(0xFF1E293B), const Color(0xFF0F172A)],
        ),
        const SizedBox(width: 8),
        _buildStatCard(
          title: 'Online (<=30s)',
          value: online.toString(),
          icon: Icons.wifi,
          color: const Color(0xFF10B981),
          gradientColors: [const Color(0xFF1E293B), const Color(0xFF0F172A)],
        ),
        const SizedBox(width: 8),
        _buildStatCard(
          title: 'Offline',
          value: offline.toString(),
          icon: Icons.wifi_off,
          color: const Color(0xFFEF4444),
          gradientColors: [const Color(0xFF1E293B), const Color(0xFF0F172A)],
        ),
        const SizedBox(width: 8),
        _buildStatCard(
          title: 'Total Sensors',
          value: sensors.toString(),
          icon: Icons.sensors,
          color: const Color(0xFFF59E0B),
          gradientColors: [const Color(0xFF1E293B), const Color(0xFF0F172A)],
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required List<Color> gradientColors,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search by Device ID, Serial No, Product Type...',
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
          prefixIcon: const Icon(Icons.search, color: Color(0xFF38BDF8), size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _fetchInventory();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onSubmitted: (_) => _fetchInventory(),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Product Type Filter
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _typeFilters.map((type) {
              final isSelected = _selectedType == type;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(type),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() => _selectedType = type);
                    _fetchInventory();
                  },
                  backgroundColor: const Color(0xFF1E293B),
                  selectedColor: const Color(0xFF0284C7),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                  side: BorderSide(
                    color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 6),
        // Health Status Filter
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _healthStatuses.map((status) {
              final isSelected = _selectedStatus == status;
              Color statusColor = const Color(0xFF0284C7);
              if (status == 'ONLINE') statusColor = const Color(0xFF10B981);
              if (status == 'OFFLINE') statusColor = const Color(0xFFEF4444);

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (status == 'ONLINE') ...[
                        const Icon(Icons.circle, color: Color(0xFF10B981), size: 10),
                        const SizedBox(width: 4),
                      ],
                      if (status == 'OFFLINE') ...[
                        const Icon(Icons.circle, color: Color(0xFFEF4444), size: 10),
                        const SizedBox(width: 4),
                      ],
                      Text(status == 'ALL' ? 'All Statuses' : status),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedStatus = status);
                      _fetchInventory();
                    }
                  },
                  backgroundColor: const Color(0xFF1E293B),
                  selectedColor: statusColor.withValues(alpha: 0.3),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 11,
                  ),
                  side: BorderSide(
                    color: isSelected ? statusColor : const Color(0xFF334155),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceListHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'REGISTERED DEVICES (${_allDevices.length})',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Color(0xFF94A3B8),
          ),
        ),
        const Text(
          'Dynamic 30s Status',
          style: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _buildDeviceCardsList(UserSession session) {
    if (_allDevices.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Column(
          children: [
            const Icon(Icons.devices_outlined, size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            const Text(
              'No Devices Found in Registry',
              style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Real devices will automatically appear when connected to AWS IoT MQTT or registered manually.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            if (session.canManageDevices) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _showAddDeviceModal(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Register Device Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _allDevices.length,
      itemBuilder: (context, index) {
        final device = _allDevices[index];
        return _buildDeviceCard(device, session);
      },
    );
  }

  Widget _buildDeviceCard(dynamic device, UserSession session) {
    final deviceId = device['device_id'] ?? device['device_code'] ?? 'Unknown';
    final deviceName = device['device_name'] ?? deviceId;
    final serialNumber = device['serial_number'] ?? 'N/A';
    final productType = (device['product_type'] ?? 'RECEIVER').toString().toUpperCase();
    final deviceType = device['device_type'] ?? (productType == 'TRANSMITTER' ? 'Dead-End' : 'Loco Unit');
    final healthStatus = (device['health_status'] ?? 'OFFLINE').toString().toUpperCase();
    final isOnline = healthStatus == 'ONLINE';
    final hwVer = device['hardware_version'] ?? '1.0';
    final fwVer = device['firmware_version'] ?? '1.0.0';
    final lineName = device['line_name'];
    final yardName = device['yard_name'];

    // Sensors list
    List<dynamic> sensors = [];
    if (device['sensors_config'] != null) {
      if (device['sensors_config'] is List) {
        sensors = device['sensors_config'];
      }
    }

    final isExpanded = _expandedDeviceId == deviceId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOnline
              ? const Color(0xFF10B981).withValues(alpha: 0.4)
              : const Color(0xFF334155),
          width: isOnline ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isOnline
                ? const Color(0xFF10B981).withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Device ID & Type
                    Expanded(
                      child: Row(
                        children: [
                          _buildTypeBadge(productType, deviceType),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              deviceId,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Live Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isOnline
                            ? const Color(0xFF10B981).withValues(alpha: 0.15)
                            : const Color(0xFFEF4444).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isOnline
                              ? const Color(0xFF10B981).withValues(alpha: 0.5)
                              : const Color(0xFFEF4444).withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isOnline ? 'ONLINE (<=30s)' : 'OFFLINE',
                            style: TextStyle(
                              color: isOnline ? const Color(0xFF34D399) : const Color(0xFFF87171),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  deviceName,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 10),
                // Metadata Grid
                Row(
                  children: [
                    Expanded(child: _buildMetaItem('Serial No', serialNumber)),
                    Expanded(child: _buildMetaItem('App Type', deviceType)),
                    Expanded(child: _buildMetaItem('HW / FW', '$hwVer / $fwVer')),
                  ],
                ),
                if (yardName != null || lineName != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 13, color: Color(0xFF38BDF8)),
                      const SizedBox(width: 4),
                      Text(
                        'Assignment: ${yardName ?? 'Yard'} • ${lineName ?? 'Line'}',
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                // Last Reading IST
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 13, color: Colors.white38),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _formatToIST(device['last_reading_timestamp']),
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Collapsible Sensors & Actions Section
          if (isExpanded) ...[
            const Divider(color: Color(0xFF334155), height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CONFIGURED SENSORS',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (sensors.isEmpty)
                    const Text(
                      'No onboard sensors configured in schema.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: sensors.map<Widget>((s) {
                        final sName = s['name'] ?? s['sensor_name'] ?? 'Sensor';
                        final sType = s['type'] ?? s['sensor_type'] ?? '';
                        final pin = s['pin'] != null ? ' (Pin ${s['pin']})' : '';
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            '$sName ($sType)$pin',
                            style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.w500),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ],

          // Card Action Buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Expand / Collapse sensors
                TextButton.icon(
                  onPressed: () => _toggleExpanded(deviceId),
                  icon: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: const Color(0xFF38BDF8),
                  ),
                  label: Text(
                    isExpanded ? 'Less Info' : 'Sensors & Specs',
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    minimumSize: Size.zero,
                  ),
                ),

                Row(
                  children: [
                    // Live Telemetry stream button
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LiveTelemetryScreen(
                              deviceId: deviceId,
                              deviceCode: deviceId,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.radar, size: 14, color: Color(0xFF10B981)),
                      label: const Text(
                        'Live MQTT',
                        style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF10B981)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                    if (session.canManageDevices) ...[
                      const SizedBox(width: 8),
                      // Delete Device button
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Color(0xFFF87171), size: 18),
                        tooltip: 'Delete Device',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: () => _confirmDeleteDevice(context, device),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeBadge(String productType, String deviceType) {
    Color bg = const Color(0xFF0284C7);
    IconData icon = Icons.memory;

    if (productType.contains('RECEIVER') || deviceType.contains('Loco')) {
      bg = const Color(0xFF2563EB);
      icon = Icons.directions_transit;
    } else if (productType.contains('TRANSMITTER') || deviceType.contains('Dead-End')) {
      bg = const Color(0xFF059669);
      icon = Icons.vertical_align_bottom;
    } else if (productType.contains('REPEATER') || deviceType.contains('Portable')) {
      bg = const Color(0xFFD97706);
      icon = Icons.cell_tower;
    } else if (productType.contains('COUPLING')) {
      bg = const Color(0xFF7C3AED);
      icon = Icons.link;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: bg.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: bg),
          const SizedBox(width: 4),
          Text(
            deviceType,
            style: TextStyle(color: bg, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  void _showAddDeviceModal(BuildContext parentContext) {
    final devIdCtrl = TextEditingController();
    final devNameCtrl = TextEditingController();
    final serialCtrl = TextEditingController();
    final hwVerCtrl = TextEditingController(text: '1.0');
    final fwVerCtrl = TextEditingController(text: '2.0.0');

    String selectedType = 'Loco Unit';
    String productType = 'RECEIVER';
    bool isSubmitting = false;

    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.add_circle, color: Color(0xFF38BDF8), size: 22),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Register Real IoT Device',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white60),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(color: Color(0xFF334155)),
                  Expanded(
                    child: ListView(
                      children: [
                        const SizedBox(height: 8),
                        _buildInputField('Device ID / Thing Name *', devIdCtrl, 'e.g. RX-06, TX-06, LD-002, DE-002'),
                        const SizedBox(height: 12),
                        _buildInputField('Device Name', devNameCtrl, 'e.g. Shunting Receiver Unit North Yard'),
                        const SizedBox(height: 12),
                        _buildInputField('Serial Number *', serialCtrl, 'e.g. SN-RX-06-2026'),
                        const SizedBox(height: 12),
                        const Text(
                          'Device & Product Type *',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              dropdownColor: const Color(0xFF1E293B),
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              value: selectedType,
                              items: const [
                                DropdownMenuItem(value: 'Loco Unit', child: Text('Loco Unit (Receiver / LD)')),
                                DropdownMenuItem(value: 'Dead-End', child: Text('Dead-End (Transmitter / DE)')),
                                DropdownMenuItem(value: 'Portable', child: Text('Portable (Repeater / Trackside)')),
                                DropdownMenuItem(value: 'Coupling', child: Text('Coupling Unit (Sensor)')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() {
                                    selectedType = val;
                                    if (val == 'Loco Unit') productType = 'RECEIVER';
                                    if (val == 'Dead-End') productType = 'TRANSMITTER';
                                    if (val == 'Portable') productType = 'REPEATER';
                                    if (val == 'Coupling') productType = 'COUPLING';
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _buildInputField('Hardware Version', hwVerCtrl, '1.0')),
                            const SizedBox(width: 12),
                            Expanded(child: _buildInputField('Firmware Version', fwVerCtrl, '2.0.0')),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    final idVal = devIdCtrl.text.trim();
                                    final serVal = serialCtrl.text.trim();
                                    final nameVal = devNameCtrl.text.trim();

                                    if (idVal.isEmpty || serVal.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Device ID and Serial Number are required.')),
                                      );
                                      return;
                                    }

                                    setModalState(() => isSubmitting = true);

                                    final payload = {
                                      'device_id': idVal,
                                      'device_name': nameVal.isNotEmpty ? nameVal : idVal,
                                      'serial_number': serVal,
                                      'product_type': productType,
                                      'device_type': selectedType,
                                      'hardware_version': hwVerCtrl.text.trim(),
                                      'firmware_version': fwVerCtrl.text.trim(),
                                      'manufacturing_date': DateTime.now().toIso8601String().split('T')[0],
                                      'sensors_config': [
                                        {'name': 'Ultrasonic Distance Sensor', 'type': 'ANALOG', 'pin': 'PA1'},
                                        {'name': 'LiPo Battery Monitor', 'type': 'ADC', 'pin': 'PB0'},
                                        {'name': 'SIMCOM A7672S GSM/LTE', 'type': 'UART', 'pin': 'USART1'}
                                      ],
                                      'health_status': 'ONLINE',
                                    };

                                    final res = await ApiService.upsertDeviceRegistry(payload);

                                    if (context.mounted) {
                                      if (res['success']) {
                                        Navigator.pop(context);
                                        ScaffoldMessenger.of(parentContext).showSnackBar(
                                          SnackBar(
                                            content: Text('Device "$idVal" registered successfully!'),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                        _fetchInventory();
                                      } else {
                                        setModalState(() => isSubmitting = false);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(res['message'] ?? 'Failed to register device'),
                                            backgroundColor: Colors.redAccent,
                                          ),
                                        );
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0284C7),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Text(
                                    'REGISTER DEVICE',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInputField(String label, TextEditingController controller, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
            filled: true,
            fillColor: const Color(0xFF1E293B),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF334155)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF334155)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF38BDF8)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}
