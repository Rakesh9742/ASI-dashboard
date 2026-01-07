import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class ZohoIntegrationScreen extends ConsumerStatefulWidget {
  const ZohoIntegrationScreen({super.key});

  @override
  ConsumerState<ZohoIntegrationScreen> createState() => _ZohoIntegrationScreenState();
}

class _ZohoIntegrationScreenState extends ConsumerState<ZohoIntegrationScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  bool _isConnected = false;
  Map<String, dynamic>? _statusInfo;
  List<dynamic> _portals = [];

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    setState(() => _isLoading = true);
    try {
      final authState = ref.read(authProvider);
      final token = authState.token;
      
      if (token == null) {
        setState(() {
          _isLoading = false;
          _isConnected = false;
        });
        return;
      }

      final status = await _apiService.getZohoStatus(token: token);
      setState(() {
        _isConnected = status['connected'] ?? false;
        _statusInfo = status['token_info'];
      });

      if (_isConnected) {
        _loadPortals();
      }
    } catch (e) {
      setState(() {
        _isConnected = false;
        _isLoading = false;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPortals() async {
    try {
      final authState = ref.read(authProvider);
      final token = authState.token;
      
      if (token == null) return;

      final portals = await _apiService.getZohoPortals(token: token);
      setState(() => _portals = portals);
    } catch (e) {
      // Ignore errors
    }
  }

  Future<void> _connectZoho() async {
    setState(() => _isLoading = true);
    try {
      final authState = ref.read(authProvider);
      final token = authState.token;
      
      if (token == null) {
        _showError('Please log in first');
        return;
      }

      // Get authorization URL
      final response = await _apiService.getZohoAuthUrl(token: token);
      final authUrl = response['authUrl'] as String;

      // Open browser for OAuth
      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        
        // Show success message and check status after a delay
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please complete authorization in the browser, then return here'),
              duration: Duration(seconds: 5),
            ),
          );
          
          // Poll for status update
          Future.delayed(const Duration(seconds: 3), () {
            _checkStatus();
          });
        }
      } else {
        _showError('Could not open browser');
      }
    } catch (e) {
      _showError('Failed to connect: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _disconnectZoho() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Zoho?'),
        content: const Text('Are you sure you want to disconnect your Zoho Projects account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final authState = ref.read(authProvider);
      final token = authState.token;
      
      if (token == null) return;

      await _apiService.disconnectZoho(token: token);
      await _checkStatus();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Zoho Projects disconnected successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError('Failed to disconnect: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zoho Projects Integration'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Card
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: [Colors.blue.shade600, Colors.blue.shade400],
                        ),
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.cloud_sync,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Zoho Projects',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Sync your Zoho Projects',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Connection Status Card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _isConnected ? Icons.check_circle : Icons.cancel,
                                color: _isConnected ? Colors.green : Colors.red,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _isConnected ? 'Connected' : 'Not Connected',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: _isConnected ? Colors.green : Colors.red,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_isConnected && _statusInfo != null) ...[
                            _buildInfoRow('Expires At', _statusInfo!['expires_at_readable'] ?? 'N/A'),
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              'Time Until Expiry',
                              '${_statusInfo!['time_until_expiry_minutes'] ?? 0} minutes',
                            ),
                            const SizedBox(height: 16),
                          ],
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isConnected ? _disconnectZoho : _connectZoho,
                              icon: Icon(_isConnected ? Icons.link_off : Icons.link),
                              label: Text(_isConnected ? 'Disconnect' : 'Connect Zoho Projects'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isConnected ? Colors.red : Colors.blue.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Portals Section
                  if (_isConnected && _portals.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Your Portals',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    ..._portals.map((portal) => Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade100,
                              child: Icon(Icons.work, color: Colors.blue.shade700),
                            ),
                            title: Text(portal['name'] ?? 'Portal'),
                            subtitle: Text('ID: ${portal['id']}'),
                            trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
                          ),
                        )),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 14,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}









