import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import 'semicon_dashboard_screen.dart';

class StandaloneProjectScreen extends ConsumerStatefulWidget {
  const StandaloneProjectScreen({super.key});

  @override
  ConsumerState<StandaloneProjectScreen> createState() => _StandaloneProjectScreenState();
}

class _StandaloneProjectScreenState extends ConsumerState<StandaloneProjectScreen> {
  Map<String, dynamic>? _project;
  String? _initialTab;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProject();
  }

  void _loadProject() {
    try {
      // Try to get from localStorage first (most reliable)
      final storedProject = html.window.localStorage['standalone_project'];
      if (storedProject != null) {
        _project = jsonDecode(storedProject) as Map<String, dynamic>;
      } else {
        // Get project data from URL hash parameters
        final url = html.window.location.href;
        Map<String, String>? params;
        
        // Check if URL has hash with query params
        if (url.contains('#/project')) {
          final hashPart = url.split('#/project')[1];
          if (hashPart.contains('?')) {
            final queryPart = hashPart.split('?')[1];
            params = Uri.splitQueryString(queryPart);
          }
        }
        
        if (params != null) {
          final projectId = params['projectId'];
          final projectName = params['projectName'];
          
          if (projectId != null) {
            // Try to get full project data from localStorage
            final fullProject = html.window.localStorage['project_$projectId'];
            if (fullProject != null) {
              _project = jsonDecode(fullProject) as Map<String, dynamic>;
            } else if (projectName != null) {
              // Create project object from URL params
              _project = {
                'id': projectId,
                'name': Uri.decodeComponent(projectName),
              };
            }
          }
        }
      }

      // Get initial tab from localStorage or URL
      final storedTab = html.window.localStorage['standalone_tab'];
      if (storedTab != null) {
        _initialTab = storedTab;
      } else {
        // Try to get from URL
        final url = html.window.location.href;
        if (url.contains('#/project')) {
          final hashPart = url.split('#/project')[1];
          if (hashPart.contains('?')) {
            final queryPart = hashPart.split('?')[1];
            final params = Uri.splitQueryString(queryPart);
            _initialTab = params['tab'];
          }
        }
      }

      if (_project == null) {
        // If no project data found, show error
        setState(() {
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check authentication
    final authState = ref.watch(authProvider);
    if (!authState.isAuthenticated) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Not authenticated',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('Please log in from the main window'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  html.window.close();
                },
                child: const Text('Close Window'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Loading project...'),
            ],
          ),
        ),
      );
    }

    if (_project == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Project not found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('Unable to load project data'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  html.window.close();
                },
                child: const Text('Close Window'),
              ),
            ],
          ),
        ),
      );
    }

    // Show project dashboard without navigation
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Minimal header with project name and close button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.folder,
                  size: 20,
                  color: const Color(0xFF1E96B1),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _project!['name'] ?? 'Project',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    html.window.close();
                  },
                  tooltip: 'Close window',
                ),
              ],
            ),
          ),
          // Project dashboard content
          Expanded(
            child: SemiconDashboardScreen(
              project: _project!,
              initialTab: _initialTab,
            ),
          ),
        ],
      ),
    );
  }
}

