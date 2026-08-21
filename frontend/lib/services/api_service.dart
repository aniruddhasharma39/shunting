import 'dart:convert';
import 'package:http/http.dart' as http;
import 'user_session.dart';

class ApiService {
  static const String baseUrl = 'https://shuntting-safety-device.onrender.com/api';

  /// Get auth headers with Bearer token
  static Map<String, String> _authHeaders() {
    final token = UserSession().token;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> registerUser({
    required String fullName,
    required String employeeId,
    required String email,
    required String designation,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'fullName': fullName,
          'employeeId': employeeId,
          'email': email,
          'designation': designation,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Registration failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error or Server unreachable. Check database connection.'};
    }
  }

  static Future<Map<String, dynamic>> loginUser({
    required String loginId,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'loginId': loginId,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Store user session data (role, assigned yards, token)
        UserSession().setFromLoginResponse(data);
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Login failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error or Server unreachable. Check database connection.'};
    }
  }

  /// Fetch current user profile with role and assigned yards
  static Future<Map<String, dynamic>> fetchMe() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/me'),
        headers: _authHeaders(),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to fetch profile'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  /// Fetch yards (backend filters by role automatically)
  static Future<Map<String, dynamic>> fetchYards() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/yards'),
        headers: _authHeaders(),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to fetch yards'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  /// List all users (Super Admin only)
  static Future<Map<String, dynamic>> fetchUsers() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/users'),
        headers: _authHeaders(),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'data': data['users'] ?? []};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to fetch users'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  /// Assign a yard to a user (Super Admin only)
  static Future<Map<String, dynamic>> assignYardToUser({
    required String userId,
    required String yardId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/yards/assign'),
        headers: _authHeaders(),
        body: jsonEncode({
          'userId': userId,
          'yardId': yardId,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Assignment failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  /// Remove yard assignment from a user (Super Admin only)
  static Future<Map<String, dynamic>> removeYardAssignment({
    required String userId,
    required String yardId,
  }) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/yards/assign'),
        headers: _authHeaders(),
        body: jsonEncode({
          'userId': userId,
          'yardId': yardId,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Removal failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  /// Toggle user active/inactive (Super Admin only)
  static Future<Map<String, dynamic>> toggleUserActive(String userId) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/auth/users/$userId/toggle-active'),
        headers: _authHeaders(),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message'], 'isActive': data['isActive']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  /// Fetch Dashboard Summary Data
  static Future<Map<String, dynamic>> fetchDashboardSummary() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/dashboard/summary'),
        headers: _authHeaders(),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to load dashboard'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  /// Fetch all devices
  static Future<Map<String, dynamic>> fetchDevices() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/devices'),
        headers: _authHeaders(),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to load devices'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  /// Register a new device
  static Future<Map<String, dynamic>> registerDevice({
    required String deviceCode,
    required String deviceType,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/devices'),
        headers: _authHeaders(),
        body: jsonEncode({
          'device_code': deviceCode,
          'device_type': deviceType,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to register device'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }



  static Future<Map<String, dynamic>> createYard(String yardName) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/yards'),
        headers: _authHeaders(),
        body: jsonEncode({'yard_name': yardName})
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 201) return {'success': true, 'data': data};
      return {'success': false, 'message': data['message'] ?? 'Failed to create yard'};
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  static Future<Map<String, dynamic>> fetchYardLines(int yardId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/yards/$yardId/lines'), headers: _authHeaders());
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'data': data};
      return {'success': false, 'message': data['message'] ?? 'Failed to load lines'};
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  static Future<Map<String, dynamic>> addYardLine(String yardId, String lineName, String lineCode) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/yards/$yardId/lines'),
        headers: _authHeaders(),
        body: jsonEncode({'line_name': lineName, 'line_code': lineCode, 'line_type': 'Standard'})
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 201) return {'success': true, 'data': data};
      return {'success': false, 'message': data['message'] ?? 'Failed to add line'};
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  // DEVICES - ADDITIONAL
  static Future<Map<String, dynamic>> assignDeviceToLine(String deviceId, String? lineId) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/devices/$deviceId/assign-line'),
        headers: _authHeaders(),
        body: jsonEncode({'assigned_line_id': lineId})
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'data': data};
      return {'success': false, 'message': data['message'] ?? 'Failed to assign line'};
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  static Future<Map<String, dynamic>> issueDevice(String deviceId, String employeeId, String remarks) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/devices/issue'),
        headers: _authHeaders(),
        body: jsonEncode({'device_id': deviceId, 'employee_id': employeeId, 'remarks': remarks})
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 201) return {'success': true, 'data': data};
      return {'success': false, 'message': data['message'] ?? 'Failed to issue device'};
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  static Future<Map<String, dynamic>> returnDevice(String assignmentId, String remarks) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/devices/return'),
        headers: _authHeaders(),
        body: jsonEncode({'assignment_id': assignmentId, 'remarks': remarks})
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'data': data};
      return {'success': false, 'message': data['message'] ?? 'Failed to return device'};
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  // SESSIONS
  static Future<Map<String, dynamic>> fetchSessions({String status = 'live'}) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/sessions?status=$status'), headers: _authHeaders());
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'data': data};
      return {'success': false, 'message': data['message'] ?? 'Failed to load sessions'};
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }


}
