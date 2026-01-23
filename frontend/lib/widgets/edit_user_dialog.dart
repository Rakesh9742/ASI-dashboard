import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EditUserDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> user;
  final Function() onUserUpdated;

  const EditUserDialog({
    super.key,
    required this.user,
    required this.onUserUpdated,
  });

  @override
  ConsumerState<EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends ConsumerState<EditUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _sshUserController = TextEditingController();
  final _sshPasswordController = TextEditingController();
  
  final ApiService _apiService = ApiService();
  List<dynamic> _domains = [];
  String? _selectedRole;
  int? _selectedDomainId;
  bool? _isActive;
  bool _isLoading = false;
  bool _isLoadingDomains = true;
  bool _obscureSshPassword = true;

  final List<String> _roles = [
    'admin',
    'project_manager',
    'lead',
    'engineer',
    'customer',
  ];

  @override
  void initState() {
    super.initState();
    _initializeFields();
    _loadDomains();
  }

  void _initializeFields() {
    _nameController.text = widget.user['full_name'] ?? '';
    
    // Extract SSH username from email if not already set
    // Example: rakesh.p@sumedhait.com -> rakesh
    String sshUser = widget.user['ssh_user'] ?? '';
    if (sshUser.isEmpty) {
      final email = widget.user['email'] ?? '';
      if (email.isNotEmpty && email.contains('@')) {
        // Get part before @
        final emailPrefix = email.split('@').first;
        // Get first part before any dots
        sshUser = emailPrefix.split('.').first;
      }
    }
    _sshUserController.text = sshUser;
    
    _selectedRole = widget.user['role'];
    _selectedDomainId = widget.user['domain_id'];
    _isActive = widget.user['is_active'] ?? true;
  }

  Future<void> _loadDomains() async {
    setState(() {
      _isLoadingDomains = true;
    });
    
    try {
      final token = ref.read(authProvider.notifier).getToken();
      final domains = await _apiService.getDomains(token: token);
      setState(() {
        _domains = domains;
        _isLoadingDomains = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingDomains = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading domains: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sshUserController.dispose();
    _sshPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final token = ref.read(authProvider.notifier).getToken();
      await _apiService.updateUser(
        userId: widget.user['id'],
        fullName: _nameController.text.trim().isEmpty 
            ? null 
            : _nameController.text.trim(),
        role: _selectedRole,
        domainId: _selectedDomainId,
        isActive: _isActive,
        sshUser: _sshUserController.text.trim().isEmpty 
            ? null 
            : _sshUserController.text.trim(),
        sshPassword: _sshPasswordController.text.isEmpty 
            ? null 
            : _sshPasswordController.text,
        token: token,
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onUserUpdated();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating user: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Edit User',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Full Name
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Role Dropdown
                DropdownButtonFormField<String>(
                  value: _selectedRole,
                  decoration: InputDecoration(
                    labelText: 'Role *',
                    prefixIcon: const Icon(Icons.badge),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: _roles.map((role) {
                    return DropdownMenuItem(
                      value: role,
                      child: Text(role.replaceAll('_', ' ').toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedRole = value;
                    });
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Please select a role';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Domain Dropdown
                _isLoadingDomains
                    ? const LinearProgressIndicator()
                    : DropdownButtonFormField<int>(
                        value: _selectedDomainId,
                        decoration: InputDecoration(
                          labelText: 'Domain (Optional)',
                          prefixIcon: const Icon(Icons.category),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: [
                          const DropdownMenuItem<int>(
                            value: null,
                            child: Text('No domain'),
                          ),
                          ..._domains.map<DropdownMenuItem<int>>((domain) {
                            final domainId = domain['id'];
                            final domainCode = domain['code'] ?? '';
                            final domainName = domain['name'] ?? '';
                            
                            return DropdownMenuItem<int>(
                              value: domainId is int 
                                  ? domainId 
                                  : int.tryParse(domainId.toString()),
                              child: Text(
                                domainCode.isNotEmpty && domainName.isNotEmpty
                                    ? '$domainCode - $domainName'
                                    : domainName.isNotEmpty
                                        ? domainName
                                        : domainCode.isNotEmpty
                                            ? domainCode
                                            : 'Unknown Domain',
                              ),
                            );
                          }).toList(),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedDomainId = value;
                          });
                        },
                      ),
                const SizedBox(height: 16),
                // Active Status
                SwitchListTile(
                  title: const Text('Active'),
                  subtitle: const Text('User account status'),
                  value: _isActive ?? true,
                  onChanged: (value) {
                    setState(() {
                      _isActive = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                // SSH Credentials Section
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'SSH Credentials',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                // SSH User
                TextFormField(
                  controller: _sshUserController,
                  decoration: InputDecoration(
                    labelText: 'SSH Username',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    helperText: 'SSH login username',
                  ),
                ),
                const SizedBox(height: 16),
                // SSH Password
                TextFormField(
                  controller: _sshPasswordController,
                  decoration: InputDecoration(
                    labelText: 'SSH Password',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureSshPassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureSshPassword = !_obscureSshPassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    helperText: 'Leave empty to keep current password',
                  ),
                  obscureText: _obscureSshPassword,
                ),
                const SizedBox(height: 24),
                // Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _handleSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Update User'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

