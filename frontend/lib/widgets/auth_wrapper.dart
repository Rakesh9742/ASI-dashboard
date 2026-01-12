import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../screens/login_screen.dart';
import '../screens/main_navigation_screen.dart';
import '../screens/standalone_project_screen.dart';
import '../screens/standalone_view_screen.dart';

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    
    // Check if this is a standalone window
    final url = html.window.location.href;
    final isStandaloneProject = url.contains('#/project');
    final isStandaloneView = url.contains('#/view');

    // Show login if not authenticated
    if (!authState.isAuthenticated) {
      return const LoginScreen();
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

