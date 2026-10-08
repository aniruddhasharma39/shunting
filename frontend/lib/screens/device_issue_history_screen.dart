import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class DeviceIssueHistoryScreen extends StatefulWidget {
  const DeviceIssueHistoryScreen({super.key});

  @override
  State<DeviceIssueHistoryScreen> createState() => _DeviceIssueHistoryScreenState();
}

class _DeviceIssueHistoryScreenState extends State<DeviceIssueHistoryScreen> {
  bool _isLoading = true;
  List<dynamic> _history = [];
  
  // Filters
  DateTime? _startDate;
  DateTime? _endDate;
  List<String> _allDevices = [];
  List<String> _selectedDevices = [];
  String _searchQuery = '';
  String _selectedIssueType = 'All Issues';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    
    // Fetch unique device codes for the filter dropdown
    final devicesResult = await ApiService.fetchDevices();
    if (devicesResult['success']) {
      final devices = devicesResult['data'] as List<dynamic>;
      _allDevices = devices.map((d) => (d['device_code'] ?? d['device_id']).toString()).toSet().toList();
      _allDevices.sort();
    }
    
    await _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() => _isLoading = true);
    
    String? startStr = _startDate != null ? "${_startDate!.toIso8601String().split('T')[0]} 00:00:00" : null;
    String? endStr = _endDate != null ? "${_endDate!.toIso8601String().split('T')[0]} 23:59:59" : null;

    final result = await ApiService.fetchDeviceAssignments(
      startDate: startStr,
      endDate: endStr,
      devices: _selectedDevices.isNotEmpty ? _selectedDevices : null
    );
    
    if (mounted) {
      if (result['success']) {
        _history = result['data'] as List<dynamic>;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'])));
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _startDate != null && _endDate != null 
          ? DateTimeRange(start: _startDate!, end: _endDate!) 
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryColor,
              onPrimary: Colors.white,
              onSurface: AppTheme.primaryColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchHistory();
    }
  }

  void _showDeviceFilter() {
    // Create a temporary copy for the modal state
    List<String> tempSelected = List.from(_selectedDevices);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Filter by Devices', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                      TextButton(
                        onPressed: () {
                          setModalState(() => tempSelected.clear());
                        },
                        child: const Text('Clear All'),
                      )
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: _allDevices.length,
                    itemBuilder: (context, index) {
                      final device = _allDevices[index];
                      final isSelected = tempSelected.contains(device);
                      return CheckboxListTile(
                        title: Text(device),
                        value: isSelected,
                        activeColor: AppTheme.primaryColor,
                        onChanged: (val) {
                          setModalState(() {
                            if (val == true) {
                              tempSelected.add(device);
                            } else {
                              tempSelected.remove(device);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedDevices = List.from(tempSelected);
                        });
                        Navigator.pop(context);
                        _fetchHistory();
                      },
                      child: const Text('Save & Apply', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            );
          }
        );
      }
    );
  }

  void _downloadPdf() async {
    String? startStr = _startDate != null ? "${_startDate!.toIso8601String().split('T')[0]} 00:00:00" : null;
    String? endStr = _endDate != null ? "${_endDate!.toIso8601String().split('T')[0]} 23:59:59" : null;
    
    final url = ApiService.getDeviceHistoryPdfUrl(
      startDate: startStr,
      endDate: endStr,
      devices: _selectedDevices.isNotEmpty ? _selectedDevices : null
    );
    
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open PDF report')));
    }
  }

  void _downloadExcel() async {
    String? startStr = _startDate != null ? "${_startDate!.toIso8601String().split('T')[0]} 00:00:00" : null;
    String? endStr = _endDate != null ? "${_endDate!.toIso8601String().split('T')[0]} 23:59:59" : null;
    
    final url = ApiService.getDeviceHistoryExcelUrl(
      startDate: startStr,
      endDate: endStr,
      devices: _selectedDevices.isNotEmpty ? _selectedDevices : null
    );
    
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open Excel report')));
    }
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null) return '--:--';
    try {
      final date = DateTime.parse(isoString).toLocal();
      return "${date.day}/${date.month.toString().padLeft(2, '0')}/${date.year} "
             "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return "--:--";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Accountability Report', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.table_chart),
            tooltip: 'Download Excel',
            onPressed: _downloadExcel,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Download PDF',
            onPressed: _downloadPdf,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search Name, Mobile, Device, Date...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _selectedIssueType,
                        decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                        items: ['All Issues', 'Registered Issues', 'Unregistered Issues']
                            .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 12))))
                            .toList(),
                        onChanged: (val) => setState(() => _selectedIssueType = val!),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        onPressed: _selectDateRange,
                        icon: const Icon(Icons.calendar_month, size: 18),
                        label: Text(
                          _startDate == null 
                            ? 'All Dates' 
                            : '${_startDate!.day}/${_startDate!.month} - ${_endDate!.day}/${_endDate!.month}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryColor,
                          side: const BorderSide(color: AppTheme.borderColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        onPressed: _showDeviceFilter,
                        icon: const Icon(Icons.devices, size: 18),
                        label: Text(
                          _selectedDevices.isEmpty ? 'All Devices' : '${_selectedDevices.length} Selected',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryColor,
                          side: const BorderSide(color: AppTheme.borderColor),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Builder(builder: (context) {
                    List<dynamic> filteredHistory = _history.where((record) {
                      if (_selectedIssueType == 'Registered Issues' && record['issue_type'] == 'UNREGISTERED') return false;
                      if (_selectedIssueType == 'Unregistered Issues' && record['issue_type'] != 'UNREGISTERED') return false;
                      
                      if (_searchQuery.isNotEmpty) {
                        final query = _searchQuery.toLowerCase();
                        final name = (record['employee_name'] ?? '').toString().toLowerCase();
                        final mobile = (record['employee_code'] ?? '').toString().toLowerCase();
                        final device = (record['device_code'] ?? '').toString().toLowerCase();
                        final date = (record['issued_at'] ?? '').toString().toLowerCase();
                        
                        if (!name.contains(query) && !mobile.contains(query) && !device.contains(query) && !date.contains(query)) {
                          return false;
                        }
                      }
                      return true;
                    }).toList();

                    if (filteredHistory.isEmpty) {
                      return const Center(child: Text('No issue/return records found.', style: TextStyle(color: AppTheme.subtitleColor)));
                    }
                    
                    return ListView.builder(
                        padding: const EdgeInsets.all(16.0),
                        itemCount: filteredHistory.length,
                        itemBuilder: (context, index) {
                          final record = filteredHistory[index];
                          final isReturned = record['returned_at'] != null;

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
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.train, 
                                            color: isReturned ? AppTheme.subtitleColor : AppTheme.primaryColor,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            record['device_code'] ?? 'Unknown Device', 
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold, 
                                              fontSize: 16, 
                                              color: isReturned ? Colors.black87 : AppTheme.primaryColor
                                            ),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isReturned ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          isReturned ? 'RETURNED' : 'ISSUED',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isReturned ? Colors.green : Colors.orange,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 24),
                                  
                                  // User Info
                                  Row(
                                    children: [
                                      const Icon(Icons.person_outline, size: 16, color: AppTheme.subtitleColor),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          "${record['employee_name'] ?? 'Unknown'} (${record['employee_code'] ?? 'N/A'})", 
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  
                                  // Timestamps
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Issued At', style: TextStyle(fontSize: 11, color: AppTheme.subtitleColor)),
                                            const SizedBox(height: 2),
                                            Text(_formatDateTime(record['issued_at']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Returned At', style: TextStyle(fontSize: 11, color: AppTheme.subtitleColor)),
                                            const SizedBox(height: 2),
                                            Text(_formatDateTime(record['returned_at']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  
                                  // Remarks
                                  if (record['remarks'] != null && record['remarks'].toString().isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text("Remarks: ${record['remarks']}", style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                                    ),
                                  ],
                                  
                                  // Defect Reason
                                  if (record['fault_reported'] != null && record['fault_reported'].toString().isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        border: Border.all(color: Colors.red.shade200),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text("Defect Reason: ${record['fault_reported']}", style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      );
                  }),
          ),
        ],
      ),
    );
  }
}
