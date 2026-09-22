import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import '../services/api_service.dart';
import '../services/user_session.dart';

class HardwareConsoleScreen extends StatefulWidget {
  const HardwareConsoleScreen({super.key});

  @override
  State<HardwareConsoleScreen> createState() => _HardwareConsoleScreenState();
}

class _HardwareConsoleScreenState extends State<HardwareConsoleScreen> {
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
  String? _expandedDeviceId; // Single-card accordion expansion

  final List<String> _productTypes = ['ALL', 'RECEIVER', 'TRANSMITTER', 'REPEATER'];
  final List<String> _healthStatuses = ['ALL', 'ONLINE', 'OFFLINE'];

  @override
  void initState() {
    super.initState();
    _fetchRegistry();
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

  Future<void> _fetchRegistry() async {
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
            content: Text(result['message'] ?? 'Failed to load device registry'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _toggleExpanded(String deviceId) {
    setState(() {
      if (_expandedDeviceId == deviceId) {
        _expandedDeviceId = null; // collapse if already open
      } else {
        _expandedDeviceId = deviceId; // expand only this card
      }
    });
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
              child: const Icon(Icons.memory, color: Color(0xFF38BDF8), size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'Hardware Console',
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
            onPressed: _isLoading ? null : _fetchRegistry,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchRegistry,
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
                  : _buildDeviceCardsList(),
            ],
          ),
        ),
      ),
      floatingActionButton: (session.isHardwareEngineer || session.isSuperAdmin)
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
          title: 'Sensors',
          value: sensors.toString(),
          icon: Icons.sensors,
          color: const Color(0xFF8B5CF6),
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
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
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
                Text(
                  title,
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                Icon(icon, color: color, size: 16),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onSubmitted: (_) => _fetchRegistry(),
        onChanged: (val) {
          if (val.isEmpty) _fetchRegistry();
        },
        decoration: InputDecoration(
          hintText: 'Search by Device ID, Serial, Name, Sensor, Firmware...',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          prefixIcon: const Icon(Icons.search, color: Color(0xFF0284C7)),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _fetchRegistry();
                  },
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 18, color: Color(0xFF0284C7)),
                  onPressed: _fetchRegistry,
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Product Type Filter
          const Text(
            'Type: ',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.subtitleColor),
          ),
          ..._productTypes.map((type) {
            final isSelected = _selectedType == type;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(
                  type,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : AppTheme.textColor,
                  ),
                ),
                selected: isSelected,
                selectedColor: const Color(0xFF0B192C),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected ? const Color(0xFF0B192C) : AppTheme.borderColor,
                  ),
                ),
                onSelected: (selected) {
                  setState(() {
                    _selectedType = type;
                  });
                  _fetchRegistry();
                },
              ),
            );
          }),
          const SizedBox(width: 8),
          // Health Filter
          const Text(
            'Status: ',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.subtitleColor),
          ),
          ..._healthStatuses.map((status) {
            final isSelected = _selectedStatus == status;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : AppTheme.textColor,
                  ),
                ),
                selected: isSelected,
                selectedColor: status == 'ONLINE'
                    ? const Color(0xFF10B981)
                    : (status == 'OFFLINE' ? const Color(0xFFEF4444) : const Color(0xFF0B192C)),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected ? Colors.transparent : AppTheme.borderColor,
                  ),
                ),
                onSelected: (selected) {
                  setState(() {
                    _selectedStatus = status;
                  });
                  _fetchRegistry();
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDeviceListHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Registered Devices (${_allDevices.length})',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryColor,
          ),
        ),
        if (_expandedDeviceId != null)
          TextButton.icon(
            onPressed: () {
              setState(() {
                _expandedDeviceId = null;
              });
            },
            icon: const Icon(
              Icons.unfold_less,
              size: 16,
              color: Color(0xFF0284C7),
            ),
            label: const Text(
              'Collapse',
              style: TextStyle(fontSize: 12, color: Color(0xFF0284C7), fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }

  Widget _buildDeviceCardsList() {
    if (_allDevices.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              const Text(
                'No matching IoT devices found',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.subtitleColor),
              ),
              const SizedBox(height: 6),
              const Text(
                'Try adjusting your search keywords or filter options.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: _allDevices.map((device) {
        final deviceId = device['device_id']?.toString() ?? '';
        final isExpanded = _expandedDeviceId == deviceId;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildDeviceCard(device, isExpanded),
        );
      }).toList(),
    );
  }


  Widget _buildDeviceCard(Map<String, dynamic> device, bool isExpanded) {
    final deviceId = device['device_id']?.toString() ?? 'Unknown';
    final deviceName = device['device_name']?.toString() ?? 'Unnamed Device';
    final serialNumber = device['serial_number']?.toString() ?? 'N/A';
    final productType = device['product_type']?.toString() ?? 'DEVICE';
    final hwVersion = device['hardware_version']?.toString() ?? '1.0';
    final fwVersion = device['firmware_version']?.toString() ?? '1.0.0';
    final healthStatus = device['health_status']?.toString() ?? 'ONLINE';
    final isOnline = healthStatus.toUpperCase() == 'ONLINE';
    final mfgDate = device['manufacturing_date']?.toString() ?? 'N/A';
    final lastReading = device['last_reading_timestamp']?.toString() ?? 'N/A';
    final uuid = device['id']?.toString() ?? 'N/A';
    final lastErrorCode = device['last_error_code']?.toString();

    // Parse sensors config
    List<dynamic> sensors = [];
    if (device['sensors_config'] != null) {
      if (device['sensors_config'] is List) {
        sensors = device['sensors_config'];
      } else if (device['sensors_config'] is String) {
        try {
          sensors = jsonDecode(device['sensors_config']);
        } catch (_) {}
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExpanded ? const Color(0xFF0284C7).withValues(alpha: 0.5) : AppTheme.borderColor,
          width: isExpanded ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isExpanded ? 0.08 : 0.03),
            blurRadius: isExpanded ? 10 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Collapsed / Header Bar (Click to toggle)
          InkWell(
            onTap: () => _toggleExpanded(deviceId),
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(14),
              bottom: Radius.circular(isExpanded ? 0 : 14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Health Status Indicator Dot
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                          boxShadow: [
                            BoxShadow(
                              color: (isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: 0.5),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Device ID Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          deviceId,
                          style: const TextStyle(
                            color: Color(0xFF38BDF8),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Product Type Badge
                      _buildProductTypeBadge(productType),
                      const Spacer(),
                      // Health status tag
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isOnline ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isOnline ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
                          ),
                        ),
                        child: Text(
                          healthStatus,
                          style: TextStyle(
                            color: isOnline ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Expand / Collapse Chevron
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.keyboard_arrow_down, color: AppTheme.subtitleColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Device Name & Serial
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              deviceName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Serial: $serialNumber',
                              style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Last Seen: ${_formatToIST(lastReading)}',
                                    style: TextStyle(
                                      color: isOnline ? const Color(0xFF059669) : Colors.grey.shade600,
                                      fontSize: 11,
                                      fontWeight: isOnline ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Version & Sensor Count Pills
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'HW v$hwVersion • FW v$fwVersion',
                              style: const TextStyle(color: Color(0xFF475569), fontSize: 10, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.sensors, size: 12, color: Color(0xFF8B5CF6)),
                              const SizedBox(width: 3),
                              Text(
                                '${sensors.length} Sensor${sensors.length == 1 ? '' : 's'}',
                                style: const TextStyle(color: Color(0xFF6D28D9), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Expanded Content Area (Full Hardware Details & sensors_config)
          if (isExpanded) ...[
            const Divider(height: 1, color: AppTheme.borderColor),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0xFFFAFAFC),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hardware Metadata Grid
                  _buildSectionHeader('HARDWARE SPECIFICATIONS & REGISTRY METADATA', Icons.info_outline),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: Column(
                      children: [
                        _buildMetaRow('System UUID', uuid),
                        _buildMetaRow('Manufacturing Date', mfgDate.split('T')[0]),
                        _buildMetaRow('Hardware Version', 'v$hwVersion'),
                        _buildMetaRow('Firmware Version', 'v$fwVersion'),
                        _buildMetaRow('Last Reading (IST)', _formatToIST(lastReading)),
                        if (lastErrorCode != null && lastErrorCode.isNotEmpty)
                          _buildMetaRow('Last Error Code', lastErrorCode, isError: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Sensors Configuration Breakdown (sensors_config)
                  _buildSectionHeader('SENSORS CONFIGURATION (${sensors.length})', Icons.sensors),
                  const SizedBox(height: 8),

                  if (sensors.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                      child: const Center(
                        child: Text(
                          'No sensors configured for this device.',
                          style: TextStyle(color: AppTheme.subtitleColor, fontSize: 12),
                        ),
                      ),
                    )
                  else
                    Column(
                      children: sensors.map((sensor) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildSensorCard(sensor),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProductTypeBadge(String productType) {
    Color bg;
    Color fg;
    switch (productType.toUpperCase()) {
      case 'RECEIVER':
        bg = const Color(0xFFEFF6FF);
        fg = const Color(0xFF1D4ED8);
        break;
      case 'TRANSMITTER':
        bg = const Color(0xFFFAF5FF);
        fg = const Color(0xFF7E22CE);
        break;
      case 'REPEATER':
        bg = const Color(0xFFFFF7ED);
        fg = const Color(0xFFC2410C);
        break;
      default:
        bg = const Color(0xFFF3F4F6);
        fg = const Color(0xFF374151);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Text(
        productType.toUpperCase(),
        style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF0284C7)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0369A1),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildMetaRow(String label, String value, {bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isError ? Colors.red : AppTheme.textColor,
                fontSize: 12,
                fontWeight: isError ? FontWeight.bold : FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorCard(dynamic sensor) {
    final sensorId = sensor['sensorId']?.toString() ?? 'S_UNKNOWN';
    final sensorName = sensor['sensorName']?.toString() ?? 'Generic Sensor';
    final sensorType = sensor['sensorType']?.toString() ?? 'Sensor';
    final manufacturer = sensor['manufacturer']?.toString() ?? 'N/A';
    final purpose = sensor['purpose']?.toString() ?? '';
    final health = sensor['health'] is Map ? sensor['health'] : {};
    final sensorStatus = health['status']?.toString() ?? 'ONLINE';
    final isOnline = sensorStatus.toUpperCase() == 'ONLINE';
    final parameters = sensor['parameters'] is List ? sensor['parameters'] : [];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sensor Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.sensors, color: Color(0xFF8B5CF6), size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            sensorName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            sensorId,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$sensorType • Mfg: $manufacturer',
                      style: const TextStyle(fontSize: 11, color: AppTheme.subtitleColor),
                    ),
                  ],
                ),
              ),
              // Sensor Health Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isOnline ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isOnline ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA)),
                ),
                child: Text(
                  sensorStatus,
                  style: TextStyle(
                    color: isOnline ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          // Purpose callout
          if (purpose.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline, size: 12, color: Color(0xFF0284C7)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Purpose: $purpose',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF334155), fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Parameters list
          if (parameters.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Telemetry Parameters:',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.subtitleColor),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: parameters.map<Widget>((p) {
                final displayName = p['displayName'] ?? p['parameterName'] ?? p['parameterId'] ?? 'Param';
                final pId = p['parameterId']?.toString() ?? '';
                final unit = p['unit']?.toString() ?? '';
                final minVal = p['minValue'];
                final maxVal = p['maxValue'];
                final dataType = p['dataType']?.toString() ?? 'numeric';

                String rangeText = '';
                if (minVal != null && maxVal != null) {
                  rangeText = ' ($minVal - $maxVal $unit)';
                } else if (unit.isNotEmpty) {
                  rangeText = ' ($unit)';
                }

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFDCFCE7)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$displayName [$pId]: ',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF166534)),
                      ),
                      Text(
                        '$dataType$rangeText',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF15803D)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  void _showAddDeviceModal(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final deviceIdCtrl = TextEditingController();
    final deviceNameCtrl = TextEditingController();
    final serialCtrl = TextEditingController();
    final hwVerCtrl = TextEditingController(text: '1.0');
    final fwVerCtrl = TextEditingController(text: '2.0.0');
    String selectedType = 'RECEIVER';

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.add_to_photos, color: Color(0xFF0284C7)),
                  SizedBox(width: 8),
                  Text('Register IoT Thing', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: deviceIdCtrl,
                        decoration: const InputDecoration(labelText: 'Device Code (e.g. RX-03)'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: deviceNameCtrl,
                        decoration: const InputDecoration(labelText: 'Device Name / Description'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: serialCtrl,
                        decoration: const InputDecoration(labelText: 'Serial Number (e.g. SN-RX-03)'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedType,
                        decoration: const InputDecoration(labelText: 'Product Type'),
                        items: ['RECEIVER', 'TRANSMITTER', 'REPEATER']
                            .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setModalState(() => selectedType = val);
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: hwVerCtrl,
                              decoration: const InputDecoration(labelText: 'HW Version'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: fwVerCtrl,
                              decoration: const InputDecoration(labelText: 'FW Version'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState?.validate() ?? false) {
                      Navigator.pop(dialogCtx);
                      final res = await ApiService.upsertDeviceRegistry({
                        'device_id': deviceIdCtrl.text.trim(),
                        'device_name': deviceNameCtrl.text.trim(),
                        'serial_number': serialCtrl.text.trim(),
                        'product_type': selectedType,
                        'hardware_version': hwVerCtrl.text.trim(),
                        'firmware_version': fwVerCtrl.text.trim(),
                        'sensors_config': [],
                        'health_status': 'ONLINE',
                      });
                      if (res['success']) {
                        _fetchRegistry();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Device registered in AWS IoT Registry!')),
                          );
                        }
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(res['message'] ?? 'Registration failed')),
                          );
                        }
                      }
                    }
                  },
                  child: const Text('Save to Registry'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
