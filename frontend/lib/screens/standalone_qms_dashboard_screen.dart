import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import 'qms_dashboard_screen.dart';

class StandaloneQmsDashboardScreen extends ConsumerStatefulWidget {
  const StandaloneQmsDashboardScreen({super.key});

  @override
  ConsumerState<StandaloneQmsDashboardScreen> createState() => _StandaloneQmsDashboardScreenState();
}

class _StandaloneQmsDashboardScreenState extends ConsumerState<StandaloneQmsDashboardScreen> {
  final GlobalKey<QmsDashboardScreenState> _qmsKey = GlobalKey<QmsDashboardScreenState>();
  int? _blockId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadParams();
  }

  void _loadParams() {
    try {
      final url = html.window.location.href;
      int? blockId;

      if (url.contains('#/qms-dashboard') && url.contains('?')) {
        final queryPart = url.split('?')[1];
        final params = Uri.splitQueryString(queryPart);
        final blockIdStr = params['blockId'];
        if (blockIdStr != null) {
          blockId = int.tryParse(blockIdStr);
        }
      }

      if (blockId == null) {
        final storedBlockId = html.window.localStorage['standalone_qms_blockId'];
        if (storedBlockId != null) {
          blockId = int.tryParse(storedBlockId);
        }
      }

      setState(() {
        _blockId = blockId;
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
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading QMS...'),
            ],
          ),
        ),
      );
    }

    if (_blockId == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Block not found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('Unable to load QMS data'),
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

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
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
                const Icon(
                  Icons.fact_check,
                  size: 20,
                  color: Color(0xFF14B8A6),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'QMS Dashboard',
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
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () {
                    _qmsKey.currentState?.refreshData();
                  },
                  tooltip: 'Refresh',
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
          Expanded(
            child: QmsDashboardScreen(
              key: _qmsKey,
              blockId: _blockId!,
              isStandalone: true,
            ),
          ),
        ],
      ),
    );
  }
}

