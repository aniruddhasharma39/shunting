import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import '../services/api_service.dart';

class YardSetupScreen extends StatefulWidget {
  const YardSetupScreen({super.key});

  @override
  State<YardSetupScreen> createState() => _YardSetupScreenState();
}

class _YardSetupScreenState extends State<YardSetupScreen> {
  bool _isLoading = true;
  List<dynamic> _yards = [];
  List<dynamic> _unassignedDeadEnds = [];

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
        setState(() {
          _yards = yardsResult['data'];
        });
      }
      
      if (devicesResult['success']) {
        final allDevices = devicesResult['data'] as List<dynamic>;
        _unassignedDeadEnds = allDevices.where((d) {
          final type = (d['device_type'] ?? d['product_type'] ?? '').toString().toUpperCase();
          final pType = (d['product_type'] ?? '').toString().toUpperCase();
          final code = (d['device_code'] ?? d['device_id'] ?? '').toString().toUpperCase();
          return type.contains('DEAD') || type.contains('TRANSMITTER') || pType.contains('TRANSMITTER') || code.startsWith('TX') || code.startsWith('DE') || code.contains('TRANSMITTER');
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
        title: const Text('Yard & Line Setup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
        shadowColor: Colors.black.withValues(alpha: 0.5),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchData)
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _fetchData, child: _buildYardList()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddMenu,
        backgroundColor: Colors.blueAccent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Create', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildYardList() {
    if (_yards.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 100),
          Center(child: Text('No yards configured yet.', style: TextStyle(color: AppTheme.subtitleColor)))
        ],
      );
    }
    
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      itemCount: _yards.length,
      itemBuilder: (context, index) {
        final yard = _yards[index];
        final List lines = yard['lines'] ?? [];
        
        return Card(
          margin: const EdgeInsets.only(bottom: 16.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            backgroundColor: Colors.white,
            collapsedBackgroundColor: Colors.white,
            title: Text(
              yard['yard_name'] ?? 'Unknown Yard',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.primaryColor),
            ),
            subtitle: Text("${yard['location'] ?? 'Unknown Location'} • ${yard['status']} • ${lines.length} Lines", style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 13)),
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFF1F5F9),
              child: Icon(Icons.factory, color: AppTheme.primaryColor),
            ),
            children: [
              Container(
                color: const Color(0xFFF8FAFC),
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('CONFIGURED LINES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.subtitleColor, letterSpacing: 1.0)),
                        TextButton.icon(
                          onPressed: () => _showLineForm(yard['id'].toString()),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Line'),
                          style: TextButton.styleFrom(foregroundColor: Colors.blueAccent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...lines.map((line) => _buildLineItem(line)),
                    if (lines.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('No lines configured in this yard.', style: TextStyle(fontStyle: FontStyle.italic, color: AppTheme.subtitleColor)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLineItem(dynamic line) {
    final bool isActive = line['status'] == 'Active';
    final bool hasDevice = line['assigned_de'] != null;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      padding: const EdgeInsets.all(12.0),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.route, size: 18, color: isActive ? AppTheme.primaryColor : Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    line['line_name'] ?? 'Unknown Line',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isActive ? AppTheme.primaryColor : Colors.grey),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive ? Colors.green.shade50 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: isActive ? Colors.green.shade200 : Colors.grey.shade300),
                ),
                child: Text(
                  line['status'] ?? 'Unknown',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isActive ? Colors.green.shade700 : Colors.grey.shade600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Line Type', style: TextStyle(fontSize: 11, color: AppTheme.subtitleColor)),
                    Text(line['line_type'] ?? 'N/A', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Line Code', style: TextStyle(fontSize: 11, color: AppTheme.subtitleColor)),
                    Text(line['line_code'] ?? 'N/A', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Divider(),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.vertical_align_bottom, size: 16, color: AppTheme.subtitleColor),
                  const SizedBox(width: 4),
                  const Text('Assigned Device: ', style: TextStyle(fontSize: 12, color: AppTheme.subtitleColor)),
                  Text(
                    hasDevice ? line['assigned_de'] : 'None',
                    style: TextStyle(
                      fontSize: 13, 
                      fontWeight: FontWeight.bold, 
                      color: hasDevice ? Colors.blueAccent : Colors.redAccent
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.edit_note, size: 20, color: AppTheme.subtitleColor),
                onPressed: () => _showAssignForm(line),
                tooltip: 'Edit Assignment',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24.0),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Create New...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
            const SizedBox(height: 16),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFF1F5F9), child: Icon(Icons.factory, color: AppTheme.primaryColor)),
              title: const Text('Yard'),
              subtitle: const Text('Add a new train yard to the station'),
              onTap: () {
                Navigator.pop(context);
                _showYardForm();
              },
            ),
          ],
        ),
      ),
      ),
    );
  }

  void _showYardForm() {
    final nameController = TextEditingController();
    bool isSubmitting = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          return Material(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24, right: 24, top: 24
              ),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Create Yard', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    children: [
                      const SizedBox(height: 16),
                      const Text('Yard Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.subtitleColor)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          hintText: 'e.g. North Yard',
                          filled: true,
                          fillColor: AppTheme.backgroundColor,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isSubmitting ? null : () async {
                            if (nameController.text.trim().isEmpty) return;
                            setModalState(() => isSubmitting = true);
                            final result = await ApiService.createYard(nameController.text.trim());
                            if (mounted) {
                               if (result['success']) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Yard Created!')));
                                  _fetchData();
                               } else {
                                  setModalState(() => isSubmitting = false);
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'])));
                               }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: isSubmitting 
                           ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                           : const Text('SAVE YARD', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ),
                    ],
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

  void _showLineForm(String yardId) {
    final nameController = TextEditingController();
    final codeController = TextEditingController();

    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          return Material(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24, right: 24, top: 24
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Add Line', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView(
                      children: [
                        const SizedBox(height: 16),
                        const Text('Line Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.subtitleColor)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: nameController,
                          decoration: InputDecoration(
                            hintText: 'e.g. Pit Line 5',
                            filled: true,
                            fillColor: AppTheme.backgroundColor,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('Line Code (Geo or identifier)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.subtitleColor)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: codeController,
                          decoration: InputDecoration(
                            hintText: 'e.g. LN-05',
                            filled: true,
                            fillColor: AppTheme.backgroundColor,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isSubmitting ? null : () async {
                              if (nameController.text.trim().isEmpty || codeController.text.trim().isEmpty) return;
                              setModalState(() => isSubmitting = true);
                              final result = await ApiService.addYardLine(yardId, nameController.text.trim(), codeController.text.trim());
                              if (mounted) {
                                 if (result['success']) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Line Created!')));
                                    _fetchData();
                                 } else {
                                    setModalState(() => isSubmitting = false);
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'])));
                                 }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: isSubmitting 
                             ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                             : const Text('SAVE LINE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        ),
                      ],
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

  void _showAssignForm(dynamic line) {
    String? selectedDeviceId = line['assigned_device_id']?.toString();
    if (selectedDeviceId == null && line['assigned_de'] != null) {
      final matched = _unassignedDeadEnds.firstWhere(
        (d) => d['device_code'] == line['assigned_de'],
        orElse: () => null,
      );
      if (matched != null) selectedDeviceId = matched['id'].toString();
    }
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
                      Text("Assign DE to ${line['line_name']}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text('Select Transmitter / Dead-End Device', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.subtitleColor)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: selectedDeviceId,
                        hint: const Text('Select a transmitter'),
                        items: [
                          const DropdownMenuItem<String>(
                            value: 'unassign',
                            child: Text('None (Unassign)', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                          ),
                          ..._unassignedDeadEnds.map((d) {
                            return DropdownMenuItem<String>(
                              value: d['id'].toString(),
                              child: Text("${d['device_code']} (${d['device_type'] ?? 'Dead-End'})"),
                            );
                          }),
                        ],
                        onChanged: (val) {
                          setModalState(() => selectedDeviceId = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSubmitting || selectedDeviceId == null ? null : () async {
                        setModalState(() => isSubmitting = true);
                        Map<String, dynamic> result;
                        if (selectedDeviceId == 'unassign') {
                          // Unassign device from line
                          final currentDevId = line['assigned_device_id'] ?? selectedDeviceId;
                          result = await ApiService.assignDeviceToLine(currentDevId.toString(), null);
                        } else {
                          result = await ApiService.assignDeviceToLine(selectedDeviceId!, line['id']);
                        }
                        if (mounted) {
                           if (result['success']) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Assignment Updated!')));
                              _fetchData();
                           } else {
                              setModalState(() => isSubmitting = false);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'])));
                           }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isSubmitting 
                       ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                       : const Text('SAVE ASSIGNMENT', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
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
