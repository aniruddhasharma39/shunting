import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import '../services/api_service.dart';

class IssueReturnScreen extends StatefulWidget {
  const IssueReturnScreen({super.key});

  @override
  State<IssueReturnScreen> createState() => _IssueReturnScreenState();
}

class _IssueReturnScreenState extends State<IssueReturnScreen> {
  bool _isLoading = true;
  List<dynamic> _availableLDs = [];
  List<dynamic> _activeSessions = [];
  List<dynamic> _locoPilots = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);

    final devicesResult = await ApiService.fetchDevices();
    final usersResult = await ApiService.fetchUsers();
    final sessionsResult = await ApiService.fetchSessions(status: 'live');

    if (mounted) {
      if (devicesResult['success']) {
        final allDevices = devicesResult['data'] as List<dynamic>;
        // Filter for Receivers / Loco Units
        _availableLDs = allDevices.where((d) {
          final type = (d['device_type'] ?? d['product_type'] ?? '').toString().toUpperCase();
          final pType = (d['product_type'] ?? '').toString().toUpperCase();
          final code = (d['device_code'] ?? d['device_id'] ?? '').toString().toUpperCase();
          final isReceiver = type.contains('RECEIVER') || type.contains('LOCO') || pType.contains('RECEIVER') || code.startsWith('RX') || code.startsWith('LD') || code.contains('RECEIVER');
          return isReceiver;
        }).toList();
      }
      
      if (usersResult['success']) {
        final allUsers = usersResult['data'] as List<dynamic>;
        _locoPilots = allUsers.where((u) => u['role'] == 'viewer' || u['role'] == 'yard_admin' || u['role'] == 'maintenance_user' || u['role'] == 'hardware_engineer').toList();
      }

      if (sessionsResult['success']) {
        _activeSessions = sessionsResult['data'] as List<dynamic>;
        
        // Filter out available LDs that are already in active sessions
        final activeLDCodes = _activeSessions.map((s) => s['ldDevice']?.toString()).where((c) => c != null).toSet();
        _availableLDs.removeWhere((d) => activeLDCodes.contains(d['device_code']?.toString()) || activeLDCodes.contains(d['device_id']?.toString()));
      }

      setState(() => _isLoading = false);
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
          title: const Text('Issue / Return Devices', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
              Tab(icon: Icon(Icons.outbox), text: 'ISSUE DEVICE'),
              Tab(icon: Icon(Icons.move_to_inbox), text: 'RETURN DEVICE'),
            ],
          ),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchData)
          ],
        ),
        body: _isLoading 
            ? const Center(child: CircularProgressIndicator()) 
            : TabBarView(
                children: [
                  _buildIssueTab(),
                  _buildReturnTab(),
                ],
              ),
      ),
    );
  }

  Widget _buildIssueTab() {
    String? selectedDeviceId;
    String? selectedUserId;
    final remarksController = TextEditingController();
    bool isSubmitting = false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: StatefulBuilder(
        builder: (tabCtx, setTabState) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Issue Loco Unit to Pilot', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
              const SizedBox(height: 8),
              const Text('Select an available LD unit and assign it to a shunter or loco pilot for the shift.', style: TextStyle(color: AppTheme.subtitleColor)),
              const SizedBox(height: 24),
              
              _buildDropdownLabel('Select Available Loco Unit (Receiver)'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.borderColor)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: (selectedDeviceId != null && _availableLDs.any((d) => d['id'].toString() == selectedDeviceId)) ? selectedDeviceId : null,
                    hint: const Text('Select a Loco Unit (Receiver)'),
                    items: _availableLDs.map((d) {
                      final code = d['device_code'] ?? d['device_id'] ?? 'LD';
                      final type = d['device_type'] ?? 'Loco Unit';
                      final batt = d['battery_level'] ?? '95%';
                      final status = d['network_status'] ?? 'Online';
                      return DropdownMenuItem<String>(
                        value: d['id'].toString(),
                        child: Row(
                          children: [
                            const Icon(Icons.train, size: 18, color: AppTheme.primaryColor),
                            const SizedBox(width: 8),
                            Text('$code ($type)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('🔋 $batt • $status', style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setTabState(() => selectedDeviceId = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              _buildDropdownLabel('Select Employee (Loco Pilot / Shunter)'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.borderColor)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: (selectedUserId != null && _locoPilots.any((u) => u['id'].toString() == selectedUserId)) ? selectedUserId : null,
                    hint: const Text('Select a Loco Pilot'),
                    items: _locoPilots.map((u) {
                      final name = u['fullName'] ?? u['full_name'] ?? 'User';
                      final empId = u['employeeId'] ?? u['employee_id'] ?? 'EMP';
                      final desig = u['designation'] ?? 'Loco Pilot';
                      return DropdownMenuItem<String>(
                        value: u['id'].toString(),
                        child: Row(
                          children: [
                            const Icon(Icons.person, size: 18, color: Colors.blueGrey),
                            const SizedBox(width: 8),
                            Text('$name ($empId)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const Spacer(),
                            Text(desig, style: const TextStyle(fontSize: 12, color: AppTheme.subtitleColor)),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setTabState(() => selectedUserId = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              _buildDropdownLabel('Remarks (Optional)'),
              TextField(
                controller: remarksController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Enter any remarks or conditions...',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.borderColor)),
                ),
              ),
              const SizedBox(height: 32),
              
              ElevatedButton.icon(
                onPressed: isSubmitting || selectedDeviceId == null || selectedUserId == null ? null : () async {
                  setTabState(() => isSubmitting = true);
                  final result = await ApiService.issueDevice(selectedDeviceId!, selectedUserId!, remarksController.text);
                  
                  if (mounted) {
                     if (result['success']) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device Issued successfully!')));
                        _fetchData(); // Reset form and data
                     } else {
                        setTabState(() => isSubmitting = false);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'])));
                     }
                  }
                },
                icon: isSubmitting ? const SizedBox() : const Icon(Icons.outbox, color: Colors.white),
                label: isSubmitting 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('ISSUE DEVICE', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          );
        }
      ),
    );
  }

  Widget _buildReturnTab() {
    if (_activeSessions.isEmpty) {
       return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 100),
          Center(child: Text('No active device assignments to return.', style: TextStyle(color: AppTheme.subtitleColor)))
        ],
      );
    }
    
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      itemCount: _activeSessions.length,
      itemBuilder: (context, index) {
        final session = _activeSessions[index];
        
        return Card(
          margin: const EdgeInsets.only(bottom: 16.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                        const Icon(Icons.train, color: AppTheme.primaryColor),
                        const SizedBox(width: 8),
                        Text(session['ldDevice'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryColor)),
                      ],
                    ),
                    Flexible(
                      child: Text(
                        "SES-${session['id'].toString().length > 8 ? session['id'].toString().substring(0, 8) : session['id']}", 
                        style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
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
                        const Text('Issued To', style: TextStyle(fontSize: 12, color: AppTheme.subtitleColor)),
                        Text(session['holder'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Issued At', style: TextStyle(fontSize: 12, color: AppTheme.subtitleColor)),
                        Text(_formatTime(session['startTime']), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _showReturnDialog(session),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.primaryColor,
                      side: const BorderSide(color: AppTheme.primaryColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('PROCESS RETURN', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showReturnDialog(dynamic session) {
    final remarksController = TextEditingController();
    bool isSubmitting = false;
    
    // We need the device_id to return it. Since session only gives device_code, we need to map it.
    // However, the backend return API takes `device_id`.
    // Let's modify ApiService.returnDevice to take device_code, OR we can look up the ID from _availableLDs. 
    // Actually _availableLDs doesn't have it because it's issued. We should fetch all devices and find the ID.
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            title: Text("Return ${session['ldDevice']}?"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Process the return of this device and end the active shunting session.'),
                const SizedBox(height: 16),
                TextField(
                  controller: remarksController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Any remarks on condition? (Optional)',
                    filled: true,
                    fillColor: AppTheme.backgroundColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
              TextButton(
                onPressed: isSubmitting ? null : () async {
                  setDialogState(() => isSubmitting = true);
                  
                  final result = await ApiService.returnDevice(session['id'].toString(), remarksController.text);
                  if (mounted) {
                     if (result['success']) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device Returned Successfully!')));
                        _fetchData();
                     } else {
                        setDialogState(() => isSubmitting = false);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'])));
                     }
                  }
                },
                child: isSubmitting
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('RETURN', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
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

  Widget _buildDropdownLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryColor)),
    );
  }
}
