import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Change this to your backend URL
  // For local development: http://localhost:3000
  // For Docker: http://backend:3000
  // For production: your production URL
  static String get baseUrl {
    const envUrl = String.fromEnvironment('API_URL', defaultValue: '');
    if (envUrl.isNotEmpty) {
      return envUrl.endsWith('/api') ? envUrl : '$envUrl/api';
    }
    return 'http://localhost:3000/api';
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
      final healthUrl = baseUrl.replaceAll('/api', '');
      final response = await http.get(Uri.parse('$healthUrl/health'));
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
    final response = await http.get(Uri.parse('$baseUrl/dashboard/stats'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load dashboard stats');
    }
  }

  // Authentication
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'username': username,
        'password': password,
      }),
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['error'] ?? 'Login failed');
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
}

