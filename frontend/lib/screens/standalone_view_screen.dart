import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import 'view_screen.dart';

class StandaloneViewScreen extends ConsumerStatefulWidget {
  const StandaloneViewScreen({super.key});

  @override
  ConsumerState<StandaloneViewScreen> createState() => _StandaloneViewScreenState();
}

class _StandaloneViewScreenState extends ConsumerState<StandaloneViewScreen> {
  String? _projectName;
  String? _domainName;
  String? _viewType;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadParams();
  }

  void _loadParams() {
    try {
      // Get project data from URL hash or localStorage
      final url = html.window.location.href;
      Map<String, String>? params;
      
      // Check if URL has hash with query params
      if (url.contains('#/view')) {
        final hashPart = url.split('#/view')[1];
        if (hashPart.contains('?')) {
          final queryPart = hashPart.split('?')[1];
          params = Uri.splitQueryString(queryPart);
        }
      }
      
      // Try to get from localStorage first (most reliable)
      final storedData = html.window.localStorage['standalone_view'];
      if (storedData != null) {
        final data = jsonDecode(storedData) as Map<String, dynamic>;
        _projectName = data['project']?.toString();
        _domainName = data['domain']?.toString();
        _viewType = data['viewType']?.toString();
        print('🔵 [STANDALONE_VIEW] Loaded from localStorage - Project: $_projectName, Domain: $_domainName, ViewType: $_viewType');
      } else if (params != null) {
        _projectName = params['project'] != null ? Uri.decodeComponent(params['project']!) : null;
        _domainName = params['domain'] != null ? Uri.decodeComponent(params['domain']!) : null;
        _viewType = params['viewType'] != null ? Uri.decodeComponent(params['viewType']!) : 'engineer';
        print('🔵 [STANDALONE_VIEW] Loaded from URL params - Project: $_projectName, Domain: $_domainName, ViewType: $_viewType');
      }
      
      // Debug: Check what we have
      print('🔵 [STANDALONE_VIEW] Final values - Project: $_projectName, Domain: $_domainName, ViewType: $_viewType');

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
              const Text('Loading view...'),
            ],
          ),
        ),
      );
    }

    if (_projectName == null) {
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

    // Show ViewScreen with project, domain, and view type
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
                  Icons.visibility,
                  size: 20,
                  color: const Color(0xFF1E96B1),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_projectName ?? 'Project'} - View',
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
          // ViewScreen content
          Expanded(
            child: ViewScreen(
              initialProject: _projectName,
              initialDomain: _domainName,
              initialViewType: _viewType ?? 'engineer',
            ),
          ),
        ],
      ),
    );
  }
}

