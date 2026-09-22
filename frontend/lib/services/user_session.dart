/// Global user session state for the logged-in user.
/// Stores role, assigned yards, and user info after login.
class UserSession {
  // Singleton pattern
  static final UserSession _instance = UserSession._internal();
  factory UserSession() => _instance;
  UserSession._internal();

  // User data
  String? id;
  String? fullName;
  String? employeeId;
  String? email;
  String? designation;
  String? role;
  String? token;
  String? profilePicUrl;
  List<Map<String, dynamic>> assignedYards = [];

  // Role constants
  static const String roleSuperAdmin = 'super_admin';
  static const String roleYardAdmin = 'yard_admin';
  static const String roleMaintenanceUser = 'maintenance_user';
  static const String roleHardwareEngineer = 'hardware_engineer';
  static const String roleViewer = 'viewer';

  /// Initialize session from login API response
  void setFromLoginResponse(Map<String, dynamic> data) {
    final user = data['user'];
    id = user['id'];
    fullName = user['fullName'];
    employeeId = user['employeeId'];
    email = user['email'];
    designation = user['designation'];
    role = user['role'] ?? roleViewer;
    token = data['token'];
    profilePicUrl = user['profilePicUrl'];

    // Parse assigned yards
    if (user['assignedYards'] != null && user['assignedYards'] is List) {
      assignedYards = List<Map<String, dynamic>>.from(
        (user['assignedYards'] as List).map((y) => Map<String, dynamic>.from(y)),
      );
    } else {
      assignedYards = [];
    }
  }

  /// Clear session on logout
  void clear() {
    id = null;
    fullName = null;
    employeeId = null;
    email = null;
    designation = null;
    role = null;
    token = null;
    profilePicUrl = null;
    assignedYards = [];
  }

  // Role check helpers
  bool get isSuperAdmin => role == roleSuperAdmin;
  bool get isYardAdmin => role == roleYardAdmin;
  bool get isMaintenanceUser => role == roleMaintenanceUser;
  bool get isHardwareEngineer => role == roleHardwareEngineer;
  bool get isViewer => role == roleViewer;

  /// Whether this user can configure yards (create/edit yards and lines)
  bool get canConfigureYards => isSuperAdmin;

  /// Whether this user can manage devices (register/edit/inventory)
  bool get canManageDevices => isSuperAdmin || isYardAdmin || isHardwareEngineer || isMaintenanceUser;

  /// Whether this user can issue/return portable devices
  bool get canIssueReturn => isSuperAdmin || isYardAdmin;

  /// Whether this user can manage users (Super Admin only)
  bool get canManageUsers => isSuperAdmin;

  /// Whether this user can access Hardware Console (Super Admin, Hardware Engineer, Maintenance)
  bool get canAccessHardwareConsole => isSuperAdmin || isHardwareEngineer || isMaintenanceUser;

  /// Whether this user can view sessions (All roles)
  bool get canViewSessions => true;

  /// Whether the user is logged in
  bool get isLoggedIn => token != null && id != null;

  /// Get display role name
  String get displayRole {
    switch (role) {
      case roleSuperAdmin:
        return 'Super Administrator';
      case roleYardAdmin:
        return 'Yard Administrator';
      case roleMaintenanceUser:
        return 'Maintenance User';
      case roleHardwareEngineer:
        return 'Hardware Engineer';
      case roleViewer:
        return 'Viewer / Control Room';
      default:
        return designation ?? 'Unknown';
    }
  }

  /// Get the list of assigned yard IDs
  List<String> get assignedYardIds =>
      assignedYards.map((y) => y['id'].toString()).toList();

  /// Get assigned yard names (for display)
  List<String> get assignedYardNames =>
      assignedYards.map((y) => y['yard_name']?.toString() ?? '').toList();
}
