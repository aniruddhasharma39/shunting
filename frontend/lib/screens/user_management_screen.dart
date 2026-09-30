import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/user_session.dart';
import 'registration_screen.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _yards = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final usersResult = await ApiService.fetchUsers();
    final yardsResult = await ApiService.fetchYards();

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (usersResult['success']) {
        _users = List<Map<String, dynamic>>.from(usersResult['data'] ?? []);
      } else {
        _errorMessage = usersResult['message'];
      }
      if (yardsResult['success']) {
        _yards = List<Map<String, dynamic>>.from(yardsResult['data'] ?? []);
      }
    });
  }

  String _getRoleLabel(String? role) {
    switch (role) {
      case 'super_admin':
        return 'Super Admin';
      case 'yard_admin':
        return 'Yard Admin';
      case 'maintenance_user':
        return 'Maintenance';
      case 'viewer':
        return 'Viewer';
      default:
        return role ?? 'Unknown';
    }
  }

  Color _getRoleColor(String? role) {
    switch (role) {
      case 'super_admin':
        return const Color(0xFFDC2626);
      case 'yard_admin':
        return const Color(0xFF2563EB);
      case 'maintenance_user':
        return const Color(0xFFD97706);
      case 'viewer':
        return const Color(0xFF059669);
      default:
        return AppTheme.subtitleColor;
    }
  }

  Future<void> _toggleUserActive(Map<String, dynamic> user) async {
    final result = await ApiService.toggleUserActive(user['id'].toString());
    if (!mounted) return;

    if (result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message']), backgroundColor: Colors.green),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message']), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showAssignYardDialog(Map<String, dynamic> user) async {
    final assignedYardIds = (user['assignedYards'] as List?)
        ?.map((y) => y['id']?.toString() ?? '')
        .toSet() ?? {};

    final availableYards = _yards.where((y) => !assignedYardIds.contains(y['id']?.toString())).toList();

    if (availableYards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No more yards available to assign.')),
      );
      return;
    }

    String? selectedYardId;

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (stateCtx, setDialogState) {
            return AlertDialog(
              title: Text('Assign Yard to ${user['fullName']}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Select a yard to assign:', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      hintText: 'Select yard',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: selectedYardId,
                    items: availableYards.map((y) {
                      return DropdownMenuItem<String>(
                        value: y['id']?.toString(),
                        child: Text('${y['yard_name']}${y['location'] != null && y['location'].toString().isNotEmpty ? ' (${y['location']})' : ''}'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedYardId = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: selectedYardId == null
                      ? null
                      : () async {
                          Navigator.pop(context);
                          final result = await ApiService.assignYardToUser(
                            userId: user['id'].toString(),
                            yardId: selectedYardId!,
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(result['message'] ?? 'Done'),
                              backgroundColor: result['success'] ? Colors.green : Colors.red,
                            ),
                          );
                          _loadData();
                        },
                  child: const Text('Assign'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _removeYardAssignment(Map<String, dynamic> user, Map<String, dynamic> yard) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Yard Assignment'),
        content: Text('Remove "${yard['yard_name']}" from ${user['fullName']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final result = await ApiService.removeYardAssignment(
        userId: user['id'].toString(),
        yardId: yard['id'].toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Done'),
          backgroundColor: result['success'] ? Colors.green : Colors.red,
        ),
      );
      _loadData();
    }
  }

  Map<String, List<Map<String, dynamic>>> get _groupedUsers {
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (var user in _users) {
      final role = _getRoleLabel(user['role']?.toString());
      if (!groups.containsKey(role)) {
        groups[role] = [];
      }
      groups[role]!.add(user);
    }
    return groups;
  }

  Future<void> _deleteUserWithConfirmation(Map<String, dynamic> user) async {
    final expectedEmail = user['email'] ?? '';
    final expectedName = user['fullName'] ?? 'Unknown';
    String inputText = '';
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              title: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
                  const SizedBox(width: 10),
                  const Text('Delete User', style: TextStyle(color: Colors.redAccent)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You are about to permanently delete the user $expectedName.',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Please type their email address to confirm:',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    expectedEmail,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (val) {
                      setState(() {
                        inputText = val;
                      });
                    },
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      hintText: 'Type email here...',
                      hintStyle: const TextStyle(color: Colors.white38),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  onPressed: inputText.trim() == expectedEmail.trim()
                      ? () => Navigator.pop(context, true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    disabledBackgroundColor: Colors.redAccent.withValues(alpha: 0.3),
                  ),
                  child: const Text('Delete', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      final res = await ApiService.deleteUser(user['id'].toString());
      if (!mounted) return;
      if (res['success']) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message']), backgroundColor: Colors.green));
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message']), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
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
        title: const Text('User Management', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _groupedUsers.keys.length,
                    itemBuilder: (context, index) {
                      final roleName = _groupedUsers.keys.elementAt(index);
                      final roleUsers = _groupedUsers[roleName]!;
                      
                      return Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: Card(
                          color: const Color(0xFF1E293B),
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ExpansionTile(
                            initiallyExpanded: false,
                            iconColor: Colors.cyanAccent,
                            collapsedIconColor: Colors.white54,
                            title: Row(
                              children: [
                                Text(
                                  roleName,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.cyanAccent.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${roleUsers.length}',
                                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF0F172A),
                                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                                ),
                                child: Column(
                                  children: roleUsers.map((u) => _buildUserCard(u)).toList(),
                                ),
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const RegistrationScreen(isAdminCreatingUser: true)));
          _loadData();
        },
        backgroundColor: Colors.cyanAccent.shade700,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('Add User', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final role = user['role']?.toString();
    final isActive = user['isActive'] == true;
    final assignedYards = List<Map<String, dynamic>>.from(user['assignedYards'] ?? []);
    final isYardAdmin = role == 'yard_admin';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isActive ? AppTheme.borderColor : Colors.red.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // User info header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _getRoleColor(role).withValues(alpha: 0.15),
                  child: Text(
                    (user['fullName'] ?? 'U')[0].toUpperCase(),
                    style: TextStyle(
                      color: _getRoleColor(role),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user['fullName'] ?? 'Unknown',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: isActive ? AppTheme.primaryColor : AppTheme.subtitleColor,
                                decoration: isActive ? null : TextDecoration.lineThrough,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!isActive) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('INACTIVE', style: TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${user['employeeId'] ?? ''} • ${user['email'] ?? ''}',
                        style: const TextStyle(color: AppTheme.subtitleColor, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Role badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getRoleColor(role),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _getRoleLabel(role),
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

          // Assigned yards section (for Yard Admins)
          if (isYardAdmin) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                border: Border(top: BorderSide(color: AppTheme.borderColor)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'ASSIGNED YARDS',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: AppTheme.subtitleColor),
                      ),
                      InkWell(
                        onTap: () => _showAssignYardDialog(user),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text('Assign', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (assignedYards.isEmpty)
                    const Text(
                      'No yards assigned yet.',
                      style: TextStyle(color: Colors.orange, fontSize: 12, fontStyle: FontStyle.italic),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: assignedYards.map((yard) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.location_city, size: 14, color: Color(0xFF2563EB)),
                              const SizedBox(width: 4),
                              Text(
                                yard['yard_name'] ?? 'Unknown',
                                style: const TextStyle(color: Color(0xFF2563EB), fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () => _removeYardAssignment(user, yard),
                                child: const Icon(Icons.close, size: 14, color: Color(0xFF2563EB)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ],

          // Action buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppTheme.borderColor)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (user['id'] != UserSession().id) ...[
                  TextButton.icon(
                    onPressed: () => _deleteUserWithConfirmation(user),
                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                    label: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _toggleUserActive(user),
                    icon: Icon(
                      isActive ? Icons.block : Icons.check_circle_outline,
                      size: 16,
                      color: isActive ? Colors.orange : Colors.green,
                    ),
                    label: Text(
                      isActive ? 'Deactivate' : 'Activate',
                      style: TextStyle(
                        color: isActive ? Colors.orange : Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }
}
