import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../screens/login_screen.dart';
import '../screens/main_navigation_screen.dart';
import '../screens/standalone_project_screen.dart';
import '../screens/standalone_view_screen.dart';
import '../screens/terminal_screen.dart';
import '../screens/vnc_screen.dart';

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final apiService = ref.read(apiServiceProvider);
    // When session expires (401), logout and show login; user sees "Session expired" message
    apiService.onSessionExpired = () {
      ref.read(authProvider.notifier).logout();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session expired. You have been logged out. Please log in again.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
    };
    
    // Check if this is a standalone window
    final url = html.window.location.href;
    final isStandaloneProject = url.contains('#/project');
    final isStandaloneView = url.contains('#/view');
    final isTerminal = url.contains('#/terminal');
    final isVnc = url.contains('#/vnc');

    // Show login if not authenticated
    if (!authState.isAuthenticated) {
      return const LoginScreen();
    }
    
    // If terminal window, show terminal screen
    if (isTerminal) {
      return const TerminalScreen();
    }
    
    // If VNC window, show VNC screen
    if (isVnc) {
      return const VncScreen();
    }
    
    // If standalone project window, show project screen
    if (isStandaloneProject) {
      return const StandaloneProjectScreen();
    }
    
    // If standalone view window, show view screen
    if (isStandaloneView) {
      return const StandaloneViewScreen();
    }
    
    // Otherwise show main navigation
    return const MainNavigationScreen();
  }
}

