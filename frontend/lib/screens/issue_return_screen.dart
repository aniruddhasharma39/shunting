import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import '../services/api_service.dart';
import '../services/user_session.dart';
import 'device_issue_history_screen.dart';
import 'package:image_picker/image_picker.dart';

class IssueReturnScreen extends StatefulWidget {
  final int initialIndex;
  const IssueReturnScreen({super.key, this.initialIndex = 0});

  @override
  State<IssueReturnScreen> createState() => _IssueReturnScreenState();
}

class _IssueReturnScreenState extends State<IssueReturnScreen> {
  bool _isLoading = true;
  List<dynamic> _availableLDs = [];
  List<dynamic> _activeAssignments = [];
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

    if (mounted) {
      if (devicesResult['success']) {
        final allDevices = devicesResult['data'] as List<dynamic>;
        
        // Populate active sessions from issued devices directly!
        final userSession = UserSession();
        _activeAssignments = allDevices.where((d) {
          if (d['is_issued'] != true) return false;
          if (userSession.isShunter) {
            final holderName = d['active_holder_name']?.toString();
            final holderId = d['active_holder_employee_id']?.toString();
            if (holderId != userSession.employeeId && holderName != userSession.fullName) {
              return false;
            }
          }
          return true;
        }).map((d) {
          return {
            'id': d['active_assignment_id'],
            'ldDevice': d['device_code'] ?? d['device_id'],
            'holder': d['active_holder_name'] ?? d['active_holder_employee_id'] ?? 'Unknown Employee',
            'holderId': d['active_holder_employee_id'],
            'startTime': d['active_issued_at'],
            'issueType': d['issue_type'] ?? 'REGISTERED',
            'userPhoto': d['user_photo_url'],
            'idCardPhoto': d['id_card_photo_url'],
          };
        }).toList();

        // Filter for available Receivers / Loco Units
        _availableLDs = allDevices.where((d) {
          final type = (d['device_type'] ?? d['product_type'] ?? '').toString().toUpperCase();
          final pType = (d['product_type'] ?? '').toString().toUpperCase();
          final code = (d['device_code'] ?? d['device_id'] ?? '').toString().toUpperCase();
          final isReceiver = type.contains('RECEIVER') || type.contains('LOCO') || pType.contains('RECEIVER') || code.startsWith('RX') || code.startsWith('LD') || code.contains('RECEIVER');
          
          return isReceiver && d['is_issued'] != true;
        }).toList();
      }
      
      if (usersResult['success']) {
        final allUsers = usersResult['data'] as List<dynamic>;
        _locoPilots = allUsers.where((u) => ['loco_pilot', 'shunter', 'supervisor'].contains(u['role'])).toList();
      }

      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userSession = UserSession();

    if (userSession.isShunter) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        drawer: const AppDrawer(),
        appBar: AppBar(
          title: const Text('My Devices', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
              icon: const Icon(Icons.history),
              tooltip: 'Device History',
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const DeviceIssueHistoryScreen()));
              },
            ),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchData)
          ],
        ),
        body: _isLoading 
            ? const Center(child: CircularProgressIndicator()) 
            : _buildReturnTab(),
      );
    }

    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialIndex,
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
              Tab(icon: Icon(Icons.person), text: 'REGISTERED ISSUE'),
              Tab(icon: Icon(Icons.person_add), text: 'UNREGISTERED ISSUE'),
              Tab(icon: Icon(Icons.move_to_inbox), text: 'RETURN DEVICE'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Issue/Return History',
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const DeviceIssueHistoryScreen()));
              },
            ),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchData)
          ],
        ),
        body: _isLoading 
            ? const Center(child: CircularProgressIndicator()) 
            : TabBarView(
                children: [
                  _buildIssueTab(),
                  _buildUnregisteredIssueTab(),
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
                    itemHeight: 70.0,
                    value: (selectedDeviceId != null && _availableLDs.any((d) => d['id'].toString() == selectedDeviceId)) ? selectedDeviceId : null,
                    hint: const Text('Select a Loco Unit (Receiver)'),
                    items: _availableLDs.map((d) {
                      String lastSeen = 'Never';
                      final lastTs = d['last_reading_timestamp'] ?? d['last_heartbeat'];
                      if (lastTs != null) {
                        try {
                          final dt = DateTime.parse(lastTs.toString()).toLocal();
                          lastSeen = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                        } catch (_) {}
                      }
                      final code = d['device_code'] ?? d['device_id'] ?? 'LD';
                      final type = d['device_type'] ?? 'Loco Unit';
                      final status = d['health_status'] ?? d['network_status'] ?? 'Online';
                      
                      return DropdownMenuItem<String>(
                        value: d['id'].toString(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.train, size: 18, color: AppTheme.primaryColor),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text('$code ($type)', 
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), 
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(status, style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text("Last seen: $lastSeen", style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
                            Expanded(
                              flex: 3,
                              child: Text('$name ($empId)', 
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: Text(desig, 
                                style: const TextStyle(fontSize: 12, color: AppTheme.subtitleColor),
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                              ),
                            ),
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

  String? _unregSelectedDeviceId;
  final _unregFullNameController = TextEditingController();
  final _unregMobileController = TextEditingController();
  XFile? _unregUserPhoto;
  XFile? _unregIdCardPhoto;
  bool _unregIsSubmitting = false;

  Widget _buildUnregisteredIssueTab() {

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: StatefulBuilder(
        builder: (tabCtx, setTabState) {
          Future<void> captureUserPhoto() async {
            final ImagePicker picker = ImagePicker();
            final XFile? photo = await picker.pickImage(source: ImageSource.camera);
            if (photo != null) {
              setTabState(() => _unregUserPhoto = photo);
            }
          }

          Future<void> captureIdCardPhoto() async {
            final ImagePicker picker = ImagePicker();
            final XFile? photo = await picker.pickImage(source: ImageSource.camera);
            if (photo != null) {
              setTabState(() => _unregIdCardPhoto = photo);
            }
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Issue to Unregistered Personnel', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
              const SizedBox(height: 8),
              const Text('Issue device to staff without registered accounts. Camera captures are mandatory for accountability.', style: TextStyle(color: AppTheme.subtitleColor)),
              const SizedBox(height: 24),
              
              _buildDropdownLabel('Full Name'),
              TextField(
                controller: _unregFullNameController,
                decoration: InputDecoration(
                  hintText: 'Enter Full Name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),

              _buildDropdownLabel('Mobile Number'),
              TextField(
                controller: _unregMobileController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: 'Enter 10-digit Mobile Number',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              
              _buildDropdownLabel('Select Available Loco Unit'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.borderColor)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    itemHeight: 60.0,
                    value: (_unregSelectedDeviceId != null && _availableLDs.any((d) => d['id'].toString() == _unregSelectedDeviceId)) ? _unregSelectedDeviceId : null,
                    hint: const Text('Select Device'),
                    items: _availableLDs.map((d) {
                      return DropdownMenuItem<String>(
                        value: d['id'].toString(),
                        child: Text('${d['device_code'] ?? d['device_id']} - ${d['battery_level'] ?? '--'}% Bat'),
                      );
                    }).toList(),
                    onChanged: (val) => setTabState(() => _unregSelectedDeviceId = val),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              _buildDropdownLabel('User Photograph'),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: captureUserPhoto,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Capture User Photo'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (_unregUserPhoto != null) const Icon(Icons.check_circle, color: Colors.green),
                ],
              ),
              const SizedBox(height: 16),

              _buildDropdownLabel('Railway ID Card Photograph'),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: captureIdCardPhoto,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Capture ID Card Photo'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (_unregIdCardPhoto != null) const Icon(Icons.check_circle, color: Colors.green),
                ],
              ),
              const SizedBox(height: 32),

              SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                  onPressed: _unregIsSubmitting ? null : () async {
                    if (_unregFullNameController.text.length < 3 || _unregMobileController.text.length < 10 || _unregSelectedDeviceId == null || _unregUserPhoto == null || _unregIdCardPhoto == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields and capture both photos')));
                      return;
                    }

                    setTabState(() => _unregIsSubmitting = true);
                    
                    final res = await ApiService.issueDeviceToUnregistered(
                      deviceId: _unregSelectedDeviceId!,
                      fullName: _unregFullNameController.text.trim(),
                      mobileNumber: _unregMobileController.text.trim(),
                      userPhoto: _unregUserPhoto!,
                      idCardPhoto: _unregIdCardPhoto!,
                    );

                    setTabState(() => _unregIsSubmitting = false);

                    if (res['success']) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device issued successfully!')));
                      _fetchData();
                      _unregFullNameController.clear();
                      _unregMobileController.clear();
                      setTabState(() {
                        _unregSelectedDeviceId = null;
                        _unregUserPhoto = null;
                        _unregIdCardPhoto = null;
                      });
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'])));
                    }
                  },
                  child: _unregIsSubmitting 
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('ISSUE DEVICE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          );
        }
      )
    );
  }

  Widget _buildReturnTab() {
    if (_activeAssignments.isEmpty) {
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
      itemCount: _activeAssignments.length,
      itemBuilder: (context, index) {
        final assignment = _activeAssignments[index];
        
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
                        Text(assignment['ldDevice'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryColor)),
                      ],
                    ),
                    Flexible(
                      child: Text(
                        "ASN-${assignment['id'].toString().length > 8 ? assignment['id'].toString().substring(0, 8) : assignment['id']}", 
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
                        Text(assignment['holder'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Issued At', style: TextStyle(fontSize: 12, color: AppTheme.subtitleColor)),
                        Text(_formatTime(assignment['startTime']), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (!UserSession().isShunter)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _showReturnDialog(assignment),
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

  void _showReturnDialog(dynamic assignment) {
    final remarksController = TextEditingController();
    final faultController = TextEditingController();
    bool isSubmitting = false;
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            title: Text("Return ${assignment['ldDevice']}?"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (assignment['issueType'] == 'UNREGISTERED') ...[
                    const Text('Unregistered User Details', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                    const SizedBox(height: 8),
                    Text('Name: ${assignment['holder']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Mobile: ${assignment['holderId']}'),
                    const SizedBox(height: 12),
                    if (assignment['userPhoto'] != null && assignment['userPhoto'].toString().isNotEmpty)
                      Column(
                        children: [
                          const Text('User Photo', style: TextStyle(fontSize: 12)),
                          const SizedBox(height: 4),
                          Image.network(assignment['userPhoto'], height: 80, fit: BoxFit.cover),
                          const SizedBox(height: 8),
                        ],
                      ),
                    if (assignment['idCardPhoto'] != null && assignment['idCardPhoto'].toString().isNotEmpty)
                      Column(
                        children: [
                          const Text('ID Card Photo', style: TextStyle(fontSize: 12)),
                          const SizedBox(height: 4),
                          Image.network(assignment['idCardPhoto'], height: 80, fit: BoxFit.cover),
                          const SizedBox(height: 16),
                        ],
                      ),
                    const Divider(),
                  ],
                  const Text('Process the return of this device.'),
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
                const SizedBox(height: 16),
                TextField(
                  controller: faultController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Reason for defect (if any)',
                    filled: true,
                    fillColor: AppTheme.backgroundColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
          actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
              TextButton(
                onPressed: isSubmitting ? null : () async {
                  setDialogState(() => isSubmitting = true);
                  
                  final result = await ApiService.returnDevice(
                    assignment['id'].toString(), 
                    remarksController.text, 
                    faultReported: faultController.text,
                  );
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
