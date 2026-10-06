import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/user_session.dart';

class RegistrationScreen extends StatefulWidget {
  final bool isAdminCreatingUser;
  const RegistrationScreen({super.key, this.isAdminCreatingUser = false});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _fullNameController = TextEditingController();
  final _employeeIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  // Assignment selections
  String? _selectedZone;
  String? _selectedDivision;
  String? _selectedParentZone; // For Division Admin
  String? _selectedYard;
  
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isFetchingData = false;
  String? _selectedDesignation;

  List<String> _availableZones = [];
  List<String> _availableDivisions = [];
  List<Map<String, dynamic>> _availableYards = [];

  List<String> get _designations {
    final role = UserSession().role;
    if (widget.isAdminCreatingUser) {
      if (role == 'yard_admin') {
        return ['Shunting Supervisor', 'Shunter'];
      } else if (role == 'supervisor') {
        return ['Shunter'];
      } else if (role == 'zone_admin') {
        return [
          'Division Administrator',
          'Yard Administrator',
          'Shunting Supervisor',
          'Shunter',
        ];
      }
    }
    return [
      'Zone Administrator',
      'Division Administrator',
      'Yard Administrator',
      'Shunting Supervisor',
      'Shunter',
    ];
  }

  @override
  void initState() {
    super.initState();
    _fetchAssignmentData();
  }

  Future<void> _fetchAssignmentData() async {
    setState(() => _isFetchingData = true);
    try {
      final zones = await ApiService.fetchZones();
      final divisions = await ApiService.fetchDivisions();
      final yardsRes = await ApiService.fetchYards();
      if (!mounted) return;
      setState(() {
        if (UserSession().role == 'zone_admin') {
          _availableZones = UserSession().assignedZones;
        } else {
          _availableZones = zones;
        }
        _availableDivisions = divisions;
        if (yardsRes['success']) {
          final allYards = List<Map<String, dynamic>>.from(yardsRes['data'] ?? []);
          if (UserSession().isShuntingSupervisor) {
            final myYardIds = UserSession().assignedYards.map((y) => y['id'].toString()).toSet();
            _availableYards = allYards.where((y) => myYardIds.contains(y['id'].toString())).toList();
          } else {
            _availableYards = allYards;
          }
        }
      });
    } finally {
      if (mounted) setState(() => _isFetchingData = false);
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _employeeIdController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    final fullName = _fullNameController.text.trim();
    final employeeId = _employeeIdController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (fullName.isEmpty || employeeId.isEmpty || email.isEmpty || password.isEmpty || _selectedDesignation == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill in all required fields')));
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
      return;
    }

    setState(() { _isLoading = true; });

    List<String>? assignedZones;
    List<String>? assignedDivisions;
    List<String>? assignedYards;
    String? parentZone;

    if (_selectedDesignation == 'Zone Administrator') {
      if (_selectedZone != null) assignedZones = [_selectedZone!];
    } else if (_selectedDesignation == 'Division Administrator') {
      if (_selectedDivision != null) assignedDivisions = [_selectedDivision!];
      if (_selectedParentZone != null) parentZone = _selectedParentZone;
    } else if (['Yard Administrator', 'Shunting Supervisor', 'Shunter'].contains(_selectedDesignation)) {
      if (_selectedYard != null) assignedYards = [_selectedYard!];
    }

    final result = await ApiService.registerUser(
      fullName: fullName,
      employeeId: employeeId,
      email: email,
      designation: _selectedDesignation!,
      password: password,
      isAdminCreatingUser: widget.isAdminCreatingUser,
      assignedZones: assignedZones,
      assignedDivisions: assignedDivisions,
      assignedYards: assignedYards,
      parentZone: parentZone,
    );

    setState(() { _isLoading = false; });

    if (!mounted) return;

    if (result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['data']['message'] ?? 'Registration Successful!'), backgroundColor: Colors.green),
      );
      Navigator.pop(context); // Go back
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message']), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.primaryColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Create Account'),
      ),
      body: _isFetchingData
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon and Title Row
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.manage_accounts_outlined, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          'Join the Safety Network',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Complete your profile to access rail shunting operations and safety logs.',
                    style: TextStyle(color: AppTheme.subtitleColor, fontSize: 14),
                  ),
                  const SizedBox(height: 32),
                  
                  // Form Fields
                  _buildLabel('Full Name'),
                  TextField(controller: _fullNameController, decoration: const InputDecoration(hintText: 'John Doe')),
                  const SizedBox(height: 16),
                  
                  _buildLabel('Employee ID'),
                  TextField(controller: _employeeIdController, decoration: const InputDecoration(hintText: 'RS-10294')),
                  const SizedBox(height: 16),
                  
                  _buildLabel('Email Address'),
                  TextField(controller: _emailController, decoration: const InputDecoration(hintText: 'name@railway.gov')),
                  const SizedBox(height: 16),
                  
                  _buildLabel('Designation'),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(hintText: 'Select position'),
                    icon: const Icon(Icons.keyboard_arrow_down),
                    value: _selectedDesignation,
                    items: _designations.map((String value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                    onChanged: (newValue) => setState(() {
                      _selectedDesignation = newValue;
                      // Reset selections on change
                      _selectedZone = null;
                      _selectedDivision = null;
                      _selectedYard = null;
                      _selectedParentZone = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  
                  // Dynamic Assignment Fields
                  if (_selectedDesignation == 'Zone Administrator') ...[
                    _buildLabel('Assigned Zone (Select existing or type new)'),
                    Autocomplete<String>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text.isEmpty) return _availableZones;
                        return _availableZones.where((String option) {
                          return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                        });
                      },
                      onSelected: (String selection) => setState(() => _selectedZone = selection),
                      fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                        // Keep track of what they type manually even if not in list
                        controller.addListener(() { _selectedZone = controller.text; });
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: const InputDecoration(hintText: 'e.g. North Western Railway (NWR)'),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  if (_selectedDesignation == 'Division Administrator') ...[
                    _buildLabel('Under Zone (Select Parent)'),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(hintText: 'Select parent zone'),
                      value: _selectedParentZone,
                      items: _availableZones.map((String value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                      onChanged: (newValue) => setState(() => _selectedParentZone = newValue),
                    ),
                    const SizedBox(height: 16),
                    _buildLabel('Assigned Division (Select existing or type new)'),
                    Autocomplete<String>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text.isEmpty) return _availableDivisions;
                        return _availableDivisions.where((String option) {
                          return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                        });
                      },
                      onSelected: (String selection) => setState(() => _selectedDivision = selection),
                      fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                        controller.addListener(() { _selectedDivision = controller.text; });
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: const InputDecoration(hintText: 'e.g. Jaipur Division'),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  if (['Yard Administrator', 'Shunting Supervisor', 'Shunter'].contains(_selectedDesignation)) ...[
                    _buildLabel('Assigned Yard'),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(hintText: 'Select Yard'),
                      value: _selectedYard,
                      items: _availableYards.map((y) => DropdownMenuItem<String>(value: y['id'].toString(), child: Text(y['yard_name']))).toList(),
                      onChanged: (newValue) => setState(() => _selectedYard = newValue),
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  _buildLabel('Password'),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      hintText: '••••••••',
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  _buildLabel('Confirm Password'),
                  TextField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: '••••••••'),
                  ),
                  const SizedBox(height: 24),
                  
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleRegister,
                    child: _isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Register'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildLabel(String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.subtitleColor)),
        const SizedBox(height: 8),
      ],
    );
  }
}
