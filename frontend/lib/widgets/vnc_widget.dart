import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class VncWidget extends ConsumerStatefulWidget {
  const VncWidget({super.key});

  @override
  ConsumerState<VncWidget> createState() => _VncWidgetState();
}

class _VncWidgetState extends ConsumerState<VncWidget> {
  bool _isInitialized = false;
  bool _isConnecting = false;
  String? _errorMessage;
  final String _viewId = 'vnc-${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _initializeVnc();
  }

  Future<void> _initializeVnc() async {
    if (_isInitialized) return;

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      final token = ref.read(authProvider).token;
      final user = ref.read(authProvider).user;
      
      if (token == null) {
        throw Exception('Not authenticated');
      }

      // Get user's SSH connection info for VNC
      final ipaddress = user?['ipaddress']?.toString() ?? '';
      final vncPort = user?['vnc_port']?.toString() ?? '5900'; // Default VNC port
      
      if (ipaddress.isEmpty) {
        throw Exception('Server IP address not configured');
      }

      // Get WebSocket URL from backend for VNC proxy
      final baseUrl = ApiService.baseUrl;
      
      // Handle both relative and absolute URLs
      String wsUrl;
      if (baseUrl.startsWith('http://') || baseUrl.startsWith('https://')) {
        // Absolute URL
        final uri = Uri.parse(baseUrl);
        final protocol = uri.scheme == 'https' ? 'wss' : 'ws';
        final host = uri.host;
        final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
        // Use VNC WebSocket proxy endpoint
        wsUrl = '$protocol://$host:$port/api/vnc/ws?token=${Uri.encodeComponent(token)}&host=${Uri.encodeComponent(ipaddress)}&port=${Uri.encodeComponent(vncPort)}';
      } else {
        // Relative URL - use current window location
        final currentUrl = html.window.location;
        final protocol = currentUrl.protocol == 'https:' ? 'wss' : 'ws';
        final host = currentUrl.host;
        final port = currentUrl.port.isNotEmpty ? currentUrl.port : (currentUrl.protocol == 'https:' ? '443' : '80');
        wsUrl = '$protocol://$host:$port/api/vnc/ws?token=${Uri.encodeComponent(token)}&host=${Uri.encodeComponent(ipaddress)}&port=${Uri.encodeComponent(vncPort)}';
      }

      // Create HTML content with noVNC
      final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>VNC Viewer</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@novnc/core@1.4.0/lib/styles/base.css" />
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    body {
      margin: 0;
      padding: 0;
      background: #000000;
      overflow: hidden;
      width: 100%;
      height: 100vh;
      font-family: -apple-system, BlinkMacSystemFont, "SF Mono", Monaco, "Cascadia Code", "Roboto Mono", Consolas, "Courier New", monospace;
    }
    #noVNC_screen {
      width: 100%;
      height: 100vh;
      background: #000000;
    }
    .noVNC_status {
      color: #ffffff;
      background: #1a1a1a;
      padding: 8px 12px;
      font-size: 12px;
    }
    .noVNC_status_bar {
      background: #2d2d2d;
      border-top: 1px solid rgba(255, 255, 255, 0.1);
    }
  </style>
</head>
<body>
  <div id="noVNC_screen" style="width: 100%; height: 100%;"></div>
  <script src="https://cdn.jsdelivr.net/npm/@novnc/core@1.4.0/lib/rfb.js"></script>
  <script>
    (function() {
      const wsUrl = '$wsUrl';
      const screen = document.getElementById('noVNC_screen');
      
      // Wait for script to load
      function initVNC() {
        if (typeof RFB === 'undefined' && typeof window.RFB === 'undefined') {
          setTimeout(initVNC, 100);
          return;
        }
        
        const RFBClass = typeof RFB !== 'undefined' ? RFB : window.RFB;
        
        try {
          // Create RFB connection
          const rfb = new RFBClass(screen, wsUrl, {
            credentials: {
              password: '' // VNC password if needed
            },
            scaleViewport: true,
            resizeSession: true,
            showDotCursor: true,
            background: '#000000',
            qualityLevel: 6,
            compressionLevel: 2
          });
          
          // Handle connection events
          rfb.addEventListener('connect', function() {
            console.log('VNC connected');
          });
          
          rfb.addEventListener('disconnect', function(e) {
            if (e.detail && e.detail.clean) {
              console.log('VNC disconnected cleanly');
            } else {
              console.error('VNC disconnected unexpectedly:', e.detail);
            }
          });
          
          rfb.addEventListener('credentialsrequired', function() {
            console.log('VNC credentials required');
          });
          
          rfb.addEventListener('securityfailure', function(e) {
            console.error('VNC security failure:', e.detail);
            screen.innerHTML = '<div style="color: #ff4444; padding: 20px; text-align: center; font-family: monospace;">VNC Security Failure: ' + (e.detail?.reason || 'Unknown error') + '</div>';
          });
          
          // Handle clipboard and viewport
          rfb.clipViewport = true;
          rfb.dragViewport = true;
          
          console.log('VNC viewer initialized, connecting to:', wsUrl);
        } catch (error) {
          console.error('Error initializing VNC:', error);
          screen.innerHTML = '<div style="color: #ff4444; padding: 20px; text-align: center; font-family: monospace;">Error initializing VNC: ' + error.message + '</div>';
        }
      }
      
      // Start initialization
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initVNC);
      } else {
        initVNC();
      }
      
      // Focus the screen on click
      screen.addEventListener('click', function() {
        screen.focus();
      });
    })();
  </script>
</body>
</html>
''';

      // Create blob URL for HTML content
      final blob = html.Blob([htmlContent], 'text/html');
      final url = html.Url.createObjectUrlFromBlob(blob);

      // Create iframe element
      final iframe = html.IFrameElement()
        ..src = url
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.border = 'none';

      // Register the platform view
      ui_web.platformViewRegistry.registerViewFactory(
        _viewId,
        (int viewId) => iframe,
      );

      setState(() {
        _isInitialized = true;
        _isConnecting = false;
      });
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isConnecting) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Connecting to remote desktop...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              'Error connecting to VNC',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.red,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isInitialized = false;
                  _errorMessage = null;
                });
                _initializeVnc();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // Use HtmlElementView to embed the iframe
    return HtmlElementView(viewType: _viewId);
  }
}

