import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Global user session state for the logged-in user.
/// Stores role, assigned yards, and user info after login,
/// persisted to SharedPreferences so page reloads do not log out.
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
  List<String> assignedZones = [];
  List<String> assignedDivisions = [];

  // Role constants
  static const String roleSuperAdmin = 'super_admin';
  static const String roleZoneAdmin = 'zone_admin';
  static const String roleDivisionAdmin = 'division_admin';
  static const String roleYardAdmin = 'yard_admin';
  static const String roleShuntingSupervisor = 'supervisor';
  static const String roleShunter = 'shunter';

  static const String _prefKeySession = 'user_session_cache_v1';

  /// Initialize session from login API response
  Future<void> setFromLoginResponse(Map<String, dynamic> data) async {
    final user = data['user'] ?? {};
    id = user['id']?.toString();
    fullName = user['fullName'];
    employeeId = user['employeeId'];
    email = user['email'];
    designation = user['designation'];
    role = user['role'] ?? roleShunter;
    token = data['token'];
    profilePicUrl = user['profilePicUrl'] ?? user['profile_pic_url'];

    // Parse assigned yards
    if (user['assignedYards'] != null && user['assignedYards'] is List) {
      assignedYards = List<Map<String, dynamic>>.from(
        (user['assignedYards'] as List).map((y) => Map<String, dynamic>.from(y)),
      );
    } else {
      assignedYards = [];
    }
    
    if (user['assignedZones'] != null && user['assignedZones'] is List) {
      assignedZones = List<String>.from(user['assignedZones']);
    } else {
      assignedZones = [];
    }

    if (user['assignedDivisions'] != null && user['assignedDivisions'] is List) {
      assignedDivisions = List<String>.from(user['assignedDivisions']);
    } else {
      assignedDivisions = [];
    }

    await saveToPreferences();
  }

  /// Save current session to persistent storage
  Future<void> saveToPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = {
        'id': id,
        'fullName': fullName,
        'employeeId': employeeId,
        'email': email,
        'designation': designation,
        'role': role,
        'token': token,
        'profilePicUrl': profilePicUrl,
        'assignedYards': assignedYards,
        'assignedZones': assignedZones,
        'assignedDivisions': assignedDivisions,
      };
      await prefs.setString(_prefKeySession, jsonEncode(map));
    } catch (_) {
      // Ignore storage errors in restricted contexts
    }
  }

  /// Restore session from persistent storage
  Future<bool> loadFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKeySession);
      if (raw == null || raw.isEmpty) return false;

      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['token'] == null || map['id'] == null) return false;

      id = map['id']?.toString();
      fullName = map['fullName'];
      employeeId = map['employeeId'];
      email = map['email'];
      designation = map['designation'];
      role = map['role'] ?? roleShunter;
      token = map['token'];
      profilePicUrl = map['profilePicUrl'];

      if (map['assignedYards'] != null && map['assignedYards'] is List) {
        assignedYards = List<Map<String, dynamic>>.from(
          (map['assignedYards'] as List).map((y) => Map<String, dynamic>.from(y)),
        );
      } else {
        assignedYards = [];
      }

      if (map['assignedZones'] != null && map['assignedZones'] is List) {
        assignedZones = List<String>.from(map['assignedZones']);
      } else {
        assignedZones = [];
      }

      if (map['assignedDivisions'] != null && map['assignedDivisions'] is List) {
        assignedDivisions = List<String>.from(map['assignedDivisions']);
      } else {
        assignedDivisions = [];
      }
      return isLoggedIn;
    } catch (_) {
      return false;
    }
  }

  /// Clear session on logout
  Future<void> clear() async {
    id = null;
    fullName = null;
    employeeId = null;
    email = null;
    designation = null;
    role = null;
    token = null;
    profilePicUrl = null;
    assignedYards = [];
    assignedZones = [];
    assignedDivisions = [];

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKeySession);
    } catch (_) {}
  }

  // Role check helpers
  bool get isSuperAdmin => role == roleSuperAdmin;
  bool get isZoneAdmin => role == roleZoneAdmin;
  bool get isDivisionAdmin => role == roleDivisionAdmin;
  bool get isYardAdmin => role == roleYardAdmin;
  bool get isShuntingSupervisor => role == roleShuntingSupervisor;
  bool get isShunter => role == roleShunter;

  /// Whether this user can configure yards (create/edit yards and lines)
  bool get canConfigureYards => isSuperAdmin || isZoneAdmin || isDivisionAdmin;

  /// Whether this user can manage devices (register/edit/inventory)
  bool get canManageDevices => isSuperAdmin || isZoneAdmin || isDivisionAdmin || isYardAdmin;

  /// Whether this user can issue/return portable devices
  bool get canIssueReturn => isSuperAdmin || isZoneAdmin || isDivisionAdmin || isYardAdmin || isShuntingSupervisor || isShunter;

  /// Whether this user can manage users (Super Admin, Zone, Division, Yard Admin, Supervisor)
  bool get canManageUsers => isSuperAdmin || isZoneAdmin || isDivisionAdmin || isYardAdmin || isShuntingSupervisor;

  /// Whether this user has maintenance permissions
  bool get isMaintenanceUser => isYardAdmin || isSuperAdmin;

  /// Whether this user can access Hardware Console
  bool get canAccessHardwareConsole => isSuperAdmin || isZoneAdmin || isDivisionAdmin;

  /// Whether this user can view sessions (All roles except limited maintenance perhaps, but keeping it true)
  bool get canViewSessions => true;

  /// Whether the user is logged in
  bool get isLoggedIn => token != null && id != null;

  /// Get display role name
  String get displayRole {
    switch (role) {
      case roleSuperAdmin:
        return 'Super Administrator';
      case roleZoneAdmin:
        return 'Zone Administrator';
      case roleDivisionAdmin:
        return 'Division Administrator';
      case roleYardAdmin:
        return 'Yard Administrator';
      case roleShuntingSupervisor:
        return 'Shunting Supervisor';
      case roleShunter:
        return 'Shunter';
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
