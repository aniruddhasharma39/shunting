import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import '../services/api_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _selectedTime = 'Daily';
  String _selectedReportType = 'Daily Shunting';
  bool _isLoading = false;
  bool _hasRunReport = false;
  
  List<dynamic> _results = [];
  List<dynamic> _yards = [];
  List<dynamic> _employees = [];
  String? _selectedYardId;
  String? _selectedLineId;
  String? _selectedEmployeeId;

  @override
  void initState() {
    super.initState();
    _fetchFilterData();
  }

  Future<void> _fetchFilterData() async {
    final yardsRes = await ApiService.fetchYards();
    if (yardsRes['success']) {
      setState(() {
        _yards = yardsRes['data'];
      });
    }
    final usersRes = await ApiService.fetchUsers();
    if (usersRes['success']) {
      setState(() {
        _employees = usersRes['data'];
      });
    }
  }

  final List<String> _timeTabs = ['Daily', 'Weekly', 'Monthly'];
  final List<String> _reportTypes = [
    'Daily Shunting',
    'Device Inventory',
    'Employee Device Usage',
    'Device Health',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      drawer: const AppDrawer(),
      appBar: AppBar(
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
        title: const Text(
          'Reports & Audits',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTimeTabs(),
              const SizedBox(height: 16),
              _buildReportTypeSelector(),
              const SizedBox(height: 24),
              _buildFilterPanel(),
              const SizedBox(height: 24),
              _buildRunReportButton(),
              const SizedBox(height: 16),
              _buildActionBar(),
              const SizedBox(height: 32),
              _buildResultsList(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runReport() async {
    setState(() {
      _isLoading = true;
      _hasRunReport = false;
      _results = [];
    });

    if (_selectedReportType == 'Device Inventory' || _selectedReportType == 'Device Health') {
       final res = await ApiService.fetchDevices();
       if (res['success']) {
          _results = res['data'];
       }
    } else {
       final res = await ApiService.fetchSessions(status: 'history');
       if (res['success']) {
          _results = res['data'];
       }
       // Fetch live sessions as well
       final resLive = await ApiService.fetchSessions(status: 'live');
       if (resLive['success']) {
          _results.addAll(resLive['data']);
       }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _hasRunReport = true;
      });
    }
  }

  Widget _buildRunReportButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _runReport,
        icon: _isLoading 
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.analytics, color: Colors.white, size: 20),
        label: Text(
          _isLoading ? 'GENERATING...' : 'RUN REPORT',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 4,
        ),
      ),
    );
  }

  Widget _buildTimeTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: _timeTabs.map((tab) {
          final isSelected = tab == _selectedTime;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTime = tab),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  tab,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppTheme.subtitleColor,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildReportTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SELECT REPORT TYPE',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
            color: AppTheme.subtitleColor,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _selectedReportType,
              icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.subtitleColor),
              items: _reportTypes.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value, style: const TextStyle(fontSize: 14, color: AppTheme.primaryColor)),
                );
              }).toList(),
              onChanged: (newValue) {
                if (newValue != null) {
                  setState(() {
                     _selectedReportType = newValue;
                     _hasRunReport = false;
                  });
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  bool _showFilter(String filter) {
    if (filter == 'Yard') return true; 
    
    switch (_selectedReportType) {
      case 'Daily Shunting':
        return ['Line', 'Employee'].contains(filter);
      case 'Device Inventory':
        return ['Device Type', 'Device Health'].contains(filter);
      default:
        return false; 
    }
  }

  Map<String, String> _getDateRange() {
    final now = DateTime.now();
    DateTime fromDate;
    
    switch (_selectedTime) {
      case 'Daily':
        fromDate = now;
        break;
      case 'Weekly':
        fromDate = now.subtract(const Duration(days: 7));
        break;
      case 'Monthly':
        fromDate = now.subtract(const Duration(days: 30));
        break;
      default:
        fromDate = DateTime(2026, 7, 1);
    }
    
    String format(DateTime d) => "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
    return {
      'from': format(fromDate),
      'to': format(now),
    };
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
  }) {
    final bool isValueValid = value != null && items.any((i) => i.value == value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.subtitleColor)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          isExpanded: true,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.borderColor),
            ),
          ),
          initialValue: isValueValid ? value : null,
          icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: AppTheme.subtitleColor),
          items: items,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildFilterPanel() {
    List<Widget> activeFilters = [];
    
    if (_showFilter('Yard')) {
      activeFilters.add(_buildDropdown(
        label: 'Yard',
        value: _selectedYardId,
        items: _yards.map((y) => DropdownMenuItem<String>(
          value: y['id'].toString(),
          child: Text(y['yard_name'] ?? 'Unknown', style: const TextStyle(fontSize: 14, color: AppTheme.primaryColor)),
        )).toList(),
        onChanged: (val) {
          setState(() {
            _selectedYardId = val;
            _selectedLineId = null;
          });
        }
      ));
    }

    if (_showFilter('Employee')) {
      activeFilters.add(_buildDropdown(
        label: 'Employee',
        value: _selectedEmployeeId,
        items: _employees.map((e) => DropdownMenuItem<String>(
          value: e['id'].toString(),
          child: Text(e['name'] ?? 'Unknown', style: const TextStyle(fontSize: 14, color: AppTheme.primaryColor)),
        )).toList(),
        onChanged: (val) => setState(() => _selectedEmployeeId = val),
      ));
    }

    if (_showFilter('Device Type')) activeFilters.add(_buildFilterDropdown('Device Type', 'All Types'));

    if (_showFilter('Line')) {
      final selectedYard = _yards.firstWhere((y) => y['id'].toString() == _selectedYardId, orElse: () => null);
      final lines = (selectedYard != null && selectedYard['lines'] != null) ? (selectedYard['lines'] as List) : [];
      activeFilters.add(_buildDropdown(
        label: 'Line',
        value: _selectedLineId,
        items: lines.map((l) => DropdownMenuItem<String>(
          value: l['id'].toString(),
          child: Text(l['line_name'] ?? 'Unknown', style: const TextStyle(fontSize: 14, color: AppTheme.primaryColor)),
        )).toList(),
        onChanged: (val) => setState(() => _selectedLineId = val),
      ));
    }

    if (_showFilter('Device Health')) activeFilters.add(_buildFilterDropdown('Device Health', 'Any Status'));

    List<Widget> dynamicRows = [];
    for (int i = 0; i < activeFilters.length; i += 2) {
      if (i + 1 < activeFilters.length) {
        dynamicRows.add(
          Row(
            children: [
              Expanded(child: activeFilters[i]),
              const SizedBox(width: 16),
              Expanded(child: activeFilters[i + 1]),
            ],
          ),
        );
      } else {
        dynamicRows.add(
          Row(
            children: [
              Expanded(child: activeFilters[i]),
              const SizedBox(width: 16),
              const Expanded(child: SizedBox()),
            ],
          ),
        );
      }
      dynamicRows.add(const SizedBox(height: 16));
    }

    final dates = _getDateRange();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.tune, size: 20, color: AppTheme.subtitleColor),
              SizedBox(width: 8),
              Text(
                'DATE RANGE & FILTERS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.subtitleColor,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildFilterInput('From Date', dates['from']!)),
              const SizedBox(width: 16),
              Expanded(child: _buildFilterInput('To Date', dates['to']!)),
            ],
          ),
          const SizedBox(height: 16),
          ...dynamicRows,
        ],
      ),
    );
  }

  Widget _buildFilterInput(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.subtitleColor)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.borderColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(value, style: const TextStyle(fontSize: 14, color: AppTheme.primaryColor)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterDropdown(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.subtitleColor)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.borderColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(value, style: const TextStyle(fontSize: 14, color: AppTheme.primaryColor)),
              const Icon(Icons.keyboard_arrow_down, size: 16, color: AppTheme.subtitleColor),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _downloadReport(String format) async {
    try {
      final dates = _getDateRange();
      
      final yardName = _yards.firstWhere((y) => y['id'].toString() == _selectedYardId, orElse: () => null)?['yard_name'] ?? 'All Yards';
      
      final selectedYard = _yards.firstWhere((y) => y['id'].toString() == _selectedYardId, orElse: () => null);
      final lines = (selectedYard != null && selectedYard['lines'] != null) ? (selectedYard['lines'] as List) : [];
      final lineName = lines.firstWhere((l) => l['id'].toString() == _selectedLineId, orElse: () => null)?['line_name'] ?? 'All Lines';
      
      final employeeName = _employees.firstWhere((e) => e['id'].toString() == _selectedEmployeeId, orElse: () => null)?['name'] ?? 'All Employees';

      final filters = <String, String>{
        'Date Range': "${dates['from']} to ${dates['to']}",
        'Yard': yardName,
        'Line': lineName,
        'Employee': employeeName,
        'fromDate': dates['from']!,
        'toDate': dates['to']!,
      };
      
      if (_selectedYardId != null) filters['yardId'] = _selectedYardId!;
      if (_selectedLineId != null) filters['lineId'] = _selectedLineId!;
      if (_selectedEmployeeId != null) filters['employeeId'] = _selectedEmployeeId!;
      
      final queryParams = {
        'reportType': _selectedReportType,
        'filters': jsonEncode(filters),
      };
      
      final uri = Uri.parse('${ApiService.baseUrl.replaceAll('/api', '')}/api/reports/generate/$format').replace(queryParameters: queryParams);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not launch $format download. Make sure backend is running.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error downloading $format: $e')),
        );
      }
    }
  }

  Widget _buildActionBar() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: _hasRunReport ? () => _downloadReport('excel') : null,
            icon: Icon(Icons.table_chart, color: _hasRunReport ? Colors.greenAccent : Colors.grey, size: 18),
            label: Text('Excel', style: TextStyle(color: _hasRunReport ? Colors.white : Colors.grey, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _hasRunReport ? AppTheme.primaryColor : Colors.grey.shade300,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: _hasRunReport ? () => _downloadReport('pdf') : null,
            icon: Icon(Icons.picture_as_pdf, color: _hasRunReport ? Colors.redAccent : Colors.grey, size: 18),
            label: Text('PDF', style: TextStyle(color: _hasRunReport ? Colors.white : Colors.grey, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _hasRunReport ? AppTheme.primaryColor : Colors.grey.shade300,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsList() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_hasRunReport) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32.0),
          child: Column(
            children: [
              Icon(Icons.insert_chart_outlined, size: 64, color: AppTheme.subtitleColor.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              const Text(
                'No reports generated yet.',
                style: TextStyle(color: AppTheme.subtitleColor, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Select your filters above and click Run Report.',
                style: TextStyle(color: AppTheme.subtitleColor, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_results.length} RESULTS FOUND',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.subtitleColor, letterSpacing: 1.0),
        ),
        const SizedBox(height: 16),
        ..._results.map((item) {
           if (_selectedReportType == 'Device Inventory' || _selectedReportType == 'Device Health') {
              return _buildDeviceCard(item);
           } else {
              return _buildSessionCard(item);
           }
        }),
      ],
    );
  }

  Widget _buildDeviceCard(dynamic device) {
     return Container(
       margin: const EdgeInsets.only(bottom: 16.0),
       decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
       ),
       child: Padding(
         padding: const EdgeInsets.all(16.0),
         child: Column(
           children: [
             Row(
               mainAxisAlignment: MainAxisAlignment.spaceBetween,
               children: [
                 Text(device['device_code'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryColor)),
                 Container(
                   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                   decoration: BoxDecoration(
                     color: device['network_status'] == 'Online' ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                     borderRadius: BorderRadius.circular(12),
                   ),
                   child: Text(
                     (device['network_status'] ?? 'Unknown').toUpperCase(),
                     style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: device['network_status'] == 'Online' ? Colors.green : Colors.orange),
                   ),
                 ),
               ],
             ),
             const Divider(height: 24),
             Row(
               mainAxisAlignment: MainAxisAlignment.spaceBetween,
               children: [
                 Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     const Text('Type', style: TextStyle(fontSize: 12, color: AppTheme.subtitleColor)),
                     Text(device['device_type'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                   ],
                 ),
                 Column(
                   crossAxisAlignment: CrossAxisAlignment.end,
                   children: [
                     const Text('Condition', style: TextStyle(fontSize: 12, color: AppTheme.subtitleColor)),
                     Text(device['condition_status'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                   ],
                 ),
               ],
             )
           ],
         ),
       ),
     );
  }

  Widget _buildSessionCard(dynamic session) {
    Color statusColor = session['status'] == 'Warning' ? Colors.orange : (session['status'] == 'Completed' ? Colors.green : Colors.blueAccent);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {},
          child: Column(
            children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppTheme.backgroundColor,
              borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
              border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "${_formatDate(session['startTime'])} | SES-${session['id'].toString().length > 8 ? session['id'].toString().substring(0, 8) : session['id']}",
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    (session['status'] ?? 'UNKNOWN').toUpperCase(),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 100,
                  decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _buildInfoItem('YARD / LINE', "${session['yard']} / ${session['line']}")),
                          Expanded(child: _buildInfoItem('EMPLOYEE', session['holder'] ?? 'Unknown')),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _buildInfoItem('DEVICES', "${session['ldDevice']} / ${session['deDevice']}")),
                          Expanded(child: _buildInfoItem('START / END', "${_formatTime(session['startTime'])} - ${_formatTime(session['endTime'])}")),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.only(top: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildDistanceItem('FINAL DIST', session['distance'] ?? 'N/A'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    )));
  }

  String _formatDate(String? isoString) {
    if (isoString == null) return '--/--';
    try {
      final date = DateTime.parse(isoString).toLocal();
      return "${date.month}/${date.day}/${date.year}";
    } catch (e) {
      return "--/--";
    }
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

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.subtitleColor, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 14, color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildDistanceItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.subtitleColor, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 20, color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
