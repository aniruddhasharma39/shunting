import 'dart:convert';
import 'package:http/http.dart' as http;
import 'user_session.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:5000/api';

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
        await UserSession().setFromLoginResponse(data);
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

  /// Fetch single session details with tabular telemetry logs
  static Future<Map<String, dynamic>> fetchSessionDetailsWithLogs(String sessionId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/sessions/$sessionId/logs'),
        headers: _authHeaders(),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'session': data['session'] ?? {},
          'logsCount': data['logsCount'] ?? 0,
          'tabularLogs': data['tabularLogs'] ?? []
        };
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to load session logs'};
    } catch (e) {
      return {'success': false, 'message': 'Network error fetching session logs.'};
    }
  }

  static String getSessionPdfUrl(String sessionId) {
    return '$baseUrl/reports/session/$sessionId/pdf';
  }

  static String getSessionExcelUrl(String sessionId) {
    return '$baseUrl/reports/session/$sessionId/excel';
  }

  static Future<Map<String, dynamic>> fetchTelemetryAudit(String deviceId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/iot/telemetry/$deviceId'), headers: _authHeaders());
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'data': data['data'] ?? []};
      return {'success': false, 'message': data['message'] ?? 'Failed to load telemetry audit'};
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  // DEVICE REGISTRY (HARDWARE CONSOLE / AWS IOT)
  static Future<Map<String, dynamic>> fetchDeviceRegistry({
    String? search,
    String? productType,
    String? healthStatus,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (search != null && search.trim().isNotEmpty) {
        queryParams['search'] = search.trim();
      }
      if (productType != null && productType != 'ALL') {
        queryParams['product_type'] = productType;
      }
      if (healthStatus != null && healthStatus != 'ALL') {
        queryParams['health_status'] = healthStatus;
      }

      final uri = Uri.parse('$baseUrl/device-registry').replace(queryParameters: queryParams.isEmpty ? null : queryParams);
      final response = await http.get(uri, headers: _authHeaders());
      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'summary': data['summary'] ?? {},
          'data': data['devices'] ?? [],
          'count': data['count'] ?? 0,
        };
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to load device registry'};
    } catch (e) {
      return {'success': false, 'message': 'Network error connecting to Device Registry.'};
    }
  }

  static Future<Map<String, dynamic>> fetchDeviceRegistryDetail(String deviceId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/device-registry/$deviceId'),
        headers: _authHeaders(),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to load device details'};
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  static Future<Map<String, dynamic>> upsertDeviceRegistry(Map<String, dynamic> payload) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/device-registry'),
        headers: _authHeaders(),
        body: jsonEncode(payload),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 201 || response.statusCode == 200) {
        return {'success': true, 'data': data['device']};
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to save device'};
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  /// Delete device from device_registry and device_telemetry
  static Future<Map<String, dynamic>> deleteDeviceRegistry(String deviceId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/device-registry/$deviceId'),
        headers: _authHeaders(),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to delete device'};
    } catch (e) {
      return {'success': false, 'message': 'Network error deleting device.'};
    }
  }

  /// Fetch Live Telemetry stream (from device_telemetry table with topic support)
  static Future<Map<String, dynamic>> fetchLiveTelemetry({
    String? deviceId,
    String? topic,
    int limit = 60,
  }) async {
    try {
      final queryParams = <String, String>{
        'limit': limit.toString(),
      };
      if (deviceId != null && deviceId.trim().isNotEmpty && deviceId != 'ALL') {
        queryParams['device_id'] = deviceId.trim();
      }
      if (topic != null && topic.trim().isNotEmpty) {
        queryParams['topic'] = topic.trim();
      }

      final uri = Uri.parse('$baseUrl/device-registry/telemetry/live').replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: _authHeaders());
      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'count': data['count'] ?? 0,
          'activeDevicesCount': data['activeDevicesCount'] ?? 0,
          'devicesList': data['devicesList'] ?? [],
          'data': data['telemetry'] ?? [],
        };
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to load live telemetry'};
    } catch (e) {
      return {'success': false, 'message': 'Network error connecting to Live Telemetry stream.'};
    }
  }


  /// Ingest Telemetry record (for test simulator or direct uplink)
  static Future<Map<String, dynamic>> ingestDeviceTelemetry(Map<String, dynamic> payload) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/device-registry/telemetry'),
        headers: _authHeaders(),
        body: jsonEncode(payload),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 201 || response.statusCode == 200) {
        return {'success': true, 'data': data['data']};
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to ingest telemetry'};
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

}

