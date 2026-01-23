import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../providers/auth_provider.dart';
import '../widgets/terminal_widget.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAuthFromLocalStorage();
  }

  Future<void> _loadAuthFromLocalStorage() async {
    // Check if we have auth data in localStorage (for standalone window)
    final storedToken = html.window.localStorage['terminal_auth_token'];
    final storedUser = html.window.localStorage['terminal_auth_user'];
    
    if (storedToken != null) {
      // Also save to SharedPreferences so auth provider can use it
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', storedToken);
        if (storedUser != null) {
          await prefs.setString('auth_user', storedUser);
        }
        
        // Update auth provider state
        final authNotifier = ref.read(authProvider.notifier);
        Map<String, dynamic>? user;
        if (storedUser != null) {
          try {
            user = json.decode(storedUser) as Map<String, dynamic>;
          } catch (e) {
            // Ignore JSON parse errors
          }
        }
        authNotifier.updateState(
          AuthState(
            isAuthenticated: true,
            token: storedToken,
            user: user,
          ),
        );
      } catch (e) {
        // Ignore errors
      }
    }
    
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0dbc79)),
              ),
              SizedBox(height: 16),
              Text(
                'Loading terminal...',
                style: TextStyle(
                  color: Color(0xFFe5e5e5),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1a1a1a),
      body: SafeArea(
        child: Column(
          children: [
            // Dark window title bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF2d2d2d),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // macOS traffic light buttons
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF5F57),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.black.withOpacity(0.3),
                            width: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFBD2E),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.black.withOpacity(0.3),
                            width: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFF28CA42),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.black.withOpacity(0.3),
                            width: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  // Window title
                  Expanded(
                    child: Center(
                      child: Text(
                        'Terminal',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 80), // Balance the traffic lights
                ],
              ),
            ),
            // Terminal widget with dark container
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF000000),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: const TerminalWidget(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

