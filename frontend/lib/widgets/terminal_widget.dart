import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class TerminalWidget extends ConsumerStatefulWidget {
  const TerminalWidget({super.key});

  @override
  ConsumerState<TerminalWidget> createState() => _TerminalWidgetState();
}

class _TerminalWidgetState extends ConsumerState<TerminalWidget> {
  bool _isInitialized = false;
  bool _isConnecting = false;
  String? _errorMessage;
  final String _viewId = 'terminal-${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _initializeTerminal();
  }

  Future<void> _initializeTerminal() async {
    if (_isInitialized) return;

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      final token = ref.read(authProvider).token;
      if (token == null) {
        throw Exception('Not authenticated');
      }

      // Get WebSocket URL from backend
      final baseUrl = ApiService.baseUrl;
      
      // Handle both relative and absolute URLs
      String wsUrl;
      if (baseUrl.startsWith('http://') || baseUrl.startsWith('https://')) {
        // Absolute URL
        final uri = Uri.parse(baseUrl);
        final protocol = uri.scheme == 'https' ? 'wss' : 'ws';
        final host = uri.host;
        final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
        wsUrl = '$protocol://$host:$port/api/terminal/ws?token=${Uri.encodeComponent(token)}';
      } else {
        // Relative URL - use current window location
        final currentUrl = html.window.location;
        final protocol = currentUrl.protocol == 'https:' ? 'wss' : 'ws';
        final host = currentUrl.host;
        final port = currentUrl.port.isNotEmpty ? currentUrl.port : (currentUrl.protocol == 'https:' ? '443' : '80');
        wsUrl = '$protocol://$host:$port/api/terminal/ws?token=${Uri.encodeComponent(token)}';
      }

      // Create HTML content with xterm.js terminal
      final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Terminal</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/xterm@5.3.0/css/xterm.css" />
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
    #terminal {
      width: 100%;
      height: 100vh;
      padding: 12px 16px;
      background: #000000;
    }
    .xterm-viewport {
      background: #000000 !important;
    }
    .xterm-screen {
      background: #000000 !important;
    }
  </style>
</head>
<body>
  <div id="terminal"></div>
  <script src="https://cdn.jsdelivr.net/npm/xterm@5.3.0/lib/xterm.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/xterm-addon-fit@0.8.0/lib/xterm-addon-fit.js"></script>
  <script>
    const Terminal = window.Terminal;
    const FitAddon = window.FitAddon;
    
    const terminal = new Terminal({
      cursorBlink: true,
      fontSize: 13,
      fontFamily: '-apple-system, BlinkMacSystemFont, "SF Mono", Monaco, "Cascadia Code", "Roboto Mono", Consolas, "Courier New", monospace',
      fontWeight: 400,
      lineHeight: 1.4,
      letterSpacing: 0,
      theme: {
        background: '#000000',
        foreground: '#ffffff',
        cursor: '#ffffff',
        cursorAccent: '#000000',
        selection: '#264f78',
        selectionForeground: '#ffffff',
        black: '#000000',
        red: '#cd3131',
        green: '#0dbc79',
        yellow: '#e5e510',
        blue: '#2472c8',
        magenta: '#bc3fbc',
        cyan: '#11a8cd',
        white: '#e5e5e5',
        brightBlack: '#666666',
        brightRed: '#f14c4c',
        brightGreen: '#23d18b',
        brightYellow: '#f5f543',
        brightBlue: '#3b8eea',
        brightMagenta: '#d670d6',
        brightCyan: '#29b8db',
        brightWhite: '#e5e5e5'
      }
    });
    
    const fitAddon = new FitAddon.FitAddon();
    terminal.loadAddon(fitAddon);
    
    const terminalElement = document.getElementById('terminal');
    terminal.open(terminalElement);
    fitAddon.fit();
    
    // Connect to WebSocket
    const wsUrl = '$wsUrl';
    const ws = new WebSocket(wsUrl);
    
    ws.onopen = function() {
      // Request terminal size
      const cols = terminal.cols;
      const rows = terminal.rows;
      ws.send(JSON.stringify({ type: 'resize', cols: cols, rows: rows }));
    };
    
    ws.onmessage = function(event) {
      try {
        const message = JSON.parse(event.data);
        
        if (message.type === 'output') {
          // Write output directly to terminal
          terminal.write(message.data);
        } else if (message.type === 'connected') {
          // Don't show connection messages - let the shell prompt appear naturally
        } else if (message.type === 'error') {
          terminal.writeln('\\r\\n\\x1b[31mError: ' + message.message + '\\x1b[0m\\r\\n');
        }
      } catch (e) {
        console.error('Error parsing WebSocket message:', e);
        terminal.writeln('\\r\\n\\x1b[31mError parsing message\\x1b[0m\\r\\n');
      }
    };
    
    ws.onerror = function(error) {
      terminal.writeln('\\r\\n\\x1b[31mConnection error\\x1b[0m\\r\\n');
    };
    
    ws.onclose = function() {
      terminal.writeln('\\r\\n\\x1b[33mConnection closed\\x1b[0m\\r\\n');
    };
    
    // Send user input to server
    terminal.onData(function(data) {
      if (ws.readyState === WebSocket.OPEN) {
        console.log('Sending input to server:', data);
        ws.send(JSON.stringify({ type: 'input', data: data }));
      } else {
        terminal.writeln('\\r\\n\\x1b[31m✗ WebSocket not connected\\x1b[0m\\r\\n');
      }
    });
    
    // Handle window resize
    let resizeTimeout;
    window.addEventListener('resize', function() {
      clearTimeout(resizeTimeout);
      resizeTimeout = setTimeout(function() {
        fitAddon.fit();
        const cols = terminal.cols;
        const rows = terminal.rows;
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({ type: 'resize', cols: cols, rows: rows }));
        }
      }, 100);
    });
    
    // Focus terminal on load and ensure it stays focused
    setTimeout(function() {
      terminal.focus();
      // Also focus the terminal element
      terminalElement.focus();
    }, 100);
    
    // Re-focus on click to ensure keyboard input works
    terminalElement.addEventListener('click', function() {
      terminal.focus();
    });
    
    // Debug: Log WebSocket state
    console.log('Terminal initialized, WebSocket URL:', wsUrl);
    console.log('Terminal ready, waiting for connection...');
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
            Text('Connecting to terminal...'),
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
              'Error connecting to terminal',
              style: Theme.of(context).textTheme.titleLarge,
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
                _initializeTerminal();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    // Use HtmlElementView to embed the iframe
    return HtmlElementView(viewType: _viewId);
  }
}

