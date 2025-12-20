import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class AuthState {
  final bool isAuthenticated;
  final String? token;
  final Map<String, dynamic>? user;

  AuthState({
    required this.isAuthenticated,
    this.token,
    this.user,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    String? token,
    Map<String, dynamic>? user,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      token: token ?? this.token,
      user: user ?? this.user,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiService _apiService;
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'auth_user';

  AuthNotifier(this._apiService) : super(AuthState(isAuthenticated: false)) {
    _loadAuthState();
  }

  Future<void> _loadAuthState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      final userJson = prefs.getString(_userKey);

      if (token != null && userJson != null) {
        try {
          final user = json.decode(userJson) as Map<String, dynamic>;
          state = AuthState(
            isAuthenticated: true,
            token: token,
            user: user,
          );
        } catch (e) {
          // If JSON parsing fails, just use token
          state = AuthState(
            isAuthenticated: true,
            token: token,
          );
        }
      }
    } catch (e) {
      // Ignore errors
    }
  }

  Future<bool> login(String username, String password) async {
    try {
      final result = await _apiService.login(username, password);
      
      if (result['token'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, result['token']);
        if (result['user'] != null) {
          await prefs.setString(_userKey, json.encode(result['user']));
        }

        state = AuthState(
          isAuthenticated: true,
          token: result['token'],
          user: result['user'] != null 
              ? Map<String, dynamic>.from(result['user'])
              : null,
        );
        return true;
      }
      return false;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);

    state = AuthState(isAuthenticated: false);
  }

  String? getToken() {
    return state.token;
  }
}

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(apiServiceProvider));
});

