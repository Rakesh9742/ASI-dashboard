import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Backend URL - Use full URL for local development, relative for production
  // In development (Flutter dev server), use http://localhost:3000/api
  // In production (nginx), use relative /api which nginx proxies
  static String get baseUrl {
    // Check if we're running in a browser (web)
    // In Flutter web dev server, we need to use full backend URL
    // In production builds served by nginx, use relative URLs
    try {
      // Check if we're in development by looking at the current URL
      // If running on localhost with a high port (Flutter dev server), use full URL
      final uri = Uri.base;
      if (uri.host == 'localhost' && uri.port > 8000) {
        // Flutter dev server - use full backend URL
        return 'http://localhost:3000/api';
      }
    } catch (e) {
      // If we can't determine, default to relative URL
    }
    // Production mode or Docker - use relative URL (nginx will proxy)
    return '/api';
  }

  // Helper method to get headers with optional token
  Map<String, String> _getHeaders({String? token}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // Health check
  Future<Map<String, dynamic>> healthCheck() async {
    try {
      // Use full URL in development, relative in production
      final uri = Uri.base;
      final healthUrl = (uri.host == 'localhost' && uri.port > 8000) 
          ? 'http://localhost:3000/health' 
          : '/health';
      final response = await http.get(Uri.parse(healthUrl));
      return json.decode(response.body);
    } catch (e) {
      throw Exception('Failed to connect to backend: $e');
    }
  }

  // Chips
  Future<List<dynamic>> getChips() async {
    final response = await http.get(Uri.parse('$baseUrl/chips'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load chips');
    }
  }

  Future<Map<String, dynamic>> getChip(int id) async {
    final response = await http.get(Uri.parse('$baseUrl/chips/$id'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load chip');
    }
  }

  Future<Map<String, dynamic>> createChip(Map<String, dynamic> chip) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chips'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(chip),
    );
    if (response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to create chip');
    }
  }

  Future<Map<String, dynamic>> updateChip(int id, Map<String, dynamic> chip) async {
    final response = await http.put(
      Uri.parse('$baseUrl/chips/$id'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(chip),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to update chip');
    }
  }

  Future<void> deleteChip(int id) async {
    final response = await http.delete(Uri.parse('$baseUrl/chips/$id'));
    if (response.statusCode != 200) {
      throw Exception('Failed to delete chip');
    }
  }

  // Designs
  Future<List<dynamic>> getDesigns() async {
    final response = await http.get(Uri.parse('$baseUrl/designs'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load designs');
    }
  }

  Future<Map<String, dynamic>> getDesign(int id) async {
    final response = await http.get(Uri.parse('$baseUrl/designs/$id'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load design');
    }
  }

  Future<Map<String, dynamic>> createDesign(Map<String, dynamic> design) async {
    final response = await http.post(
      Uri.parse('$baseUrl/designs'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(design),
    );
    if (response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to create design');
    }
  }

  // Projects
  Future<List<dynamic>> getProjects({String? token}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/projects'),
      headers: _getHeaders(token: token),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to load projects');
    }
  }

  Future<Map<String, dynamic>> createProject({
    required String name,
    required String technologyNode,
    required List<int> domainIds,
    String? client,
    String? startDate,
    String? targetDate,
    String? plan,
    String? token,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/projects'),
      headers: _getHeaders(token: token),
      body: json.encode({
        'name': name,
        'client': client,
        'technology_node': technologyNode,
        'start_date': startDate,
        'target_date': targetDate,
        'plan': plan,
        'domain_ids': domainIds,
      }),
    );

    if (response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to create project');
    }
  }

  // Delete project (admin only)
  Future<void> deleteProject(int projectId, {String? token}) async {
    try {
      final url = '$baseUrl/projects/$projectId';
      print('Deleting project: $url');
      
      final response = await http.delete(
        Uri.parse(url),
        headers: _getHeaders(token: token),
      );

      print('Delete response status: ${response.statusCode}');
      print('Delete response body: ${response.body}');

      if (response.statusCode == 200) {
        return;
      } else if (response.statusCode == 404) {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Project not found');
      } else if (response.statusCode == 403) {
        throw Exception('Access denied. Admin role required.');
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to delete project');
      }
    } catch (e) {
      print('Error in deleteProject: $e');
      rethrow;
    }
  }

  // Dashboard stats
  Future<Map<String, dynamic>> getDashboardStats() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/dashboard/stats'));
      
      // Check if response is JSON
      if (response.headers['content-type']?.contains('application/json') != true) {
        // If not JSON, likely an HTML error page
        throw Exception('Backend server returned non-JSON response. Is the server running?');
      }
      
      if (response.statusCode == 200) {
        try {
          return json.decode(response.body);
        } catch (e) {
          // Response body is not valid JSON
          throw Exception('Invalid JSON response from server: ${response.body.substring(0, 100)}...');
        }
      } else {
        // Try to parse error response
        try {
          final error = json.decode(response.body);
          throw Exception(error['error'] ?? 'Failed to load dashboard stats');
        } catch (e) {
          throw Exception('Failed to load dashboard stats (Status: ${response.statusCode})');
        }
      }
    } catch (e) {
      if (e.toString().contains('Failed host lookup') || 
          e.toString().contains('Connection refused') ||
          e.toString().contains('Network is unreachable')) {
        throw Exception('Cannot connect to backend server. Please make sure the backend is running on port 3000.');
      }
      rethrow;
    }
  }

  // Authentication
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
        }),
      );
      
      // Check if response is JSON
      if (response.headers['content-type']?.contains('application/json') != true) {
        throw Exception('Backend server returned non-JSON response. Is the server running?');
      }
      
      if (response.statusCode == 200) {
        try {
          return json.decode(response.body);
        } catch (e) {
          throw Exception('Invalid JSON response from server');
        }
      } else {
        try {
          final error = json.decode(response.body);
          throw Exception(error['error'] ?? 'Login failed');
        } catch (e) {
          throw Exception('Login failed (Status: ${response.statusCode})');
        }
      }
    } catch (e) {
      if (e.toString().contains('Failed host lookup') || 
          e.toString().contains('Connection refused') ||
          e.toString().contains('Network is unreachable')) {
        throw Exception('Cannot connect to backend server. Please make sure the backend is running on port 3000.');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    String? fullName,
    String? role,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'username': username,
        'email': email,
        'password': password,
        if (fullName != null) 'full_name': fullName,
        if (role != null) 'role': role,
      }),
    );
    
    if (response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Registration failed');
    }
  }

  // Get all users (admin only) - requires authentication token
  Future<List<dynamic>> getUsers({String? token}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/users'),
      headers: _getHeaders(token: token),
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to load users');
    }
  }

  // Get all domains (public endpoint, token optional)
  Future<List<dynamic>> getDomains({String? token}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/domains'),
        headers: _getHeaders(token: token),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Domains API response: $data'); // Debug log
        return data;
      } else {
        final error = json.decode(response.body);
        print('Domains API error: ${error['error']}'); // Debug log
        throw Exception(error['error'] ?? 'Failed to load domains');
      }
    } catch (e) {
      print('Domains API exception: $e'); // Debug log
      rethrow;
    }
  }

  // Create user (admin only)
  Future<Map<String, dynamic>> createUser({
    required String username,
    required String email,
    required String password,
    String? fullName,
    String? role,
    int? domainId,
    String? token,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: _getHeaders(token: token),
      body: json.encode({
        'username': username,
        'email': email,
        'password': password,
        if (fullName != null) 'full_name': fullName,
        if (role != null) 'role': role,
        if (domainId != null) 'domain_id': domainId,
      }),
    );
    
    if (response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to create user');
    }
  }

  // Zoho Integration Methods
  Future<Map<String, dynamic>> getZohoAuthUrl({String? token}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/zoho/auth'),
      headers: _getHeaders(token: token),
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to get Zoho auth URL');
    }
  }

  // Zoho OAuth Login (no token required)
  Future<Map<String, dynamic>> getZohoLoginAuthUrl() async {
    final response = await http.get(
      Uri.parse('$baseUrl/zoho/login-auth'),
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to get Zoho login URL');
    }
  }

  Future<Map<String, dynamic>> getZohoStatus({String? token}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/zoho/status'),
      headers: _getHeaders(token: token),
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to get Zoho status');
    }
  }

  Future<List<dynamic>> getZohoPortals({String? token}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/zoho/portals'),
      headers: _getHeaders(token: token),
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to get Zoho portals');
    }
  }

  Future<Map<String, dynamic>> getZohoProjects({String? token, String? portalId}) async {
    final uri = portalId != null
        ? Uri.parse('$baseUrl/zoho/projects?portalId=$portalId')
        : Uri.parse('$baseUrl/zoho/projects');
    
    final response = await http.get(
      uri,
      headers: _getHeaders(token: token),
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to get Zoho projects');
    }
  }

  Future<Map<String, dynamic>> getZohoTasks({
    required String projectId,
    String? token,
    String? portalId,
  }) async {
    // Extract actual project ID if it's prefixed with "zoho_"
    final actualProjectId = projectId.startsWith('zoho_') 
        ? projectId.replaceFirst('zoho_', '') 
        : projectId;
    
    final uri = portalId != null
        ? Uri.parse('$baseUrl/zoho/projects/$actualProjectId/tasks?portalId=$portalId')
        : Uri.parse('$baseUrl/zoho/projects/$actualProjectId/tasks');
    
    final response = await http.get(
      uri,
      headers: _getHeaders(token: token),
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to get Zoho tasks');
    }
  }

  Future<void> disconnectZoho({String? token}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/zoho/disconnect'),
      headers: _getHeaders(token: token),
    );
    
    if (response.statusCode != 200) {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to disconnect Zoho');
    }
  }

  // Get projects with Zoho integration option
  Future<Map<String, dynamic>> getProjectsWithZoho({String? token, bool includeZoho = false}) async {
    final uri = includeZoho
        ? Uri.parse('$baseUrl/projects?includeZoho=true')
        : Uri.parse('$baseUrl/projects');
    
    final response = await http.get(
      uri,
      headers: _getHeaders(token: token),
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      // Handle different response formats
      if (data is Map) {
        final mapData = Map<String, dynamic>.from(data);
        // If response has 'all' key, use it; otherwise use the data directly
        if (mapData.containsKey('all')) {
          return mapData;
        } else if (mapData.containsKey('local') || mapData.containsKey('zoho')) {
          return mapData;
        } else {
          // If it's a map but doesn't have expected keys, return as is
          return mapData;
        }
      } else if (data is List) {
        return {'all': data, 'local': data, 'zoho': []};
      }
      // Fallback: wrap in a map
      return {'all': [], 'local': [], 'zoho': []};
    } else {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to load projects');
    }
  }

  // EDA Output Files Methods
  Future<Map<String, dynamic>> getEdaFiles({
    String? token,
    String? projectName,
    String? domainName,
    int? projectId,
    int? domainId,
    String? processingStatus,
    String? filePath,
    int limit = 50,
    int offset = 0,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    
    if (projectName != null) queryParams['project_name'] = projectName;
    if (domainName != null) queryParams['domain_name'] = domainName;
    if (projectId != null) queryParams['project_id'] = projectId.toString();
    if (domainId != null) queryParams['domain_id'] = domainId.toString();
    if (processingStatus != null) queryParams['processing_status'] = processingStatus;
    if (filePath != null) queryParams['file_path'] = filePath;

    final uri = Uri.parse('$baseUrl/eda-files').replace(queryParameters: queryParams);
    
    final response = await http.get(
      uri,
      headers: _getHeaders(token: token),
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to load EDA files');
    }
  }

  Future<Map<String, dynamic>> getEdaFile(int id, {String? token}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/eda-files/$id'),
      headers: _getHeaders(token: token),
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to load EDA file');
    }
  }

  Future<Map<String, dynamic>> uploadEdaFile(
    List<int> fileBytes,
    String fileName, {
    String? token,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/eda-files/upload'),
    );
    
    request.headers.addAll(_getHeaders(token: token));
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    if (response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to upload file');
    }
  }

  Future<Map<String, dynamic>> getEdaFilesStats({String? token}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/eda-files/stats/summary'),
      headers: _getHeaders(token: token),
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to load stats');
    }
  }

  Future<Map<String, dynamic>> deleteEdaFile(int id, {String? token, bool deleteFile = false}) async {
    final uri = Uri.parse('$baseUrl/eda-files/$id').replace(
      queryParameters: {'deleteFile': deleteFile.toString()},
    );
    
    final response = await http.delete(
      uri,
      headers: _getHeaders(token: token),
    );
    
    if (response.statusCode != 200) {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Failed to delete file');
    }
    
    return json.decode(response.body);
  }
}

