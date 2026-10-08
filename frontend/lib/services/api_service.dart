import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'user_session.dart';

class ApiService {
  // Set to true to test with your local backend, false to use the AWS backend
  static const bool useLocalhost = false;

  // IMPORTANT:
  // - For Web/Chrome testing: '127.0.0.1' or 'localhost'
  // - For Android Emulator: '10.0.2.2'
  // - For Physical Phone (APK): Use your computer's WiFi IPv4 Address (e.g. '192.168.1.18')
  static const String localPort = '5000'; // Change to 3000 if your backend uses 3000

  static String get baseUrl {
    if (!useLocalhost) {
      return 'http://13.234.30.131:5000/api';
    }

    if (kIsWeb) {
      return 'http://127.0.0.1:$localPort/api';
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      // Use your computer's local IPv4 address so the physical phone can connect over Wi-Fi
      return 'http://192.168.1.18:$localPort/api';
    } else {
      return 'http://127.0.0.1:$localPort/api';
    }
  }

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
    bool isAdminCreatingUser = false,
    List<String>? assignedZones,
    List<String>? assignedDivisions,
    List<String>? assignedYards,
    String? parentZone,
  }) async {
    try {
      final headers = isAdminCreatingUser ? _authHeaders() : {'Content-Type': 'application/json'};
      
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: headers,
        body: jsonEncode({
          'fullName': fullName,
          'employeeId': employeeId,
          'email': email,
          'designation': designation,
          'password': password,
          'isAdminCreatingUser': isAdminCreatingUser,
          if (assignedZones != null) 'assignedZones': assignedZones,
          if (assignedDivisions != null) 'assignedDivisions': assignedDivisions,
          if (assignedYards != null) 'assignedYards': assignedYards,
          if (parentZone != null) 'parentZone': parentZone,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Registration failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
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
      ).timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Store user session data (role, assigned yards, token)
        await UserSession().setFromLoginResponse(data);
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Login failed'};
      }
    } on Exception catch (e) {
      if (e.toString().contains('TimeoutException')) {
        return {'success': false, 'message': 'Login timed out. Server may be slow — please try again.'};
      }
      return {'success': false, 'message': 'Network error. Please check your connection.'};
    }
  }

  /// Fetch current user profile with role and assigned yards
  static Future<Map<String, dynamic>> fetchMe() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/me'),
        headers: _authHeaders(),
      ).timeout(const Duration(seconds: 30));

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
      ).timeout(const Duration(seconds: 30));

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
      ).timeout(const Duration(seconds: 30));

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

  /// Fetch all distinct zones (from zone admins) for dropdowns
  static Future<List<String>> fetchZones() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/auth/zones'), headers: _authHeaders());
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<String>.from(data['zones'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  /// Fetch all distinct divisions (from division admins) for dropdowns
  static Future<List<String>> fetchDivisions() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/auth/divisions'), headers: _authHeaders());
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<String>.from(data['divisions'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  /// Remove a zone assignment from a user
  static Future<Map<String, dynamic>> removeZoneAssignment({required String userId, required String zoneName}) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/auth/users/$userId/zone/${Uri.encodeComponent(zoneName)}'),
        headers: _authHeaders(),
      );
      final data = jsonDecode(response.body);
      return {'success': response.statusCode == 200, 'message': data['message'] ?? 'Done'};
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  /// Remove a division assignment from a user
  static Future<Map<String, dynamic>> removeDivisionAssignment({required String userId, required String divisionName}) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/auth/users/$userId/division/${Uri.encodeComponent(divisionName)}'),
        headers: _authHeaders(),
      );
      final data = jsonDecode(response.body);
      return {'success': response.statusCode == 200, 'message': data['message'] ?? 'Done'};
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

  /// Delete a yard (Super Admin only)
  static Future<Map<String, dynamic>> deleteYard(String yardId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/yards/$yardId'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'message': 'Yard deleted successfully'};
      }
      final data = jsonDecode(response.body);
      return {'success': false, 'message': data['message'] ?? 'Failed to delete yard'};
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  /// Delete a yard line (Super Admin only)
  static Future<Map<String, dynamic>> deleteYardLine(String yardId, String lineId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/yards/$yardId/lines/$lineId'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'message': 'Yard line deleted successfully'};
      }
      final data = jsonDecode(response.body);
      return {'success': false, 'message': data['message'] ?? 'Failed to delete yard line'};
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

  /// Delete a user (Super Admin only)
  static Future<Map<String, dynamic>> deleteUser(String userId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/auth/users/$userId'),
        headers: _authHeaders(),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message'] ?? 'User deleted'};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Delete failed'};
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
      ).timeout(const Duration(seconds: 30));

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
      ).timeout(const Duration(seconds: 30));

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



  static Future<Map<String, dynamic>> createYard(String yardName, String location) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/yards'),
        headers: _authHeaders(),
        body: jsonEncode({'yard_name': yardName, 'location': location})
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
        body: jsonEncode({'device_id': deviceId, 'employee_id': employeeId, 'remarks': remarks, 'issue_type': 'REGISTERED'})
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 201) return {'success': true, 'data': data};
      return {'success': false, 'message': data['message'] ?? 'Failed to issue device'};
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  static Future<Map<String, dynamic>> issueDeviceToUnregistered({
    required String deviceId,
    required String fullName,
    required String mobileNumber,
    required XFile userPhoto,
    required XFile idCardPhoto,
  }) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/devices/issue'));
      
      final token = UserSession().token;
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.fields['device_id'] = deviceId;
      request.fields['issue_type'] = 'UNREGISTERED';
      request.fields['full_name'] = fullName;
      request.fields['mobile_number'] = mobileNumber;

      final userPhotoBytes = await userPhoto.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes('user_photo', userPhotoBytes, filename: userPhoto.name));

      final idCardPhotoBytes = await idCardPhoto.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes('id_card_photo', idCardPhotoBytes, filename: idCardPhoto.name));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      var data = jsonDecode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        return {'success': true, 'data': data};
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to issue device'};
    } catch (e) {
      return {'success': false, 'message': 'Network error during issue.'};
    }
  }

  static Future<Map<String, dynamic>> returnDevice(String assignmentId, String remarks, {String? faultReported}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/devices/return'),
        headers: _authHeaders(),
        body: jsonEncode({'assignment_id': assignmentId, 'remarks': remarks, 'fault_reported': faultReported})
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'data': data};
      return {'success': false, 'message': data['message'] ?? 'Failed to return device'};
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  static Future<Map<String, dynamic>> fetchDeviceAssignments({String? startDate, String? endDate, List<String>? devices}) async {
    try {
      List<String> queries = [];
      if (startDate != null && endDate != null) {
        queries.add('startDate=$startDate');
        queries.add('endDate=$endDate');
      }
      if (devices != null && devices.isNotEmpty) {
        queries.add('devices=${devices.join(',')}');
      }
      final queryString = queries.isNotEmpty ? '?${queries.join('&')}' : '';
      
      final response = await http.get(Uri.parse('$baseUrl/devices/assignments$queryString'), headers: _authHeaders());
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'data': data['data'] ?? data};
      return {'success': false, 'message': data['message'] ?? 'Failed to load assignments'};
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  static String getDeviceHistoryPdfUrl({String? startDate, String? endDate, List<String>? devices}) {
    final filters = <String, dynamic>{};
    if (startDate != null) filters['fromDate'] = startDate;
    if (endDate != null) filters['toDate'] = endDate;
    if (devices != null && devices.isNotEmpty) filters['deviceCodes'] = devices;
    
    final filterStr = Uri.encodeComponent(jsonEncode(filters));
    final token = UserSession().token ?? '';
    return '$baseUrl/reports/generate/pdf?token=$token&reportType=Device%20History&filters=$filterStr';
  }

  static String getDeviceHistoryExcelUrl({String? startDate, String? endDate, List<String>? devices}) {
    final filters = <String, dynamic>{};
    if (startDate != null) filters['fromDate'] = startDate;
    if (endDate != null) filters['toDate'] = endDate;
    if (devices != null && devices.isNotEmpty) filters['deviceCodes'] = devices;
    
    final filterStr = Uri.encodeComponent(jsonEncode(filters));
    final token = UserSession().token ?? '';
    return '$baseUrl/reports/generate/excel?token=$token&reportType=Device%20History&filters=$filterStr';
  }

  // SESSIONS
  static Future<Map<String, dynamic>> fetchSessions({String status = 'live', String? yard, String? pilot}) async {
    try {
      String query = 'status=$status';
      if (yard != null && yard.isNotEmpty) query += '&yard=${Uri.encodeComponent(yard)}';
      if (pilot != null && pilot.isNotEmpty) query += '&pilot=${Uri.encodeComponent(pilot)}';
      
      final response = await http.get(Uri.parse('$baseUrl/sessions?$query'), headers: _authHeaders()).timeout(const Duration(seconds: 30));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'data': data};
      return {'success': false, 'message': data['message'] ?? 'Failed to load sessions'};
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

  static Future<Map<String, dynamic>> fetchSessionFilterOptions() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/sessions/filters/options'), headers: _authHeaders());
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'data': data};
      return {'success': false, 'message': data['message'] ?? 'Failed to load filter options'};
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
    final token = UserSession().token ?? '';
    return '$baseUrl/reports/session/$sessionId/pdf?token=$token';
  }

  static String getSessionExcelUrl(String sessionId) {
    final token = UserSession().token ?? '';
    return '$baseUrl/reports/session/$sessionId/excel?token=$token';
  }

  static String getRangeReportPdfUrl(String fromDate, String toDate) {
    final token = UserSession().token ?? '';
    return '$baseUrl/reports/range/pdf?from_date=$fromDate&to_date=$toDate&token=$token';
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

  static Future<Map<String, dynamic>> upsertDeviceRegistryWithImages({
    required Map<String, dynamic> payload,
    XFile? deviceImage,
    XFile? deviceSim,
  }) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/device-registry'));
      
      final token = UserSession().token;
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      // Add payload fields
      payload.forEach((key, value) {
        if (value != null) {
          if (value is List || value is Map) {
            request.fields[key] = jsonEncode(value);
          } else {
            request.fields[key] = value.toString();
          }
        }
      });

      // Add files safely for web
      if (deviceImage != null) {
        final bytes = await deviceImage.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes('device_image', bytes, filename: deviceImage.name));
      }
      
      if (deviceSim != null) {
        final bytes = await deviceSim.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes('device_sim', bytes, filename: deviceSim.name));
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      var data = jsonDecode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        return {'success': true, 'data': data['device']};
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to save device'};
    } catch (e) {
      return {'success': false, 'message': 'Network error during upload.'};
    }
  }

  static Future<Map<String, dynamic>> uploadDeviceImages({
    required String deviceId,
    XFile? deviceImage,
    XFile? deviceSim,
  }) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/device-registry/$deviceId/images'));
      
      final token = UserSession().token;
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      // Add files safely for web
      if (deviceImage != null) {
        final bytes = await deviceImage.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes('device_image', bytes, filename: deviceImage.name));
      }
      
      if (deviceSim != null) {
        final bytes = await deviceSim.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes('device_sim', bytes, filename: deviceSim.name));
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      var data = jsonDecode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        return {'success': true, 'data': data['device']};
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to upload images'};
    } catch (e) {
      return {'success': false, 'message': 'Network error during upload.'};
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

  /// Toggle device disabled/enabled status in device registry
  static Future<Map<String, dynamic>> toggleDeviceDisabled(String deviceId) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/device-registry/$deviceId/toggle-disabled'),
        headers: _authHeaders(),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to toggle device state'};
    } catch (e) {
      return {'success': false, 'message': 'Network error.'};
    }
  }

}

