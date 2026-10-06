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
    setState(() { _isLoading = true; _errorMessage = null; });
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
      case 'super_admin':    return 'Super Admin';
      case 'zone_admin':     return 'Zone Admin';
      case 'division_admin': return 'Division Admin';
      case 'yard_admin':     return 'Yard Admin';
      case 'supervisor':     return 'Supervisor';
      case 'shunter':        return 'Shunter';
      default:               return role ?? 'Unknown';
    }
  }

  Color _getRoleColor(String? role) {
    switch (role) {
      case 'super_admin':    return const Color(0xFFDC2626);
      case 'zone_admin':     return const Color(0xFF9333EA);
      case 'division_admin': return const Color(0xFF0284C7);
      case 'yard_admin':     return const Color(0xFF2563EB);
      case 'supervisor':     return const Color(0xFF0D9488);
      case 'shunter':        return const Color(0xFF65A30D);
      default:               return AppTheme.subtitleColor;
    }
  }

  IconData _getRoleIcon(String? role) {
    switch (role) {
      case 'super_admin':    return Icons.shield;
      case 'zone_admin':     return Icons.map_outlined;
      case 'division_admin': return Icons.location_city_outlined;
      case 'yard_admin':     return Icons.business_outlined;
      case 'supervisor':     return Icons.supervisor_account_outlined;
      case 'shunter':        return Icons.engineering_outlined;
      default:               return Icons.person_outline;
    }
  }

  Future<void> _toggleUserActive(Map<String, dynamic> user) async {
    final result = await ApiService.toggleUserActive(user['id'].toString());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result['message'] ?? 'Done'),
      backgroundColor: result['success'] ? Colors.green : Colors.red,
    ));
    if (result['success']) _loadData();
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Confirm Deletion', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete ${user['fullName']}? This action cannot be undone.',
          style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60, fontSize: 14)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete User'),
          ),
        ],
      ),
    );
    if (result == true) {
      final res = await ApiService.deleteUser(user['id'].toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message']), backgroundColor: res['success'] ? Colors.green : Colors.red));
      if (res['success']) _loadData();
    }
  }

  Future<void> _showAssignYardDialog(Map<String, dynamic> user) async {
    final assignedYardIds = (user['assignedYards'] as List?)?.map((y) => y['id']?.toString() ?? '').toSet() ?? {};
    final availableYards = _yards.where((y) => !assignedYardIds.contains(y['id']?.toString())).toList();
    if (availableYards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No more yards available to assign.')));
      return;
    }
    String? selectedYardId;
    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(builder: (stateCtx, setDs) => AlertDialog(
        title: Text('Assign Yard to ${user['fullName']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Select a yard to assign:', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(hintText: 'Select yard', border: OutlineInputBorder()),
            initialValue: selectedYardId,
            items: availableYards.map((y) => DropdownMenuItem<String>(value: y['id']?.toString(), child: Text('${y['yard_name']}'))).toList(),
            onChanged: (value) => setDs(() { selectedYardId = value; }),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: selectedYardId == null ? null : () async {
              Navigator.pop(context);
              final result = await ApiService.assignYardToUser(userId: user['id'].toString(), yardId: selectedYardId!);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'Done'), backgroundColor: result['success'] ? Colors.green : Colors.red));
              _loadData();
            },
            child: const Text('Assign'),
          ),
        ],
      )),
    );
  }

  Future<void> _showRemoveYardDialog(Map<String, dynamic> user) async {
    final assignedYards = List<Map<String, dynamic>>.from(user['assignedYards'] ?? []);
    if (assignedYards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No yards to remove.')));
      return;
    }
    String? selectedYardId;
    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(builder: (stateCtx, setDs) => AlertDialog(
        title: Text('Remove Yard from ${user['fullName']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Select a yard to remove:', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(hintText: 'Select yard', border: OutlineInputBorder()),
            initialValue: selectedYardId,
            items: assignedYards.map((y) => DropdownMenuItem<String>(value: y['id']?.toString(), child: Text('${y['yard_name']}'))).toList(),
            onChanged: (value) => setDs(() { selectedYardId = value; }),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: selectedYardId == null ? null : () async {
              Navigator.pop(context);
              final result = await ApiService.removeYardAssignment(userId: user['id'].toString(), yardId: selectedYardId!);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'Done'), backgroundColor: result['success'] ? Colors.green : Colors.red));
              _loadData();
            },
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      )),
    );
  }

  // ─── Tree helpers ────────────────────────────────────────────────

  List<Map<String, dynamic>> _byRole(String role) => _users.where((u) => u['role'] == role).toList();

  List<Map<String, dynamic>> _divAdminsForZone(Map<String, dynamic> za) {
    final zones = List<String>.from(za['assignedZones'] ?? []);
    if (zones.isEmpty) return [];
    return _byRole('division_admin').where((da) {
      final divs = List<String>.from(da['assignedDivisions'] ?? []);
      if (_yards.isEmpty) return true;
      return divs.any((div) => _yards.any((y) =>
          y['division']?.toString().toLowerCase() == div.toLowerCase() &&
          zones.any((z) => y['zone']?.toString().toLowerCase() == z.toLowerCase())));
    }).toList();
  }

  List<Map<String, dynamic>> _yardAdminsForDiv(Map<String, dynamic> da) {
    final divs = List<String>.from(da['assignedDivisions'] ?? []);
    if (divs.isEmpty) return [];
    return _byRole('yard_admin').where((ya) {
      final yardIds = (ya['assignedYards'] as List?)?.map((y) => y['id']?.toString()).toSet() ?? {};
      if (_yards.isEmpty) return true;
      return _yards.any((y) => yardIds.contains(y['id']?.toString()) &&
          divs.any((d) => y['division']?.toString().toLowerCase() == d.toLowerCase()));
    }).toList();
  }

  List<Map<String, dynamic>> _operatorsForYardAdmin(Map<String, dynamic> ya) {
    final yardIds = (ya['assignedYards'] as List?)?.map((y) => y['id']?.toString()).toSet() ?? {};
    if (yardIds.isEmpty) return [];
    return _users.where((u) {
      if (u['role'] != 'supervisor' && u['role'] != 'shunter') return false;
      final uIds = (u['assignedYards'] as List?)?.map((y) => y['id']?.toString()).toSet() ?? {};
      return yardIds.intersection(uIds).isNotEmpty;
    }).toList();
  }

  // ─── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final session = UserSession();
    final isSuperAdmin = session.isSuperAdmin;
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1A2A42), Color(0xFF0F172A)])),
        ),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))),
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        title: const Text('User Hierarchy', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [IconButton(icon: const Icon(Icons.refresh, color: Colors.cyanAccent), onPressed: _loadData)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)))
              : _buildTree(),
      floatingActionButton: session.canManageUsers
          ? FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const RegistrationScreen(isAdminCreatingUser: true)));
                _loadData();
              },
              backgroundColor: Colors.cyanAccent.shade700,
              icon: const Icon(Icons.person_add, color: Colors.white),
              label: const Text('Add User', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  Widget _buildTree() {
    final session = UserSession();
    final superAdmins = _byRole('super_admin');
    final zoneAdmins = _byRole('zone_admin');
    final linkedDiv = <String>{};
    final linkedYard = <String>{};
    final linkedOps = <String>{};

    List<_TreeNode> buildOpsChildren(Map<String, dynamic> ya) {
      final ops = _operatorsForYardAdmin(ya);
      for (final o in ops) linkedOps.add(o['id'].toString());
      return ops.map((op) => _TreeNode(user: op, children: const [])).toList();
    }

    List<_TreeNode> buildYardChildren(Map<String, dynamic> da) {
      final yardAdmins = _yardAdminsForDiv(da);
      for (final y in yardAdmins) linkedYard.add(y['id'].toString());
      return yardAdmins.map((ya) => _TreeNode(user: ya, children: buildOpsChildren(ya))).toList();
    }

    List<_TreeNode> buildDivChildren(Map<String, dynamic> za) {
      final divAdmins = _divAdminsForZone(za);
      for (final d in divAdmins) linkedDiv.add(d['id'].toString());
      return divAdmins.map((da) => _TreeNode(user: da, children: buildYardChildren(da))).toList();
    }

    List<_TreeNode> buildZoneChildren(Map<String, dynamic> sa) {
      return zoneAdmins.map((za) => _TreeNode(user: za, children: buildDivChildren(za))).toList();
    }

    List<_TreeNode> roots = [];

    if (session.isSuperAdmin) {
      roots = superAdmins.map((sa) => _TreeNode(user: sa, children: buildZoneChildren(sa))).toList();
      
      // Unlinked division admins
      for (final da in _byRole('division_admin').where((u) => !linkedDiv.contains(u['id'].toString()))) {
        roots.add(_TreeNode(user: da, children: []));
      }
      // Unlinked yard admins
      for (final ya in _byRole('yard_admin').where((u) => !linkedYard.contains(u['id'].toString()))) {
        roots.add(_TreeNode(user: ya, children: []));
      }
      // Unlinked operators
      for (final op in _users.where((u) => (u['role'] == 'supervisor' || u['role'] == 'shunter') && !linkedOps.contains(u['id'].toString()))) {
        roots.add(_TreeNode(user: op, children: []));
      }
    } else if (session.isZoneAdmin) {
      final myZoneAdmins = zoneAdmins.where((za) => za['id'].toString() == session.id).toList();
      roots = myZoneAdmins.map((za) => _TreeNode(user: za, children: buildDivChildren(za))).toList();
    } else if (session.isDivisionAdmin) {
      final myDivAdmins = _byRole('division_admin').where((da) => da['id'].toString() == session.id).toList();
      roots = myDivAdmins.map((da) => _TreeNode(user: da, children: buildYardChildren(da))).toList();
    } else if (session.isYardAdmin) {
      final myYardAdmins = _byRole('yard_admin').where((ya) => ya['id'].toString() == session.id).toList();
      roots = myYardAdmins.map((ya) => _TreeNode(user: ya, children: buildOpsChildren(ya))).toList();
    } else if (session.isShuntingSupervisor) {
      final mySupervisors = _byRole('supervisor').where((su) => su['id'].toString() == session.id).toList();
      roots = mySupervisors.map((su) {
        final yardIds = (su['assignedYards'] as List?)?.map((y) => y['id']?.toString()).toSet() ?? {};
        final shunters = _byRole('shunter').where((sh) {
          final sYardIds = (sh['assignedYards'] as List?)?.map((y) => y['id']?.toString()).toSet() ?? {};
          return yardIds.intersection(sYardIds).isNotEmpty;
        }).toList();
        return _TreeNode(user: su, children: shunters.map((sh) => _TreeNode(user: sh, children: const [])).toList());
      }).toList();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 120),
      children: roots.map((n) => _TreeNodeWidget(
        node: n,
        depth: 0,
        getRoleLabel: _getRoleLabel,
        getRoleColor: _getRoleColor,
        getRoleIcon: _getRoleIcon,
        onToggleActive: _toggleUserActive,
        onDelete: _deleteUser,
        onAssignYard: _showAssignYardDialog,
        onRemoveYard: _showRemoveYardDialog,
      )).toList(),
    );
  }
}

// ─── Data model ──────────────────────────────────────────────────────────────

class _TreeNode {
  final Map<String, dynamic> user;
  final List<_TreeNode> children;
  const _TreeNode({required this.user, required this.children});
}

// ─── Tree Node Widget ─────────────────────────────────────────────────────────

class _TreeNodeWidget extends StatefulWidget {
  final _TreeNode node;
  final int depth;
  final String Function(String?) getRoleLabel;
  final Color Function(String?) getRoleColor;
  final IconData Function(String?) getRoleIcon;
  final Future<void> Function(Map<String, dynamic>) onToggleActive;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final Future<void> Function(Map<String, dynamic>) onAssignYard;
  final Future<void> Function(Map<String, dynamic>) onRemoveYard;

  const _TreeNodeWidget({
    required this.node,
    required this.depth,
    required this.getRoleLabel,
    required this.getRoleColor,
    required this.getRoleIcon,
    required this.onToggleActive,
    required this.onDelete,
    required this.onAssignYard,
    required this.onRemoveYard,
  });

  @override
  State<_TreeNodeWidget> createState() => _TreeNodeWidgetState();
}

class _TreeNodeWidgetState extends State<_TreeNodeWidget> with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _ctrl;
  late Animation<double> _rot;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _rot = Tween<double>(begin: 0, end: 0.5).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _ctrl.value = 0.0;
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _toggle() {
    setState(() { _expanded = !_expanded; });
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.node.user;
    final children = widget.node.children;
    final hasChildren = children.isNotEmpty;
    final role = user['role']?.toString();
    final isActive = user['isActive'] == true;
    final roleColor = widget.getRoleColor(role);
    final roleLabel = widget.getRoleLabel(role);
    final roleIcon = widget.getRoleIcon(role);

    final cardColors = [
      const Color(0xFF1E293B),
      const Color(0xFF1A2540),
      const Color(0xFF172035),
      const Color(0xFF141B2D),
      const Color(0xFF121628),
    ];
    final bgColor = cardColors[widget.depth.clamp(0, cardColors.length - 1)];

    return Padding(
      padding: EdgeInsets.only(top: widget.depth == 0 ? 10 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Connector
          if (widget.depth > 0)
            Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Row(children: [
                Container(width: 1.5, height: 10, color: Colors.white12),
                Container(width: 10, height: 1.5, color: Colors.white12),
              ]),
            ),

          // Card
          GestureDetector(
            onTap: hasChildren ? _toggle : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(left: widget.depth > 0 ? 28.0 : 0, bottom: 3),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isActive ? roleColor.withValues(alpha: widget.depth == 0 ? 0.6 : 0.35) : Colors.red.withValues(alpha: 0.4),
                  width: widget.depth == 0 ? 1.5 : 1.0,
                ),
                boxShadow: widget.depth == 0 ? [BoxShadow(color: roleColor.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 4))] : null,
              ),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(children: [
                    // Icon
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: roleColor.withValues(alpha: 0.15), shape: BoxShape.circle, border: Border.all(color: roleColor.withValues(alpha: 0.4))),
                      child: Icon(roleIcon, color: roleColor, size: 17),
                    ),
                    const SizedBox(width: 11),
                    // Info
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(
                          user['fullName'] ?? 'Unknown',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: isActive ? Colors.white : Colors.white38, decoration: isActive ? null : TextDecoration.lineThrough),
                          overflow: TextOverflow.ellipsis,
                        )),
                        if (!isActive) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                            child: const Text('INACTIVE', style: TextStyle(color: Colors.redAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 2),
                      Text('${user['employeeId'] ?? ''} • ${user['email'] ?? ''}', style: const TextStyle(color: Colors.white54, fontSize: 10.5), overflow: TextOverflow.ellipsis),
                      _buildChips(user, role, roleColor),
                    ])),
                    // Badge + expand arrow
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: roleColor, borderRadius: BorderRadius.circular(6)),
                        child: Text(roleLabel, style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w700)),
                      ),
                      if (hasChildren) ...[
                        const SizedBox(height: 5),
                        RotationTransition(turns: _rot, child: const Icon(Icons.expand_more, color: Colors.white38, size: 17)),
                      ],
                    ]),
                  ]),
                ),
                // Actions
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 5, 12, 7),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06)))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    if (['yard_admin', 'supervisor', 'shunter'].contains(role)) ...[
                      _Btn(label: 'Assign', icon: Icons.add_location_alt_outlined, color: Colors.cyanAccent, onTap: () => widget.onAssignYard(user)),
                      const SizedBox(width: 8),
                      _Btn(label: 'Remove', icon: Icons.wrong_location_outlined, color: Colors.deepOrangeAccent, onTap: () => widget.onRemoveYard(user)),
                      const SizedBox(width: 10),
                    ],
                    _Btn(label: isActive ? 'Deactivate' : 'Activate', icon: isActive ? Icons.pause_circle_outline : Icons.play_circle_outline, color: isActive ? Colors.orange : Colors.green, onTap: () => widget.onToggleActive(user)),
                    const SizedBox(width: 10),
                    _Btn(label: 'Delete', icon: Icons.delete_outline, color: Colors.redAccent, onTap: () => widget.onDelete(user)),
                  ]),
                ),
              ]),
            ),
          ),

          // Children
          if (_expanded && hasChildren)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children.map((child) => _TreeNodeWidget(
                node: child,
                depth: widget.depth + 1,
                getRoleLabel: widget.getRoleLabel,
                getRoleColor: widget.getRoleColor,
                getRoleIcon: widget.getRoleIcon,
                onToggleActive: widget.onToggleActive,
                onDelete: widget.onDelete,
                onAssignYard: widget.onAssignYard,
                onRemoveYard: widget.onRemoveYard,
              )).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildChips(Map<String, dynamic> user, String? role, Color roleColor) {
    List<String> chips = [];
    if (role == 'zone_admin') chips = List<String>.from(user['assignedZones'] ?? []);
    if (role == 'division_admin') chips = List<String>.from(user['assignedDivisions'] ?? []);
    if (['yard_admin', 'supervisor', 'shunter'].contains(role)) {
      chips = List<Map<String, dynamic>>.from(user['assignedYards'] ?? []).map((y) => y['yard_name']?.toString() ?? '').toList();
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Wrap(spacing: 4, runSpacing: 3, children: [
        ...chips.take(3).map((c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: roleColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4), border: Border.all(color: roleColor.withValues(alpha: 0.3))),
          child: Text(c, style: TextStyle(color: roleColor, fontSize: 9, fontWeight: FontWeight.w600)),
        )),
        if (chips.length > 3)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
            child: Text('+${chips.length - 3} more', style: const TextStyle(color: Colors.white54, fontSize: 9)),
          ),
      ]),
    );
  }
}

// ─── Action button ────────────────────────────────────────────────────────────

class _Btn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _Btn({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 13),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w600)),
    ]),
  );
}
