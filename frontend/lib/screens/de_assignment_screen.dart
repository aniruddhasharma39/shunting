import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import '../services/api_service.dart';

class DEAssignmentScreen extends StatefulWidget {
  const DEAssignmentScreen({super.key});

  @override
  State<DEAssignmentScreen> createState() => _DEAssignmentScreenState();
}

class _DEAssignmentScreenState extends State<DEAssignmentScreen> {
  bool _isLoading = true;
  List<dynamic> _lines = [];
  List<dynamic> _unassignedDeadEnds = [];
  List<dynamic> _devices = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);

    final yardsResult = await ApiService.fetchYards();
    final devicesResult = await ApiService.fetchDevices();

    if (mounted) {
      if (yardsResult['success']) {
        final yards = yardsResult['data'] as List<dynamic>;
        
        // Flatten yards and lines into a single list of lines with yard info attached
        _lines = [];
        for (var yard in yards) {
          final yardLines = yard['lines'] as List<dynamic>;
          for (var line in yardLines) {
            _lines.add({
               ...line,
               'yard_name': yard['yard_name']
            });
          }
        }
      }

      if (devicesResult['success']) {
        _devices = devicesResult['data'] as List<dynamic>;
        _unassignedDeadEnds = _devices.where((d) {
          final type = (d['device_type'] ?? d['product_type'] ?? '').toString().toUpperCase();
          final pType = (d['product_type'] ?? '').toString().toUpperCase();
          final code = (d['device_code'] ?? d['device_id'] ?? '').toString().toUpperCase();
          final isDeadEnd = type.contains('DEAD') || type.contains('TRANSMITTER') || pType.contains('TRANSMITTER') || code.startsWith('TX') || code.startsWith('DE') || code.contains('TRANSMITTER');
          final isUnassigned = d['assigned_line_id'] == null || d['assigned_line_id'].toString().trim().isEmpty;
          return isDeadEnd && isUnassigned;
        }).toList();
      }

      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('DE Assignments', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
        elevation: 4,
        shadowColor: Colors.black54,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchData)
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _fetchData, child: _buildAssignmentList()),
    );
  }

  Widget _buildAssignmentList() {
    if (_lines.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 100),
          Center(child: Text('No lines configured in any yard.', style: TextStyle(color: AppTheme.subtitleColor)))
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      itemCount: _lines.length,
      itemBuilder: (context, index) {
        final Map<String, dynamic> item = Map<String, dynamic>.from(_lines[index]);
        final String yard = item['yard_name'] ?? 'Unknown Yard';
        final String line = item['line_name'] ?? 'Unknown Line';
        final String deviceCode = item['assigned_de'] ?? 'None';
        
        final bool isAssigned = deviceCode != 'None';
        
        // Find device status if assigned
        String status = 'Offline';
        String lastPing = '-';
        if (isAssigned) {
           final dev = _devices.firstWhere((d) => d['device_code'] == deviceCode, orElse: () => null);
           if (dev != null) {
              status = dev['network_status'] ?? 'Unknown';
              lastPing = dev['last_heartbeat'] != null ? _formatDate(dev['last_heartbeat']) : '-';
           }
        }
        
        final bool isOnline = status == 'Online';

        Color badgeBgColor = Colors.grey;
        if (isAssigned) {
          badgeBgColor = isOnline ? Colors.green : Colors.red;
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$yard • $line', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryColor)),
                    if (isAssigned)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: badgeBgColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          status,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const SizedBox(width: 8),
                    Text(
                      isAssigned ? 'Assigned: $deviceCode' : 'No device assigned',
                      style: TextStyle(
                        fontSize: 14,
                        color: isAssigned ? AppTheme.primaryColor : AppTheme.subtitleColor,
                        fontWeight: isAssigned ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                if (isAssigned)
                  Padding(
                    padding: const EdgeInsets.only(left: 28.0, top: 4.0),
                    child: Text('Last Heartbeat: $lastPing', style: const TextStyle(fontSize: 12, color: AppTheme.subtitleColor)),
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isAssigned)
                      InkWell(
                        onTap: () => _handleUnassign(item),
                        child: const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text('UNASSIGN', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    const SizedBox(width: 16),
                    InkWell(
                      onTap: () => _showAssignForm(item),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(isAssigned ? 'REPLACE' : 'ASSIGN', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDate(String isoString) {
    try {
      final date = DateTime.parse(isoString).toLocal();
      return "${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return "Invalid date";
    }
  }

  void _handleUnassign(Map<String, dynamic> item) {
    final dev = _devices.firstWhere((d) => d['device_code'] == item['assigned_de'], orElse: () => null);
    if (dev == null) return;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Assignment?'),
        content: Text("Are you sure you want to unassign ${item['assigned_de']} from ${item['line_name']}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              
              showDialog(
                context: context, barrierDismissible: false,
                builder: (context) => const Center(child: CircularProgressIndicator())
              );
              
              final result = await ApiService.assignDeviceToLine(dev['id'].toString(), null);
              
              if (mounted) {
                 Navigator.pop(context); // close loading
                 if (result['success']) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device Unassigned successfully!')));
                    _fetchData();
                 } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'])));
                 }
              }
            },
            child: const Text('UNASSIGN', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAssignForm(Map<String, dynamic> item) {
    final String lineName = item['line_name']?.toString() ?? 'Unknown Line';
    String? selectedDeviceId;
    bool isSubmitting = false;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          return Material(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Container(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Assign Device to $lineName', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text('Select Available Dead-End Device', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.subtitleColor)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(color: AppTheme.backgroundColor, borderRadius: BorderRadius.circular(8)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: (selectedDeviceId != null && _unassignedDeadEnds.any((d) => d['id'].toString() == selectedDeviceId)) ? selectedDeviceId : null,
                        hint: const Text('Select a device'),
                        items: _unassignedDeadEnds.map((d) {
                          return DropdownMenuItem<String>(value: d['id'].toString(), child: Text(d['device_code']));
                        }).toList(),
                        onChanged: (val) {
                           setModalState(() => selectedDeviceId = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSubmitting || selectedDeviceId == null ? null : () async {
                        setModalState(() => isSubmitting = true);
                        final result = await ApiService.assignDeviceToLine(selectedDeviceId!, item['id'].toString());
                        
                        if (mounted) {
                           if (result['success']) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Device Assigned to $lineName!')));
                              _fetchData();
                           } else {
                              setModalState(() => isSubmitting = false);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'])));
                           }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isSubmitting
                       ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                       : const Text('CONFIRM ASSIGNMENT', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      ),
    );
  }
}
