import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import 'domain_plan_screen.dart';
import 'zoho_integration_screen.dart';

class ProjectManagementScreen extends ConsumerStatefulWidget {
  const ProjectManagementScreen({super.key});

  @override
  ConsumerState<ProjectManagementScreen> createState() => _ProjectManagementScreenState();
}

class _ProjectManagementScreenState extends ConsumerState<ProjectManagementScreen> {
  final ApiService _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _clientController = TextEditingController();
  final TextEditingController _technologyNodeController = TextEditingController();
  final TextEditingController _planController = TextEditingController();

  // Helper function to convert Map to YAML string
  String _mapToYaml(dynamic data, {int indent = 0}) {
    final indentStr = '  ' * indent;
    final buffer = StringBuffer();
    
    if (data is Map) {
      data.forEach((key, value) {
        if (value == null) {
          buffer.writeln('$indentStr${key}: null');
        } else if (value is Map) {
          buffer.writeln('$indentStr${key}:');
          buffer.write(_mapToYaml(value, indent: indent + 1));
        } else if (value is List) {
          buffer.writeln('$indentStr${key}:');
          for (var item in value) {
            if (item is Map) {
              buffer.writeln('$indentStr  -');
              buffer.write(_mapToYaml(item, indent: indent + 2));
            } else {
              buffer.writeln('$indentStr  - ${_escapeYamlValue(item)}');
            }
          }
        } else {
          buffer.writeln('$indentStr${key}: ${_escapeYamlValue(value)}');
        }
      });
    } else if (data is List) {
      for (var item in data) {
        if (item is Map) {
          buffer.writeln('$indentStr-');
          buffer.write(_mapToYaml(item, indent: indent + 1));
        } else {
          buffer.writeln('$indentStr- ${_escapeYamlValue(item)}');
        }
      }
    }
    
    return buffer.toString();
  }
  
  String _escapeYamlValue(dynamic value) {
    if (value == null) return 'null';
    final str = value.toString();
    // If value contains special characters, wrap in quotes
    if (str.contains(':') || str.contains('#') || str.contains('|') || 
        str.contains('&') || str.contains('*') || str.contains('!') ||
        str.contains('[') || str.contains(']') || str.contains('{') ||
        str.contains('}') || str.contains(',') || str.contains('`') ||
        str.contains("'") || str.contains('"') || str.contains('\n') ||
        str.startsWith(' ') || str.endsWith(' ') || str.isEmpty) {
      return '"${str.replaceAll('"', '\\"')}"';
    }
    return str;
  }

  DateTime? _startDate;
  DateTime? _targetDate;
  int _currentStep = 0;
  bool _isLoading = true;
  bool _isSubmitting = false;

  List<dynamic> _domains = [];
  List<int> _selectedDomainIds = [];
  List<dynamic> _projects = [];
  List<dynamic> _zohoProjects = [];
  bool _includeZoho = true; // Default to true - show Zoho projects if connected
  bool _isZohoConnected = false;
  final ScrollController _horizontalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _checkZohoStatus().then((_) {
      _loadDomainsAndProjects();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _clientController.dispose();
    _technologyNodeController.dispose();
    _planController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  Future<void> _checkZohoStatus() async {
    try {
      final authState = ref.read(authProvider);
      final token = authState.token;
      if (token == null) {
        setState(() {
          _isZohoConnected = false;
          _includeZoho = false;
        });
        return;
      }

      final status = await _apiService.getZohoStatus(token: token);
      setState(() {
        _isZohoConnected = status['connected'] ?? false;
        // Auto-include Zoho projects if connected
        _includeZoho = _isZohoConnected;
      });
    } catch (e) {
      setState(() {
        _isZohoConnected = false;
        _includeZoho = false;
      });
    }
  }

  Future<void> _loadDomainsAndProjects() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authState = ref.read(authProvider);
      final token = authState.token;

      final domains = await _apiService.getDomains(token: token);
      
      // Admin sees only Zoho projects - always request with includeZoho
      final userRole = ref.read(authProvider).user?['role'];
      final isAdmin = userRole == 'admin';
      
      Map<String, dynamic> projectsData;
      if (isAdmin || (_includeZoho && _isZohoConnected)) {
        projectsData = await _apiService.getProjectsWithZoho(token: token, includeZoho: true);
      } else {
        final projects = await _apiService.getProjects(token: token);
        projectsData = {'all': projects, 'local': projects, 'zoho': []};
      }

      setState(() {
        _domains = domains;
        _projects = projectsData['all'] ?? projectsData['local'] ?? [];
        _zohoProjects = projectsData['zoho'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading project data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickDate({
    required bool isStartDate,
  }) async {
    final now = DateTime.now();
    final initialDate = isStartDate
        ? (_startDate ?? now)
        : (_targetDate ?? _startDate ?? now.add(const Duration(days: 30)));
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );

    if (selected != null) {
      setState(() {
        if (isStartDate) {
          _startDate = selected;
        } else {
          _targetDate = selected;
        }
      });
    }
  }

  String? _formatDate(DateTime? date) {
    if (date == null) return null;
    return date.toIso8601String().split('T').first;
  }

  Future<void> _submitProject() async {
    if (!_formKey.currentState!.validate()) {
      setState(() {
        _currentStep = 0;
      });
      return;
    }

    if (_selectedDomainIds.isEmpty) {
      setState(() {
        _currentStep = 1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one domain'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final authState = ref.read(authProvider);
      final token = authState.token;

      final project = await _apiService.createProject(
        name: _nameController.text.trim(),
        client: _clientController.text.trim().isEmpty ? null : _clientController.text.trim(),
        technologyNode: _technologyNodeController.text.trim(),
        startDate: _formatDate(_startDate),
        targetDate: _formatDate(_targetDate),
        plan: _planController.text.trim().isEmpty ? null : _planController.text.trim(),
        domainIds: _selectedDomainIds,
        token: token,
      );

        setState(() {
        _projects = [project, ..._projects];
        _nameController.clear();
        _clientController.clear();
        _technologyNodeController.clear();
        _planController.clear();
        _startDate = null;
        _targetDate = null;
        _selectedDomainIds = [];
        _currentStep = 0;
      });

      if (mounted) {
        Navigator.of(context).pop(); // Close the dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Project created successfully'),
            backgroundColor: Colors.green,
      ),
    );
  }
    } catch (e) {
      if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create project: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isAuthenticated = authState.isAuthenticated;

    if (!isAuthenticated) {
      return const Center(child: Text('Please log in to manage projects.'));
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadDomainsAndProjects,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Project Management',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage and track your projects',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.settings),
                      tooltip: 'Zoho Integration Settings',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const ZohoIntegrationScreen(),
                          ),
                        ).then((_) {
                          _checkZohoStatus();
                          _loadDomainsAndProjects();
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 32),
            // Projects List Section
            Row(
              children: [
                Icon(Icons.folder_open, color: Colors.purple.shade600, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Projects',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_projects.length}',
                    style: TextStyle(
                      color: Colors.purple.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_includeZoho && _zohoProjects.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud, size: 16, color: Colors.blue.shade700),
                        const SizedBox(width: 4),
                        Text(
                          '${_zohoProjects.length} Zoho',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            if (_projects.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Icon(Icons.folder_open_outlined, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'No projects yet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Click "Create Project" to get started',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Scrollbar(
                  controller: _horizontalScrollController,
                  thumbVisibility: true,
                  thickness: 8,
                  radius: const Radius.circular(4),
                  child: SingleChildScrollView(
                    controller: _horizontalScrollController,
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                    headingRowColor: MaterialStateProperty.all(Colors.grey.shade900),
                    headingRowHeight: 56,
                    dataRowMinHeight: 64,
                    dataRowMaxHeight: 80,
                    columnSpacing: 24,
                    headingTextStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    columns: [
                      DataColumn(
                        label: Text('ID', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      DataColumn(
                        label: Text('Project Name', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      DataColumn(
                        label: Text('Technology', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      DataColumn(
                        label: Text('Source', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      DataColumn(
                        label: Text('Status', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      DataColumn(
                        label: Text('Start Date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      DataColumn(
                        label: Text('Due Date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      DataColumn(
                        label: Text('Duration', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      DataColumn(
                        label: Text('Owner', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      DataColumn(
                        label: Text('Created By', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      DataColumn(
                        label: Text('Completion %', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      DataColumn(
                        label: Text('Work Hours', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      DataColumn(
                        label: Text('Priority', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      DataColumn(
                        label: Text('Team', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      DataColumn(
                        label: Text('Billing Type', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      DataColumn(
                        label: Text('Timelog Total', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      DataColumn(
                        label: Text('Domains', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      if (authState.user?['role'] == 'admin')
                        DataColumn(
                          label: Text('Actions', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                    ],
                    rows: _projects.map((project) {
                      final isZohoProject = project['source'] == 'zoho';
                      final isMapped = project['is_mapped'] == true;
                      final zohoData = project['zoho_data'] as Map<String, dynamic>?;
                      final projectId = project['id']?.toString() ?? 'N/A';
                      final projectName = project['name'] ?? 'Project';
                      final technology = project['technology_node'] ?? 'N/A';
                      final domains = (project['domains'] as List<dynamic>? ?? []);
                      final startDate = _formatDateForTable(project['start_date']);
                      final dueDate = _formatDateForTable(project['target_date']);
                      final duration = _calculateDuration(project['start_date'], project['target_date']);
                      
                      // Extract Zoho-specific fields
                      final owner = isZohoProject && zohoData != null 
                          ? (zohoData['owner_name'] ?? 'N/A').toString()
                          : 'N/A';
                      final createdBy = isZohoProject && zohoData != null
                          ? (zohoData['created_by_name'] ?? zohoData['created_by'] ?? 'N/A').toString()
                          : 'N/A';
                      final completionPercentage = isZohoProject && zohoData != null && zohoData['completion_percentage'] != null
                          ? '${zohoData['completion_percentage']}%'
                          : '-';
                      final workHours = isZohoProject && zohoData != null
                          ? (zohoData['work_hours_p'] ?? zohoData['work_hours'] ?? '00:00').toString()
                          : '-';
                      final priority = isZohoProject && zohoData != null && zohoData['priority'] != null
                          ? zohoData['priority'].toString()
                          : 'None';
                      final associatedTeam = isZohoProject && zohoData != null
                          ? (zohoData['team_name'] ?? zohoData['associated_team'] ?? 'Not Associated').toString()
                          : 'N/A';
                      final billingType = isZohoProject && zohoData != null && zohoData['billing_type'] != null
                          ? zohoData['billing_type'].toString()
                          : 'None';
                      final timelogTotal = isZohoProject && zohoData != null
                          ? (zohoData['timelog_total_t'] ?? zohoData['timelog_total'] ?? '00:00').toString()
                          : '-';
                      
                      return DataRow(
                        color: isMapped 
                          ? WidgetStateProperty.all(Colors.green.shade50.withOpacity(0.3))
                          : null,
                        cells: [
                          DataCell(
                            InkWell(
                              onTap: () => _showProjectDetails(project),
                              child: Text(
                                projectId.length > 12 ? '${projectId.substring(0, 12)}...' : projectId,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  color: Colors.grey.shade800,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            InkWell(
                              onTap: () => _showProjectDetails(project),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: isMapped 
                                        ? Colors.green.shade100
                                        : (isZohoProject ? Colors.blue.shade50 : Colors.purple.shade50),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(
                                      isMapped 
                                        ? Icons.check_circle
                                        : (isZohoProject ? Icons.cloud : Icons.folder),
                                      size: 18,
                                      color: isMapped 
                                        ? Colors.green.shade700
                                        : (isZohoProject ? Colors.blue.shade700 : Colors.purple.shade700),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: Text(
                                      projectName,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: isMapped ? Colors.green.shade900 : Colors.black87,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isMapped) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.green.shade300, width: 1),
                                      ),
                                      child: Text(
                                        'Mapped',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              technology,
                              style: const TextStyle(fontSize: 14, color: Colors.black87),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DataCell(
                            isZohoProject
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.blue.shade200, width: 1),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.cloud, size: 14, color: Colors.blue.shade700),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Zoho',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.blue.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.purple.shade200, width: 1),
                                    ),
                                    child: Text(
                                      'Local',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.purple.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                          ),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.shade200, width: 1),
                              ),
                              child: Text(
                                'Active',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              startDate,
                              style: const TextStyle(fontSize: 14, color: Colors.black87),
                            ),
                          ),
                          DataCell(
                            dueDate != 'N/A'
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        dueDate,
                                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                                      ),
                                      if (project['target_date'] != null)
                                        Text(
                                          _getRemainingDays(project['target_date']),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.green.shade700,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                    ],
                                  )
                                : Text(
                                    '-',
                                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                                  ),
                          ),
                          DataCell(
                            Text(
                              duration,
                              style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500),
                            ),
                          ),
                          DataCell(
                            Text(
                              owner,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                                fontWeight: isZohoProject ? FontWeight.w500 : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DataCell(
                            Text(
                              createdBy,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                                fontWeight: isZohoProject ? FontWeight.w500 : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DataCell(
                            completionPercentage != '-'
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      completionPercentage,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                : Text(
                                    '-',
                                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                                  ),
                          ),
                          DataCell(
                            Text(
                              workHours,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          DataCell(
                            priority != 'None'
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getPriorityColor(priority).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: _getPriorityColor(priority), width: 1),
                                    ),
                                    child: Text(
                                      priority,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _getPriorityColor(priority),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                : Text(
                                    'None',
                                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                                  ),
                          ),
                          DataCell(
                            Text(
                              associatedTeam,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DataCell(
                            Text(
                              billingType,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              timelogTotal,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          DataCell(
                            domains.isEmpty
                                ? Text(
                                    '-',
                                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                                  )
                                : Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      ...domains.take(2).map((domain) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.purple.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.purple.shade200, width: 1),
                                          ),
                                          child: Text(
                                            domain['code'] ?? domain['name'] ?? 'Domain',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.purple.shade700,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        );
                                      }),
                                      if (domains.length > 2)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '+${domains.length - 2}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                          if (authState.user?['role'] == 'admin')
                            DataCell(
                              isZohoProject
                                  ? SizedBox(
                                      width: 160,
                                      child: _SyncZohoMembersButton(
                                        project: project,
                                        apiService: _apiService,
                                        authProvider: authState,
                                        onSyncComplete: () {},
                                      ),
                                    )
                                  : Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: IconButton(
                                        icon: Icon(Icons.delete_outline, color: Colors.red.shade700, size: 22),
                                        onPressed: () => _confirmDeleteProject(project),
                                        tooltip: 'Delete project',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                    ),
                            ),
                        ],
                      );
                    }).toList(),
                    ),
                  ),
                ),
              ),
          ],
        ),
        ),
      );
    }


  void _handleCreateDomainPlan(dynamic project) {
    final domains = (project['domains'] as List<dynamic>? ?? []);
    
    if (domains.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This project has no domains assigned'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (domains.length == 1) {
      // Directly open domain plan page with the single domain
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => DomainPlanScreen(
            projectId: project['id'],
            projectName: project['name'] ?? 'Project',
            domain: domains[0],
          ),
        ),
      );
    } else {
      // Show domain selection dialog
      _showDomainSelectionDialog(project, domains);
    }
  }

  void _showDomainSelectionDialog(dynamic project, List<dynamic> domains) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.select_all, color: Colors.purple.shade600),
            const SizedBox(width: 12),
            const Text('Select Domain'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select a domain to create a plan for:',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              ...domains.map((domain) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.purple.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          (domain['code'] ?? domain['name'] ?? 'D')[0],
                          style: TextStyle(
                            color: Colors.purple.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      domain['name'] ?? 'Domain',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      domain['code'] ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => DomainPlanScreen(
                            projectId: project['id'],
                            projectName: project['name'] ?? 'Project',
                            domain: domain,
                          ),
                        ),
                      );
                    },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              }).toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showProjectDetails(dynamic project) {
    final isZohoProject = project['source'] == 'zoho';
    
    // For all Zoho projects (mapped or unmapped), show dialog with Sync button
    if (isZohoProject) {
      _showMappedProjectOptions(project);
    } else {
      // Local project: if mapped show same dialog (no Sync); if unmapped show details dialog
      final isMapped = project['is_mapped'] == true;
      if (isMapped) {
        _showMappedProjectOptions(project);
      } else {
        showDialog(
          context: context,
          builder: (context) {
            return _ZohoProjectDetailsDialog(
              project: project,
              isZohoProject: false,
              apiService: _apiService,
              authProvider: ref.read(authProvider),
            );
          },
        );
      }
    }
  }

  Future<void> _openViewScreenInNewWindow(dynamic project) async {
    try {
      final projectName = project['name'] ?? '';
      if (projectName.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Project name not available'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Get domain from project data if available, otherwise fetch from API
      String? domainName = project['domain_name']?.toString();
      
      // If no domain in project data, try to get first domain from API
      if (domainName == null || domainName.isEmpty) {
        try {
          final token = ref.read(authProvider).token;
          if (token != null) {
            final filesResponse = await _apiService.getEdaFiles(
              token: token,
              projectName: projectName,
              limit: 100,
            );
            final files = filesResponse['files'] ?? [];
            if (files.isNotEmpty) {
              final firstFile = files[0];
              domainName = firstFile['domain_name']?.toString();
            }
          }
        } catch (e) {
          // Ignore domain loading errors
        }
      }

      // Default view type by role: admin -> manager, customer -> customer, else engineer
      final userRole = ref.read(authProvider).user?['role']?.toString();
      final viewType = userRole == 'admin'
          ? 'manager'
          : (userRole == 'customer' ? 'customer' : 'engineer');

      // Store data in localStorage for the new window
      final viewData = {
        'project': projectName,
        if (domainName != null && domainName.isNotEmpty) 'domain': domainName,
        'viewType': viewType,
      };
      html.window.localStorage['standalone_view'] = jsonEncode(viewData);
      
      // Get current URL and construct new window URL
      final currentUrl = html.window.location.href;
      final baseUrl = currentUrl.split('?')[0].split('#')[0];
      final projectNameEncoded = Uri.encodeComponent(projectName);
      final domainNameEncoded = domainName != null && domainName.isNotEmpty 
          ? Uri.encodeComponent(domainName) 
          : '';
      
      // Open new window with view route
      String newWindowUrl = '$baseUrl#/view?project=$projectNameEncoded';
      if (domainNameEncoded.isNotEmpty) {
        newWindowUrl += '&domain=$domainNameEncoded';
      }
      newWindowUrl += '&viewType=${Uri.encodeComponent(viewType)}';
      
      html.window.open(
        newWindowUrl,
        'view_${projectName.replaceAll(' ', '_')}',
        'width=1600,height=1000,scrollbars=yes,resizable=yes',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open view window: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  void _showMappedProjectOptions(dynamic project) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade700,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Mapped Project',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project['name'] ?? 'Project',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Sync Members Button (only for Zoho projects)
                    if (project['source'] == 'zoho')
                      Builder(
                        builder: (context) {
                          try {
                            return SizedBox(
                              width: double.infinity,
                              child: _SyncZohoMembersButton(
                                project: project,
                                apiService: _apiService,
                                authProvider: ref.read(authProvider),
                                onSyncComplete: () {},
                              ),
                            );
                          } catch (e) {
                            print('[MappedDialog] Error rendering sync button: $e');
                            return const SizedBox.shrink();
                          }
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProjectPlan(dynamic project) async {
    // Show loading dialog first
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final authState = ref.read(authProvider);
      final token = authState.token;

      if (token == null) {
        if (mounted) {
          Navigator.of(context).pop(); // Close loading
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Not authenticated'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Get project ID - handle both zoho_ prefix and direct ID
      final projectId = project['zoho_project_id']?.toString() ?? 
                       project['id']?.toString() ?? '';
      
      // Remove zoho_ prefix if present
      final actualProjectId = projectId.startsWith('zoho_') 
          ? projectId.replaceFirst('zoho_', '') 
          : projectId;
      
      if (actualProjectId.isEmpty) {
        if (mounted) {
          Navigator.of(context).pop(); // Close loading
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Project ID not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      // Get portal ID from zoho_data if available
      final zohoData = project['zoho_data'] as Map<String, dynamic>?;
      final portalId = zohoData?['portal_id']?.toString() ?? 
                      zohoData?['portal']?.toString();
      
      // Load both tasks and milestones in parallel
      final tasksFuture = _apiService.getZohoTasks(
        projectId: actualProjectId,
        token: token,
        portalId: portalId,
      );
      
      // Load milestones with error handling - don't fail if milestones fail
      List<dynamic> milestones = [];
      try {
        final milestonesResponse = await _apiService.getZohoMilestones(
          projectId: actualProjectId,
          token: token,
          portalId: portalId,
        );
        milestones = milestonesResponse['milestones'] ?? [];
        print('🎯 Loaded ${milestones.length} milestones for Project Plan');
        print('🎯 Milestones response structure: ${milestonesResponse.keys.toList()}');
        if (milestones.isEmpty) {
          print('⚠️ Milestones array is empty - project may not have milestones in Zoho');
          print('⚠️ Full response: $milestonesResponse');
        } else {
          print('✅ First milestone sample: ${milestones[0]}');
        }
      } catch (milestoneError) {
        print('⚠️ Failed to load milestones (non-critical): $milestoneError');
        print('⚠️ Error details: ${milestoneError.toString()}');
        // Continue without milestones - don't block the UI
      }
      
      // Wait for tasks
      final tasksResponse = await tasksFuture;
      final tasks = tasksResponse['tasks'] ?? [];
      
      // If milestones API returned empty, try to extract milestones from tasks
      if (milestones.isEmpty && tasks.isNotEmpty) {
        print('🔄 Extracting milestones from tasks...');
        milestones = _extractMilestonesFromTasks(tasks);
        print('✅ Extracted ${milestones.length} unique milestones from tasks');
      }

      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        
        // Show tasks and milestones dialog
        _showTasksDialog(project, tasks, milestones: milestones);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading project plan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Extract unique milestones from tasks
  List<dynamic> _extractMilestonesFromTasks(List<dynamic> tasks) {
    final milestoneMap = <String, Map<String, dynamic>>{};
    
    for (final task in tasks) {
      final milestoneId = task['milestone_id']?.toString();
      final milestoneName = task['milestone_name']?.toString();
      
      // Only process if we have both ID and name
      if (milestoneId != null && milestoneName != null && milestoneId.isNotEmpty) {
        // Use milestone_id as key to avoid duplicates
        if (!milestoneMap.containsKey(milestoneId)) {
          milestoneMap[milestoneId] = {
            'id': milestoneId,
            'name': milestoneName,
            'start_date': task['milestone_start_date'],
            'end_date': task['milestone_end_date'],
            'status': task['milestone_status'] ?? 'Unknown',
            // Mark as extracted from tasks
            '_extracted_from_tasks': true,
          };
        }
      }
    }
    
    return milestoneMap.values.toList();
  }

  // Map Zoho tasks to project structure
  // Task lists = Domains
  // Tasks = Blocks (for PD) or Modules/Blocks (for DV)
  // Subtasks = Requirements (only for DV, not for PD)
  Map<String, dynamic> _mapTasksToProjectStructure(List<dynamic> tasks) {
    final mappedData = <String, dynamic>{
      'domains': <Map<String, dynamic>>[],
    };
    
    for (final task in tasks) {
      final taskName = (task['name'] ?? task['task_name'] ?? 'Unnamed Task').toString();
      final subtasks = task['subtasks'] as List<dynamic>? ?? [];
      
      // Get domain from tasklist_name (this is where the domain is stored)
      final tasklistName = (task['tasklist_name'] ?? task['tasklistName'] ?? '').toString();
      final tasklistNameLower = tasklistName.toLowerCase();
      
      // Determine domain type from tasklist name
      // Check if it's PD (Physical Design) or DV (Design Verification)
      final isPD = tasklistNameLower.contains('pd') || 
                   tasklistNameLower == 'pd' ||
                   tasklistNameLower.contains('physical') || 
                   tasklistNameLower.contains('physical design');
      final isDV = tasklistNameLower.contains('dv') || 
                   tasklistNameLower == 'dv' ||
                   tasklistNameLower.contains('design verification') ||
                   tasklistNameLower.contains('verification');
      
      // If tasklist_name doesn't help, try task name as fallback
      final taskNameLower = taskName.toLowerCase();
      final isPDFromTask = !isPD && !isDV && (taskNameLower.contains('pd') || 
                   taskNameLower.contains('physical') || 
                   taskNameLower.contains('physical design'));
      final isDVFromTask = !isPD && !isDV && (taskNameLower.contains('dv') || 
                   taskNameLower.contains('design verification') ||
                   taskNameLower.contains('verification'));
      
      // Determine domain type
      final domainType = (isPD || isPDFromTask) ? 'PD' : ((isDV || isDVFromTask) ? 'DV' : 'DV');
      final domainCode = (isPD || isPDFromTask) ? 'PHYSICAL' : 'DV';
      final domainName = (isPD || isPDFromTask) ? 'Physical Design' : 'Design Verification';
      
      // Create domain entry
      final domain = <String, dynamic>{
        'name': domainName,
        'code': domainCode,
        'type': domainType,
        'blocks': <Map<String, dynamic>>[],
      };
      
      // Map tasks as blocks/modules
      // For PD: tasks are blocks
      // For DV: tasks are modules/blocks
      
      // Extract owner information - try multiple sources
      String? ownerName = task['owner_name']?.toString();
      String? ownerRole = task['owner_role']?.toString();
      
      // Fallback: try to get from owner object
      if ((ownerName == null || ownerName.isEmpty) && task['owner'] != null) {
        if (task['owner'] is Map) {
          ownerName = task['owner']['name']?.toString() ?? 
                     '${task['owner']['first_name'] ?? ''} ${task['owner']['last_name'] ?? ''}'.trim();
          ownerRole = task['owner']['role']?.toString() ?? ownerRole;
        } else {
          ownerName = task['owner'].toString();
        }
      }
      
      // Fallback: try to get from details.owners array
      if ((ownerName == null || ownerName.isEmpty) && task['details'] != null && task['details'] is Map) {
        final details = task['details'] as Map;
        if (details['owners'] != null && details['owners'] is List && (details['owners'] as List).isNotEmpty) {
          final owner = (details['owners'] as List)[0];
          if (owner is Map) {
            ownerName = owner['name']?.toString() ?? 
                       owner['full_name']?.toString() ??
                       '${owner['first_name'] ?? ''} ${owner['last_name'] ?? ''}'.trim();
            ownerRole = owner['role']?.toString() ?? ownerRole;
          }
        }
      }
      
      // Debug: Check what owner info we found
      print('📋 Mapping task: $taskName');
      print('   Final owner_name: $ownerName');
      print('   Final owner_role: $ownerRole');
      
      final block = <String, dynamic>{
        'name': taskName,
        'type': domainType == 'PD' ? 'block' : 'module',
        'owner_name': ownerName,
        'owner_role': ownerRole,
        'requirements': <Map<String, dynamic>>[],
      };
      
      // Map subtasks as requirements (only for DV)
      if (domainType == 'DV' && subtasks.isNotEmpty) {
        for (final subtask in subtasks) {
          final subtaskName = (subtask['name'] ?? subtask['task_name'] ?? 'Unnamed Subtask').toString();
          
          // Extract owner information for subtask - try multiple sources
          String? subtaskOwnerName = subtask['owner_name']?.toString();
          String? subtaskOwnerRole = subtask['owner_role']?.toString();
          
          // Fallback: try to get from owner object
          if ((subtaskOwnerName == null || subtaskOwnerName.isEmpty) && subtask['owner'] != null) {
            if (subtask['owner'] is Map) {
              subtaskOwnerName = subtask['owner']['name']?.toString() ?? 
                               '${subtask['owner']['first_name'] ?? ''} ${subtask['owner']['last_name'] ?? ''}'.trim();
              subtaskOwnerRole = subtask['owner']['role']?.toString() ?? subtaskOwnerRole;
            } else {
              subtaskOwnerName = subtask['owner'].toString();
            }
          }
          
          // Fallback: try to get from details.owners array
          if ((subtaskOwnerName == null || subtaskOwnerName.isEmpty) && subtask['details'] != null && subtask['details'] is Map) {
            final details = subtask['details'] as Map;
            if (details['owners'] != null && details['owners'] is List && (details['owners'] as List).isNotEmpty) {
              final owner = (details['owners'] as List)[0];
              if (owner is Map) {
                subtaskOwnerName = owner['name']?.toString() ?? 
                                 owner['full_name']?.toString() ??
                                 '${owner['first_name'] ?? ''} ${owner['last_name'] ?? ''}'.trim();
                subtaskOwnerRole = owner['role']?.toString() ?? subtaskOwnerRole;
              }
            }
          }
          
          block['requirements'].add({
            'name': subtaskName,
            'owner_name': subtaskOwnerName,
            'owner_role': subtaskOwnerRole,
            'original_data': subtask,
          });
        }
      }
      
      domain['blocks'].add(block);
      
      // Check if domain already exists, if so merge blocks
      final existingDomainIndex = mappedData['domains'].indexWhere(
        (d) => d['code'] == domainCode
      );
      
      if (existingDomainIndex >= 0) {
        mappedData['domains'][existingDomainIndex]['blocks'].addAll(domain['blocks']);
      } else {
        mappedData['domains'].add(domain);
      }
    }
    
    return mappedData;
  }

  void _showTasksDialog(dynamic project, List<dynamic> tasks, {List<dynamic>? milestones}) {
    final projectName = project['name'] ?? 'Project';
    
    // Map tasks to project structure
    final mappedData = _mapTasksToProjectStructure(tasks);
    final domains = mappedData['domains'] as List<dynamic>;
    
    // Store original tasks and project for export
    final originalTasks = List<dynamic>.from(tasks);
    final projectData = project;
    final milestonesList = milestones ?? [];
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 900),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D2D),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade700,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.list_alt,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Project Plan',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Export Button
                      ElevatedButton.icon(
                        onPressed: () {
                          _exportMappedData(projectName, mappedData, originalTasks: originalTasks, project: projectData, milestones: milestonesList);
                        },
                        icon: const Icon(Icons.download, size: 16),
                        label: const Text('Export YAML'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                // Title
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    projectName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Milestones Section - Always show, even if empty (for debugging)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: milestonesList.isNotEmpty ? Colors.purple.shade700 : Colors.grey.shade700,
                      width: 2,
                    ),
                  ),
                  child: milestonesList.isEmpty
                      ? Row(
                          children: [
                            Icon(
                              Icons.flag,
                              color: Colors.grey.shade400,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'No milestones found',
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.flag,
                                  color: Colors.purple.shade300,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Milestones (${milestonesList.length})',
                                  style: TextStyle(
                                    color: Colors.purple.shade300,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                        ...milestonesList.take(5).map((milestone) {
                          final name = milestone['name']?.toString() ?? 
                                       milestone['milestone_name']?.toString() ?? 
                                       'Unnamed Milestone';
                          final startDate = milestone['start_date'] ?? 
                                           milestone['start_date_format'];
                          final endDate = milestone['end_date'] ?? 
                                         milestone['end_date_format'];
                          final status = milestone['status']?.toString() ?? 'Unknown';
                          
                          Color statusColor = Colors.grey;
                          if (status.toLowerCase().contains('completed') || 
                              status.toLowerCase().contains('done')) {
                            statusColor = Colors.green;
                          } else if (status.toLowerCase().contains('in progress') ||
                                     status.toLowerCase().contains('active')) {
                            statusColor = Colors.blue;
                          } else if (status.toLowerCase().contains('pending') ||
                                     status.toLowerCase().contains('not started')) {
                            statusColor = Colors.orange;
                          }
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.shade700, width: 1),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.flag,
                                  size: 16,
                                  color: statusColor,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: statusColor.withOpacity(0.5)),
                                  ),
                                  child: Text(
                                    status.toUpperCase(),
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Icon(
                                  Icons.calendar_today,
                                  size: 12,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${startDate != null ? _formatSimpleDate(startDate) ?? 'TBD' : 'TBD'} - ${endDate != null ? _formatSimpleDate(endDate) ?? 'TBD' : 'TBD'}',
                                  style: TextStyle(
                                    color: Colors.grey.shade300,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        if (milestonesList.length > 5)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '... and ${milestonesList.length - 5} more milestone${milestonesList.length - 5 != 1 ? 's' : ''}',
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                          ),
                        ),
                      ],
                  ),
                ),
                // Mapped Structure: Domains -> Blocks -> Requirements
                Expanded(
                  child: domains.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: Text(
                              'No domains found',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: domains.length,
                          itemBuilder: (context, domainIndex) {
                            final domain = domains[domainIndex];
                            final domainName = domain['name'] ?? 'Domain';
                            final domainCode = domain['code'] ?? '';
                            final domainType = domain['type'] ?? 'DV';
                            final blocks = domain['blocks'] as List<dynamic>? ?? [];
                            final isDomainExpanded = domain['_isExpanded'] == true;
                            
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2D2D2D),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: domainType == 'PD' ? Colors.orange.shade700 : Colors.blue.shade700,
                                  width: 2,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Domain Header
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        domain['_isExpanded'] = !isDomainExpanded;
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          Icon(
                                            isDomainExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                                            color: domainType == 'PD' ? Colors.orange.shade300 : Colors.blue.shade300,
                                            size: 24,
                                          ),
                                          const SizedBox(width: 12),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: domainType == 'PD' ? Colors.orange.shade700 : Colors.blue.shade700,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              domainCode,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              domainName,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade700,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '${blocks.length} ${domainType == 'PD' ? 'block' : 'module'}${blocks.length != 1 ? 's' : ''}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: const Icon(Icons.download, size: 18),
                                            color: Colors.green.shade400,
                                            tooltip: 'Export Domain YAML',
                                            onPressed: () {
                                              _exportDomainJson(
                                                projectName,
                                                domain,
                                                originalTasks: originalTasks,
                                                project: projectData,
                                                milestones: milestonesList,
                                              );
                                            },
                                            padding: const EdgeInsets.all(8),
                                            constraints: const BoxConstraints(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Blocks/Modules
                                  if (isDomainExpanded && blocks.isNotEmpty)
                                    Container(
                                      margin: const EdgeInsets.only(left: 32, right: 16, bottom: 16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: blocks.asMap().entries.map((blockEntry) {
                                          final block = blockEntry.value;
                                          final blockName = block['name'] ?? 'Unnamed Block';
                                          final requirements = block['requirements'] as List<dynamic>? ?? [];
                                          final isBlockExpanded = block['_isExpanded'] == true;
                                          
                                          return Container(
                                            margin: const EdgeInsets.only(bottom: 12),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF1E1E1E),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: domainType == 'PD' ? Colors.orange.shade500 : Colors.blue.shade500,
                                                width: 1,
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                // Block Header
                                                InkWell(
                                                  onTap: () {
                                                    setState(() {
                                                      block['_isExpanded'] = !isBlockExpanded;
                                                    });
                                                  },
                                                  child: Padding(
                                                    padding: const EdgeInsets.all(14),
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          isBlockExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                                            color: Colors.grey,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                                        Icon(
                                                          domainType == 'PD' ? Icons.view_module : Icons.widgets,
                                                          color: domainType == 'PD' ? Colors.orange.shade400 : Colors.blue.shade400,
                                                          size: 18,
                                                        ),
                                                        const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                                            blockName,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                                        if (domainType == 'DV' && requirements.isNotEmpty)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade700,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                              '${requirements.length} requirement${requirements.length != 1 ? 's' : ''}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                                fontSize: 11,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                                // Requirements (only for DV)
                                                if (isBlockExpanded && domainType == 'DV' && requirements.isNotEmpty)
                                    Container(
                                      margin: const EdgeInsets.only(left: 48, right: 16, bottom: 16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: requirements.asMap().entries.map((reqEntry) {
                                                        final reqIndex = reqEntry.key;
                                                        final requirement = reqEntry.value;
                                                        final reqName = requirement['name'] ?? 'Unnamed Requirement';
                                          
                                          return Container(
                                            margin: const EdgeInsets.only(bottom: 8),
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                                            color: const Color(0xFF2D2D2D),
                                              borderRadius: BorderRadius.circular(6),
                                                            border: Border.all(color: Colors.blue.shade700, width: 1),
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                                width: 24,
                                                                height: 24,
                                                  decoration: BoxDecoration(
                                                    color: Colors.blue.shade700,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                                    '${reqIndex + 1}',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                                  reqName,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 14,
                                                    ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      }).toList(),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                // Footer
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D2D),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // View Button
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop(); // Close Project Plan dialog
                          // Open View screen in new window
                          _openViewScreenInNewWindow(project);
                        },
                        icon: const Icon(Icons.visibility, size: 18),
                        label: const Text('View'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                      // Close Button
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Close',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _exportMappedData(String projectName, Map<String, dynamic> mappedData, {List<dynamic>? originalTasks, dynamic project, List<dynamic>? milestones}) {
    // Create simplified export data structure with only essential fields
    final domains = mappedData['domains'] as List<dynamic>;
    
    // Get project dates
    final startDate = project?['start_date']?.toString() ?? '';
    final updatedDate = project?['updated_at']?.toString() ?? '';
    
    // Get project roles/members to map owner names to their project roles
    final projectRoles = <String, String>{}; // Map owner_name -> role
    final projectMembers = project?['members'] as List<dynamic>?;
    final projectRolesList = project?['roles'] as List<dynamic>?;
    
    // Build role mapping from project members/roles
    if (projectMembers != null && projectMembers.isNotEmpty) {
      for (final member in projectMembers) {
        final memberName = member['name']?.toString();
        final memberRole = member['role']?.toString() ?? member['role_mapped']?.toString();
        if (memberName != null && memberRole != null) {
          projectRoles[memberName] = memberRole;
        }
      }
    }
    
    if (projectRolesList != null && projectRolesList.isNotEmpty) {
      for (final role in projectRolesList) {
        final roleName = role['name']?.toString();
        final roleValue = role['role']?.toString() ?? role['role_mapped']?.toString();
        if (roleName != null && roleValue != null) {
          projectRoles[roleName] = roleValue;
        }
      }
    }
    
    // Build simplified export structure
    final exportDomains = <Map<String, dynamic>>[];
    
    for (final domain in domains) {
      final domainName = domain['name'] ?? '';
      final blocks = domain['blocks'] as List<dynamic>? ?? [];
      
      // Build simplified blocks with only name and requirements
      final simplifiedBlocks = <Map<String, dynamic>>[];
      
      for (final block in blocks) {
        final blockName = block['name'] ?? '';
        final requirements = block['requirements'] as List<dynamic>? ?? [];
        
        // Debug: Check what's in the block
        print('🔍 Exporting block: $blockName');
        print('   Block keys: ${block.keys.toList()}');
        print('   Block owner_name: ${block['owner_name']}');
        print('   Block owner_role: ${block['owner_role']}');
        
        // Get owner info from block first (it's already stored there from mapping)
        String? blockOwnerName = block['owner_name']?.toString();
        String? blockOwnerRole = block['owner_role']?.toString();
        
        print('   Extracted owner_name: $blockOwnerName');
        print('   Extracted owner_role: $blockOwnerRole');
        
        // Get dates - try from block first, then from originalTasks
        String? blockStartDate;
        String? blockUpdatedDate;
        
        // Try to get dates from originalTasks if available
        if (originalTasks != null) {
          for (final task in originalTasks) {
            final taskName = (task['name'] ?? task['task_name'] ?? '').toString();
            if (taskName == blockName) {
              blockStartDate = task['start_date']?.toString() ?? task['created_time']?.toString() ?? '';
              blockUpdatedDate = task['updated_at']?.toString() ?? task['modified_time']?.toString() ?? '';
              
              // If owner info not in block, try to get from task
              if (blockOwnerName == null || blockOwnerName.isEmpty) {
                blockOwnerName = task['owner_name']?.toString();
              }
              if (blockOwnerRole == null || blockOwnerRole.isEmpty) {
                blockOwnerRole = task['owner_role']?.toString();
              }
              break;
            }
          }
        }
        
        // If still no role, try to get from project roles mapping
        if ((blockOwnerRole == null || blockOwnerRole.isEmpty) && blockOwnerName != null && blockOwnerName.isNotEmpty) {
          blockOwnerRole = projectRoles[blockOwnerName];
        }
        
        final simplifiedBlock = <String, dynamic>{
          'block': blockName,
          if (blockStartDate != null && blockStartDate.isNotEmpty) 'start_date': blockStartDate,
          if (blockUpdatedDate != null && blockUpdatedDate.isNotEmpty) 'updated_date': blockUpdatedDate,
          if (blockOwnerName != null && blockOwnerName.isNotEmpty) 'owner': {
            'name': blockOwnerName,
            if (blockOwnerRole != null && blockOwnerRole.isNotEmpty) 'role': blockOwnerRole,
          },
        };
        
        // Add requirements/modules only for DV domains
        if (requirements.isNotEmpty) {
          simplifiedBlock['requirements'] = requirements.map((req) {
            final reqName = req['name'] ?? '';
            // Get owner info from requirement first (it's already stored there)
            String? reqOwnerName = req['owner_name']?.toString();
            String? reqOwnerRole = req['owner_role']?.toString();
            
            // If no role, try to get from project roles mapping
            if ((reqOwnerRole == null || reqOwnerRole.isEmpty) && reqOwnerName != null && reqOwnerName.isNotEmpty) {
              reqOwnerRole = projectRoles[reqOwnerName];
            }
            
            // Return as object with name and owner info if available
            if (reqOwnerName != null && reqOwnerName.isNotEmpty) {
              return {
                'name': reqName,
                'owner': {
                  'name': reqOwnerName,
                  if (reqOwnerRole != null && reqOwnerRole.isNotEmpty) 'role': reqOwnerRole,
                },
              };
            } else {
              return reqName; // Backward compatibility: return just name if no owner
            }
          }).toList();
        }
        
        simplifiedBlocks.add(simplifiedBlock);
      }
      
      // Build domain export structure
      final domainExport = <String, dynamic>{
        'domain_name': domainName,
        'blocks': simplifiedBlocks,
      };
      
      exportDomains.add(domainExport);
    }
    
    // Build milestones export structure
    final exportMilestones = <Map<String, dynamic>>[];
    if (milestones != null && milestones.isNotEmpty) {
      for (final milestone in milestones) {
        final milestoneExport = <String, dynamic>{
          'name': milestone['name']?.toString() ?? milestone['milestone_name']?.toString() ?? 'Unnamed Milestone',
        };
        
        // Add start_date if available
        final startDateValue = milestone['start_date'] ?? milestone['start_date_format'];
        if (startDateValue != null) {
          milestoneExport['start_date'] = startDateValue.toString();
        }
        
        // Add end_date if available
        final endDateValue = milestone['end_date'] ?? milestone['end_date_format'];
        if (endDateValue != null) {
          milestoneExport['end_date'] = endDateValue.toString();
        }
        
        exportMilestones.add(milestoneExport);
      }
    }
    
    // Create simplified export data structure
    final exportData = {
      'project_name': projectName,
      if (startDate.isNotEmpty) 'start_date': startDate,
      if (updatedDate.isNotEmpty) 'updated_date': updatedDate,
      if (exportMilestones.isNotEmpty) 'milestones': exportMilestones,
      'domains': exportDomains,
    };
    
    // Convert to YAML string
    final yamlString = _mapToYaml(exportData);
    
    // Show dialog with YAML data
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade700,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.download,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Exported Mapped Data',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              // YAML Content
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D0D),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade800, width: 1),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      yamlString,
                      style: const TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
              // Footer with Download and Copy buttons
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        // Download YAML file
                        final blob = html.Blob([yamlString], 'text/yaml');
                        final url = html.Url.createObjectUrlFromBlob(blob);
                        html.AnchorElement(href: url)
                          ..setAttribute('download', '${projectName.replaceAll(' ', '_')}_project_plan.yaml')
                          ..click();
                        html.Url.revokeObjectUrl(url);
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('YAML file downloaded: ${projectName.replaceAll(' ', '_')}_project_plan.yaml'),
                            backgroundColor: Colors.green,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Download YAML'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        // Copy to clipboard
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('YAML data is selectable. Copy manually or use browser copy (Ctrl+C)'),
                            backgroundColor: Colors.blue,
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Close',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _exportDomainJson(String projectName, Map<String, dynamic> domain, {List<dynamic>? originalTasks, dynamic project, List<dynamic>? milestones}) {
    final domainName = domain['name'] ?? '';
    final domainCode = domain['code'] ?? '';
    final blocks = domain['blocks'] as List<dynamic>? ?? [];
    
    // Get project dates
    final startDate = project?['start_date']?.toString() ?? '';
    final updatedDate = project?['updated_at']?.toString() ?? '';
    
    // Get project roles/members to map owner names to their project roles
    final projectRoles = <String, String>{}; // Map owner_name -> role
    final projectMembers = project?['members'] as List<dynamic>?;
    final projectRolesList = project?['roles'] as List<dynamic>?;
    
    // Build role mapping from project members/roles
    if (projectMembers != null && projectMembers.isNotEmpty) {
      for (final member in projectMembers) {
        final memberName = member['name']?.toString();
        final memberRole = member['role']?.toString() ?? member['role_mapped']?.toString();
        if (memberName != null && memberRole != null) {
          projectRoles[memberName] = memberRole;
        }
      }
    }
    
    if (projectRolesList != null && projectRolesList.isNotEmpty) {
      for (final role in projectRolesList) {
        final roleName = role['name']?.toString();
        final roleValue = role['role']?.toString() ?? role['role_mapped']?.toString();
        if (roleName != null && roleValue != null) {
          projectRoles[roleName] = roleValue;
        }
      }
    }
    
    // Build simplified blocks
    final simplifiedBlocks = <Map<String, dynamic>>[];
    
    for (final block in blocks) {
      final blockName = block['name'] ?? '';
      final requirements = block['requirements'] as List<dynamic>? ?? [];
      
      // Get owner info from block first (it's already stored there from mapping)
      String? blockOwnerName = block['owner_name']?.toString();
      String? blockOwnerRole = block['owner_role']?.toString();
      
      // Get dates - try from block first, then from originalTasks
      String? blockStartDate;
      String? blockUpdatedDate;
      
      // Try to get dates from originalTasks if available
      if (originalTasks != null) {
        for (final task in originalTasks) {
          final taskName = (task['name'] ?? task['task_name'] ?? '').toString();
          if (taskName == blockName) {
            blockStartDate = task['start_date']?.toString() ?? task['created_time']?.toString() ?? '';
            blockUpdatedDate = task['updated_at']?.toString() ?? task['modified_time']?.toString() ?? '';
            
            // If owner info not in block, try to get from task
            if (blockOwnerName == null || blockOwnerName.isEmpty) {
              blockOwnerName = task['owner_name']?.toString();
            }
            if (blockOwnerRole == null || blockOwnerRole.isEmpty) {
              blockOwnerRole = task['owner_role']?.toString();
            }
            break;
          }
        }
      }
      
      // If still no role, try to get from project roles mapping
      if ((blockOwnerRole == null || blockOwnerRole.isEmpty) && blockOwnerName != null && blockOwnerName.isNotEmpty) {
        blockOwnerRole = projectRoles[blockOwnerName];
      }
      
      final simplifiedBlock = <String, dynamic>{
        'block': blockName,
        if (blockStartDate != null && blockStartDate.isNotEmpty) 'start_date': blockStartDate,
        if (blockUpdatedDate != null && blockUpdatedDate.isNotEmpty) 'updated_date': blockUpdatedDate,
        if (blockOwnerName != null && blockOwnerName.isNotEmpty) 'owner': {
          'name': blockOwnerName,
          if (blockOwnerRole != null && blockOwnerRole.isNotEmpty) 'role': blockOwnerRole,
        },
      };
      
      // Add requirements/modules only for DV domains
      if (requirements.isNotEmpty) {
        simplifiedBlock['requirements'] = requirements.map((req) {
          final reqName = req['name'] ?? '';
          // Get owner info from requirement first (it's already stored there)
          String? reqOwnerName = req['owner_name']?.toString();
          String? reqOwnerRole = req['owner_role']?.toString();
          
          // If no role, try to get from project roles mapping
          if ((reqOwnerRole == null || reqOwnerRole.isEmpty) && reqOwnerName != null && reqOwnerName.isNotEmpty) {
            reqOwnerRole = projectRoles[reqOwnerName];
          }
          
          // Return as object with name and owner info if available
          if (reqOwnerName != null && reqOwnerName.isNotEmpty) {
            return {
              'name': reqName,
              'owner': {
                'name': reqOwnerName,
                if (reqOwnerRole != null && reqOwnerRole.isNotEmpty) 'role': reqOwnerRole,
              },
            };
          } else {
            return reqName; // Backward compatibility: return just name if no owner
          }
        }).toList();
      }
      
      simplifiedBlocks.add(simplifiedBlock);
    }
    
    // Build milestones export structure
    final exportMilestones = <Map<String, dynamic>>[];
    if (milestones != null && milestones.isNotEmpty) {
      for (final milestone in milestones) {
        final milestoneExport = <String, dynamic>{
          'name': milestone['name']?.toString() ?? milestone['milestone_name']?.toString() ?? 'Unnamed Milestone',
        };
        
        // Add start_date if available
        final startDateValue = milestone['start_date'] ?? milestone['start_date_format'];
        if (startDateValue != null) {
          milestoneExport['start_date'] = startDateValue.toString();
        }
        
        // Add end_date if available
        final endDateValue = milestone['end_date'] ?? milestone['end_date_format'];
        if (endDateValue != null) {
          milestoneExport['end_date'] = endDateValue.toString();
        }
        
        exportMilestones.add(milestoneExport);
      }
    }
    
    // Create domain-specific export data structure
    final exportData = {
      'project_name': projectName,
      'domain_name': domainName,
      'domain_code': domainCode,
      if (startDate.isNotEmpty) 'start_date': startDate,
      if (updatedDate.isNotEmpty) 'updated_date': updatedDate,
      if (exportMilestones.isNotEmpty) 'milestones': exportMilestones,
      'blocks': simplifiedBlocks,
    };
    
    // Convert to YAML string
    final yamlString = _mapToYaml(exportData);
    
    // Download YAML file directly
    final safeDomainName = domainName.replaceAll(' ', '_').replaceAll(RegExp(r'[^\w\s-]'), '');
    final safeProjectName = projectName.replaceAll(' ', '_').replaceAll(RegExp(r'[^\w\s-]'), '');
    final fileName = '${safeProjectName}_${safeDomainName}_domain.yaml';
    
    final blob = html.Blob([yamlString], 'text/yaml');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
    html.Url.revokeObjectUrl(url);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Domain YAML file downloaded: $fileName'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Helper methods for the main class
  String _formatDateForTable(dynamic dateValue) {
    if (dateValue == null) return 'N/A';
    try {
      String dateStr = dateValue.toString();
      if (dateStr.contains('T') || dateStr.contains('Z')) {
        final date = DateTime.parse(dateStr);
        return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }
      return dateStr;
    } catch (e) {
      return dateValue.toString();
    }
  }

  String? _formatSimpleDate(dynamic dateValue) {
    if (dateValue == null) return null;
    
    try {
      // If it's already a formatted string, return it
      if (dateValue is String) {
        // Check if it's an ISO date string
        if (dateValue.contains('T') || dateValue.contains('Z')) {
          final date = DateTime.parse(dateValue);
          return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
        }
        // If it's already formatted, return as is
        return dateValue;
      }
      
      // If it's a timestamp (long)
      if (dateValue is int || dateValue is num) {
        final date = DateTime.fromMillisecondsSinceEpoch(dateValue.toInt());
        return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
      }
      
      return dateValue.toString();
    } catch (e) {
      return dateValue.toString();
    }
  }

  String _calculateDuration(dynamic startDate, dynamic endDate) {
    if (startDate == null || endDate == null) return '-';
    try {
      final start = DateTime.parse(startDate.toString());
      final end = DateTime.parse(endDate.toString());
      final difference = end.difference(start);
      final days = difference.inDays;
      if (days > 0) {
        return '$days day${days != 1 ? 's' : ''}';
      } else {
        final hours = difference.inHours;
        return '$hours hour${hours != 1 ? 's' : ''}';
      }
    } catch (e) {
      return '-';
    }
  }

  Color _getPriorityColor(String priority) {
    final priorityLower = priority.toLowerCase();
    if (priorityLower.contains('high') || priorityLower.contains('urgent')) {
      return Colors.red;
    } else if (priorityLower.contains('medium') || priorityLower.contains('normal')) {
      return Colors.orange;
    } else if (priorityLower.contains('low')) {
      return Colors.green;
    }
    return Colors.grey;
  }

  String _getRemainingDays(dynamic targetDate) {
    if (targetDate == null) return '';
    try {
      final target = DateTime.parse(targetDate.toString());
      final now = DateTime.now();
      final difference = target.difference(now);
      final days = difference.inDays;
      final hours = difference.inHours % 24;
      
      if (days > 0) {
        return '($days day(s) and $hours hour(s))';
      } else if (hours > 0) {
        return '($hours hour(s))';
      } else {
        return '(Overdue)';
      }
    } catch (e) {
      return '';
    }
  }

  Future<void> _confirmDeleteProject(dynamic project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text('Delete Project'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to delete this project?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Project: ${project['name'] ?? 'Unknown'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (project['id'] != null)
                    Text(
                      'ID: ${project['id']}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This action cannot be undone!',
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final authState = ref.read(authProvider);
        final token = authState.token;
        final projectId = project['id'];
        
        if (projectId == null) {
          throw Exception('Invalid project ID');
        }

        // Extract numeric ID if it's a string like "zoho_123"
        int? numericId;
        if (projectId is String && projectId.startsWith('zoho_')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cannot delete Zoho projects from this interface'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        } else {
          numericId = projectId is int ? projectId : int.tryParse(projectId.toString());
        }

        if (numericId == null) {
          throw Exception('Invalid project ID format');
        }

        await _apiService.deleteProject(numericId, token: token);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Project deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
          // Reload projects
          _loadDomainsAndProjects();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting project: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}

// Separate StatefulWidget for Zoho project details
class _ZohoProjectDetailsDialog extends StatefulWidget {
  final dynamic project;
  final bool isZohoProject;
  final ApiService apiService;
  final dynamic authProvider;

  const _ZohoProjectDetailsDialog({
    required this.project,
    required this.isZohoProject,
    required this.apiService,
    required this.authProvider,
  });

  @override
  State<_ZohoProjectDetailsDialog> createState() => _ZohoProjectDetailsDialogState();
}

class _ZohoProjectDetailsDialogState extends State<_ZohoProjectDetailsDialog> {
  List<dynamic> _tasks = [];
  bool _isLoadingTasks = false;
  String? _tasksError;
  bool _hasLoadedTasks = false;
  
  // Milestones state
  List<dynamic> _milestones = [];
  bool _isLoadingMilestones = false;
  String? _milestonesError;
  bool _hasLoadedMilestones = false;
  
  // Tab selection
  int _selectedTab = 0;

  // Check if this Zoho project has been linked to an ASI project
  bool _hasAsiProjectId() {
    // Check if project has an ASI project ID (not just zoho_project_id)
    // ASI project ID should be a numeric ID, not starting with 'zoho_'
    final projectId = widget.project['id'];
    if (projectId == null) return false;
    
    // If it's a string starting with 'zoho_', it's not linked yet
    if (projectId is String && projectId.startsWith('zoho_')) {
      return false;
    }
    
    // If it's a number or numeric string, it's an ASI project ID
    if (projectId is int) return true;
    if (projectId is String && int.tryParse(projectId) != null) return true;
    
    return false;
  }

  @override
  void initState() {
    super.initState();
    if (widget.isZohoProject) {
      // Load milestones and tasks after the first frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadMilestones();
        _loadTasks();
      });
    }
  }

  Future<void> _loadMilestones() async {
    if (!widget.isZohoProject || _hasLoadedMilestones || _isLoadingMilestones) return;
    
    setState(() {
      _isLoadingMilestones = true;
      _milestonesError = null;
      _hasLoadedMilestones = true;
    });
    
    try {
      final token = widget.authProvider.token;
      
      if (token == null) {
        setState(() {
          _milestonesError = 'Not authenticated';
          _isLoadingMilestones = false;
        });
        return;
      }
      
      // Get project ID - handle both zoho_ prefix and direct ID
      final projectId = widget.project['zoho_project_id']?.toString() ?? 
                       widget.project['id']?.toString() ?? '';
      
      // Remove zoho_ prefix if present
      final actualProjectId = projectId.startsWith('zoho_') 
          ? projectId.replaceFirst('zoho_', '') 
          : projectId;
      
      if (actualProjectId.isEmpty) {
        setState(() {
          _milestonesError = 'Project ID not found';
          _isLoadingMilestones = false;
        });
        return;
      }
      
      // Get portal ID from zoho_data if available
      final zohoData = widget.project['zoho_data'] as Map<String, dynamic>?;
      final portalId = zohoData?['portal_id']?.toString() ?? 
                      zohoData?['portal']?.toString();
      
      final response = await widget.apiService.getZohoMilestones(
        projectId: actualProjectId,
        token: token,
        portalId: portalId,
      );
      
      final milestones = response['milestones'] ?? [];
      
      print('🎯 Received ${milestones.length} milestones from API');
      
      setState(() {
        _milestones = milestones;
        _isLoadingMilestones = false;
      });
    } catch (e) {
      print('❌ Error loading milestones: $e');
      setState(() {
        _milestonesError = e.toString();
        _isLoadingMilestones = false;
      });
    }
  }

  Future<void> _loadTasks() async {
    if (!widget.isZohoProject || _hasLoadedTasks || _isLoadingTasks) return;
    
    setState(() {
      _isLoadingTasks = true;
      _tasksError = null;
      _hasLoadedTasks = true;
    });
    
    try {
      final token = widget.authProvider.token;
      
      if (token == null) {
        setState(() {
          _tasksError = 'Not authenticated';
          _isLoadingTasks = false;
        });
        return;
      }
      
      // Get project ID - handle both zoho_ prefix and direct ID
      final projectId = widget.project['zoho_project_id']?.toString() ?? 
                       widget.project['id']?.toString() ?? '';
      
      // Remove zoho_ prefix if present
      final actualProjectId = projectId.startsWith('zoho_') 
          ? projectId.replaceFirst('zoho_', '') 
          : projectId;
      
      if (actualProjectId.isEmpty) {
        setState(() {
          _tasksError = 'Project ID not found';
          _isLoadingTasks = false;
        });
        return;
      }
      
      // Get portal ID from zoho_data if available
      final zohoData = widget.project['zoho_data'] as Map<String, dynamic>?;
      final portalId = zohoData?['portal_id']?.toString() ?? 
                      zohoData?['portal']?.toString();
      
      final response = await widget.apiService.getZohoTasks(
        projectId: actualProjectId,
        token: token,
        portalId: portalId,
      );
      
      final tasks = response['tasks'] ?? [];
      
      // Debug: Log task structure to see if subtasks are present
      if (tasks.isNotEmpty) {
        print('📋 Received ${tasks.length} tasks from API');
        for (var i = 0; i < tasks.length; i++) {
          final task = tasks[i];
          final taskName = task['name']?.toString() ?? 'Unnamed';
          final subtasks = task['subtasks'];
          print('   Task $i: "$taskName" - subtasks: ${subtasks != null ? (subtasks is List ? (subtasks as List).length : 'not a list') : 'null'}');
          if (subtasks != null && subtasks is List && (subtasks as List).isNotEmpty) {
            print('      Subtask names: ${(subtasks as List).map((s) => s['name']?.toString() ?? 'Unnamed').join(', ')}');
          }
        }
      }
      
      setState(() {
        _tasks = tasks;
        _isLoadingTasks = false;
      });
    } catch (e) {
      setState(() {
        _tasksError = e.toString();
        _isLoadingTasks = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 800),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E), // Dark grey background
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D2D),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: widget.isZohoProject ? Colors.blue.shade700 : Colors.purple.shade700,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Project',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                // Project Title
                if (widget.isZohoProject)
                  Container(
                    padding: const EdgeInsets.all(20),
                    color: const Color(0xFF1E1E1E),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                          widget.project['name'] ?? 'Project',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                            ),
                        Text(
                          '${_tasks.length} Tasks',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        // Sync Members Button (show for all Zoho projects)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: _SyncZohoMembersButton(
                            project: widget.project,
                            apiService: widget.apiService,
                            authProvider: widget.authProvider,
                            onSyncComplete: () {
                              // Optionally refresh or show success message
                            },
                          ),
                        ),
                      ],
                    ),
                  )
                else
                Container(
                  padding: const EdgeInsets.all(20),
                  color: const Color(0xFF1E1E1E),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          widget.project['name'] ?? 'Project',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Active',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Tabs for Milestones and Tasks (Zoho projects only)
                if (widget.isZohoProject)
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D2D2D),
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade700, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _selectedTab = 0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: _selectedTab == 0 ? Colors.blue.shade400 : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.flag,
                                    size: 18,
                                    color: _selectedTab == 0 ? Colors.blue.shade400 : Colors.grey.shade400,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Milestones (${_milestones.length})',
                                    style: TextStyle(
                                      color: _selectedTab == 0 ? Colors.blue.shade400 : Colors.grey.shade400,
                                      fontSize: 14,
                                      fontWeight: _selectedTab == 0 ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _selectedTab = 1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: _selectedTab == 1 ? Colors.blue.shade400 : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.task,
                                    size: 18,
                                    color: _selectedTab == 1 ? Colors.blue.shade400 : Colors.grey.shade400,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Tasks (${_tasks.length})',
                                    style: TextStyle(
                                      color: _selectedTab == 1 ? Colors.blue.shade400 : Colors.grey.shade400,
                                      fontSize: 14,
                                      fontWeight: _selectedTab == 1 ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Content - For Zoho projects, show milestones or tasks based on selected tab
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: widget.isZohoProject
                        ? Builder(
                            builder: (context) {
                              // Milestones Tab
                              if (_selectedTab == 0) {
                                if (_isLoadingMilestones) {
                                  return const Padding(
                                    padding: EdgeInsets.all(40),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                
                                if (_milestonesError != null) {
                                  return Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      children: [
                                        Text(
                                          'Error loading milestones: $_milestonesError',
                                          style: const TextStyle(color: Colors.red, fontSize: 14),
                                        ),
                                        const SizedBox(height: 12),
                                        ElevatedButton.icon(
                                          onPressed: _loadMilestones,
                                          icon: const Icon(Icons.refresh, size: 18),
                                          label: const Text('Retry'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blue.shade700,
                                            foregroundColor: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                
                                if (_milestones.isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.all(40),
                                    child: Center(
                                      child: Text(
                                        'No milestones found',
                                        style: TextStyle(color: Colors.grey, fontSize: 14),
                                      ),
                                    ),
                                  );
                                }
                                
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: _milestones.map((milestone) {
                                      final name = milestone['name']?.toString() ?? 
                                                   milestone['milestone_name']?.toString() ?? 
                                                   'Unnamed Milestone';
                                      final startDate = milestone['start_date'] ?? 
                                                       milestone['start_date_format'];
                                      final endDate = milestone['end_date'] ?? 
                                                     milestone['end_date_format'];
                                      final status = milestone['status']?.toString() ?? 'Unknown';
                                      final description = milestone['description']?.toString();
                                      
                                      Color statusColor = Colors.grey;
                                      if (status.toLowerCase().contains('completed') || 
                                          status.toLowerCase().contains('done')) {
                                        statusColor = Colors.green;
                                      } else if (status.toLowerCase().contains('in progress') ||
                                                 status.toLowerCase().contains('active')) {
                                        statusColor = Colors.blue;
                                      } else if (status.toLowerCase().contains('pending') ||
                                                 status.toLowerCase().contains('not started')) {
                                        statusColor = Colors.orange;
                                      }
                                      
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 12),
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2D2D2D),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.grey.shade700, width: 1),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.flag,
                                                  size: 20,
                                                  color: statusColor,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    name,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: statusColor.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: statusColor.withOpacity(0.5)),
                                                  ),
                                                  child: Text(
                                                    status.toUpperCase(),
                                                    style: TextStyle(
                                                      color: statusColor,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (description != null && description.isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              Text(
                                                description,
                                                style: TextStyle(
                                                  color: Colors.grey.shade300,
                                                  fontSize: 13,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.calendar_today,
                                                  size: 14,
                                                  color: Colors.grey.shade400,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  '${startDate != null ? _formatSimpleDate(startDate) : 'TBD'} - ${endDate != null ? _formatSimpleDate(endDate) : 'TBD'}',
                                                  style: TextStyle(
                                                    color: Colors.grey.shade300,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                );
                              }
                              
                              // Tasks Tab
                              if (_isLoadingTasks) {
                                return const Padding(
                                  padding: EdgeInsets.all(40),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              
                              if (_tasksError != null) {
                                return Padding(
                                  padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                                      Text(
                                        'Error loading tasks: $_tasksError',
                                        style: const TextStyle(color: Colors.red, fontSize: 14),
                          ),
                                      const SizedBox(height: 12),
                                      ElevatedButton.icon(
                                        onPressed: _loadTasks,
                                        icon: const Icon(Icons.refresh, size: 18),
                                        label: const Text('Retry'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue.shade700,
                                          foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                                );
                              }
                              
                              if (_tasks.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.all(40),
                                  child: Center(
                                    child: Text(
                                      'No tasks found',
                                      style: TextStyle(color: Colors.grey, fontSize: 14),
                                    ),
                                  ),
                                );
                              }
                              
                              // Group tasks by tasklist (domain)
                              // Each tasklist will show its milestone info inside
                              final Map<String, List<dynamic>> tasksByTasklist = {};
                              final Map<String, Map<String, dynamic>> tasklistMilestoneMap = {};
                              
                              for (final task in _tasks) {
                                // Get tasklist name
                                final tasklistName = task['tasklist_name']?.toString() ?? 'Uncategorized';
                                
                                // Get milestone info for this tasklist
                                final milestoneId = task['milestone_id']?.toString();
                                final milestoneName = task['milestone_name']?.toString();
                                final milestoneStartDate = task['milestone_start_date'];
                                final milestoneEndDate = task['milestone_end_date'];
                                
                                // Store milestone info for this tasklist (only once per tasklist)
                                if (!tasklistMilestoneMap.containsKey(tasklistName)) {
                                  if (milestoneId != null && milestoneName != null) {
                                    tasklistMilestoneMap[tasklistName] = {
                                      'id': milestoneId,
                                      'name': milestoneName,
                                      'start_date': milestoneStartDate,
                                      'end_date': milestoneEndDate,
                                    };
                                  } else {
                                    tasklistMilestoneMap[tasklistName] = {};
                                  }
                                }
                                
                                // Initialize tasklist group if needed
                                if (!tasksByTasklist.containsKey(tasklistName)) {
                                  tasksByTasklist[tasklistName] = [];
                                }
                                
                                tasksByTasklist[tasklistName]!.add(task);
                              }
                              
                              return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                children: tasksByTasklist.entries.map((tasklistEntry) {
                                  final tasklistName = tasklistEntry.key;
                                  final tasksInList = tasklistEntry.value;
                                  
                                  // Get milestone info for this tasklist
                                  final milestoneInfo = tasklistMilestoneMap[tasklistName];
                                  final hasMilestone = milestoneInfo != null && milestoneInfo.isNotEmpty;
                                  
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2D2D2D),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.grey.shade700, width: 1),
                                    ),
                                    child: ExpansionTile(
                                      initiallyExpanded: true,
                                      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
                                      title: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Domain/Tasklist Name
                                          Row(
                                    children: [
                                          Icon(
                                            Icons.folder,
                                            size: 18,
                                            color: Colors.blue.shade300,
                                          ),
                                          const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                            tasklistName,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          // Milestone Info inside the domain
                                          if (hasMilestone) ...[
                                            const SizedBox(height: 8),
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade900.withOpacity(0.2),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: Colors.blue.shade700.withOpacity(0.5), width: 1),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  // Milestone Name
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.flag,
                                                        size: 14,
                                                        color: Colors.blue.shade300,
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Expanded(
                                                        child: Text(
                                                          milestoneInfo['name']?.toString() ?? 'Unnamed Milestone',
                                                          style: TextStyle(
                                                            color: Colors.blue.shade300,
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  // Milestone Dates
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.calendar_today,
                                                        size: 12,
                                                        color: Colors.grey.shade400,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        '${milestoneInfo['start_date'] != null ? _formatSimpleDate(milestoneInfo['start_date']) : 'TBD'} - ${milestoneInfo['end_date'] != null ? _formatSimpleDate(milestoneInfo['end_date']) : 'TBD'}',
                                                        style: TextStyle(
                                                          color: Colors.grey.shade300,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                              ],
                            ),
                                      children: tasksInList.map((task) {
                                        // Extract only the data we need: name, date, assigned person
                                        final taskName = task['name']?.toString() ?? 
                                                        task['task_name']?.toString() ?? 
                                                        'Unnamed Task';
                                        
                                        // Get date - try multiple fields
                                        String? taskDate;
                                        if (task['start_date'] != null) {
                                          taskDate = _formatSimpleDate(task['start_date']);
                                        } else if (task['start_date_format'] != null) {
                                          taskDate = task['start_date_format'].toString();
                                        } else if (task['end_date'] != null) {
                                          taskDate = _formatSimpleDate(task['end_date']);
                                        } else if (task['end_date_format'] != null) {
                                          taskDate = task['end_date_format'].toString();
                                        }
                                        
                                        // Get assigned person
                                        String assignedPerson = 'Unassigned';
                                        if (task['owner_name'] != null) {
                                          assignedPerson = task['owner_name'].toString();
                                        } else if (task['details']?['owners'] != null && 
                                                  (task['details']?['owners'] as List).isNotEmpty) {
                                          final owner = (task['details']?['owners'] as List)[0];
                                          assignedPerson = owner['full_name']?.toString() ?? 
                                                          owner['name']?.toString() ?? 
                                                          'Unassigned';
                                        }
                                        
                                        // Get subtasks - check multiple possible field names and types
                                        // IMPORTANT: Create a final list that will be captured in the closure
                                        final List<dynamic> finalSubtasks = () {
                                          dynamic subtasksRaw = task['subtasks'];
                                          List<dynamic> subtasksList = [];
                                          
                                          // Debug: Check what we actually have
                                          print('🔍 Task "${taskName}" - subtasksRaw type: ${subtasksRaw.runtimeType}, value: $subtasksRaw');
                                          
                                          if (subtasksRaw != null) {
                                            if (subtasksRaw is List) {
                                              subtasksList = List<dynamic>.from(subtasksRaw); // Create a copy
                                              print('✅ Found ${subtasksList.length} subtasks as List');
                                            } else if (subtasksRaw is Map) {
                                              // Sometimes subtasks might be in a nested structure
                                              print('⚠️ Subtasks is a Map, not a List. Keys: ${(subtasksRaw as Map).keys.toList()}');
                                            } else {
                                              print('⚠️ Subtasks is neither List nor Map: ${subtasksRaw.runtimeType}');
                                            }
                                          }
                                          
                                          // Try alternative field names if first attempt failed
                                          if (subtasksList.isEmpty) {
                                            final subTasksAlt = task['sub_tasks'];
                                            if (subTasksAlt != null && subTasksAlt is List) {
                                              subtasksList = List<dynamic>.from(subTasksAlt);
                                              print('✅ Found ${subtasksList.length} subtasks in sub_tasks field');
                                            }
                                          }
                                          
                                          if (subtasksList.isEmpty) {
                                            final subtaskList = task['subtask_list'];
                                            if (subtaskList != null && subtaskList is List) {
                                              subtasksList = List<dynamic>.from(subtaskList);
                                              print('✅ Found ${subtasksList.length} subtasks in subtask_list field');
                                            }
                                          }
                                          
                                          // Sort subtasks by creation order (first created at top)
                                          if (subtasksList.isNotEmpty) {
                                            subtasksList.sort((a, b) {
                                              // First try order_sequence (if available)
                                              final orderA = a['order_sequence'];
                                              final orderB = b['order_sequence'];
                                              if (orderA != null && orderB != null) {
                                                return (orderA as num).compareTo(orderB as num);
                                              }
                                              
                                              // Fallback to created_time_long
                                              final timeA = a['created_time_long'] ?? a['created_time'];
                                              final timeB = b['created_time_long'] ?? b['created_time'];
                                              if (timeA != null && timeB != null) {
                                                final timeAVal = timeA is num ? timeA : (timeA is String ? int.tryParse(timeA) ?? 0 : 0);
                                                final timeBVal = timeB is num ? timeB : (timeB is String ? int.tryParse(timeB) ?? 0 : 0);
                                                return (timeAVal as num).compareTo(timeBVal as num);
                                              }
                                              
                                              // If no sort criteria, keep original order
                                              return 0;
                                            });
                                            
                                            print('📋 Task "${taskName}" FINAL: ${subtasksList.length} subtasks ready for UI (sorted by creation order)');
                                            print('   Subtask names: ${subtasksList.map((s) => s['name']?.toString() ?? 'Unnamed').join(', ')}');
                                          } else {
                                            print('❌ Task "${taskName}" FINAL: NO subtasks found. All task keys: ${task.keys.toList()}');
                                          }
                                          
                                          return subtasksList;
                                        }();
                                        
                                  return Container(
                                          margin: const EdgeInsets.only(bottom: 6),
                                    decoration: BoxDecoration(
                                            color: const Color(0xFF1E1E1E),
                                      borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.grey.shade800, width: 1),
                                    ),
                                          child: ExpansionTile(
                                            initiallyExpanded: false,
                                            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            childrenPadding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
                                            title: Row(
                                      children: [
                                                // Task Name
                                                Expanded(
                                                  child: Text(
                                                    taskName,
                                          style: const TextStyle(
                                            color: Colors.white,
                                                      fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                                ),
                                                const SizedBox(width: 12),
                                                // Date
                                                if (taskDate != null)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.grey.shade800,
                                                      borderRadius: BorderRadius.circular(4),
                          ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons.calendar_today,
                                                          size: 12,
                                                          color: Colors.grey.shade400,
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          taskDate,
                                                          style: TextStyle(
                                                            color: Colors.grey.shade300,
                                                            fontSize: 11,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                const SizedBox(width: 8),
                                                // Assigned Person
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                                    color: Colors.blue.shade800.withOpacity(0.3),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.person,
                                                        size: 12,
                                                        color: Colors.blue.shade300,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        assignedPerson,
                                      style: TextStyle(
                                        color: Colors.blue.shade300,
                                                          fontSize: 11,
                                                        ),
                                      ),
                                                    ],
                                                  ),
                              ),
                                              ],
                          ),
                                            children: () {
                                              // Use the finalSubtasks that was captured when the widget was built
                                              print('🎯 Building children for "${taskName}" - finalSubtasks.length: ${finalSubtasks.length}');
                                              
                                              if (finalSubtasks.isEmpty) {
                                                return <Widget>[
                                                  Padding(
                                                    padding: const EdgeInsets.all(12),
                                                    child: Text(
                                                      'No subtasks',
                                                      style: TextStyle(
                                                        color: Colors.grey.shade500,
                                                        fontSize: 12,
                                                        fontStyle: FontStyle.italic,
                                                      ),
                                                    ),
                                                  ),
                                                ];
                                              }
                                              
                                              return finalSubtasks.map<Widget>((subtask) {
                                                    // Extract subtask data: name, date, assigned person
                                                    final subtaskName = subtask['name']?.toString() ?? 
                                                                      subtask['task_name']?.toString() ?? 
                                                                      'Unnamed Subtask';
                                                    
                                                    // Get subtask date
                                                    String? subtaskDate;
                                                    if (subtask['start_date'] != null) {
                                                      subtaskDate = _formatSimpleDate(subtask['start_date']);
                                                    } else if (subtask['start_date_format'] != null) {
                                                      subtaskDate = subtask['start_date_format'].toString();
                                                    } else if (subtask['end_date'] != null) {
                                                      subtaskDate = _formatSimpleDate(subtask['end_date']);
                                                    } else if (subtask['end_date_format'] != null) {
                                                      subtaskDate = subtask['end_date_format'].toString();
                                                    }
                                                    
                                                    // Get subtask assigned person
                                                    String subtaskAssigned = 'Unassigned';
                                                    if (subtask['owner_name'] != null) {
                                                      subtaskAssigned = subtask['owner_name'].toString();
                                                    } else if (subtask['details']?['owners'] != null && 
                                                              (subtask['details']?['owners'] as List).isNotEmpty) {
                                                      final owner = (subtask['details']?['owners'] as List)[0];
                                                      subtaskAssigned = owner['full_name']?.toString() ?? 
                                                                       owner['name']?.toString() ?? 
                                                                       'Unassigned';
                                                    }
                                                    
                                                    return Container(
                                                      margin: const EdgeInsets.only(bottom: 6),
                                                      padding: const EdgeInsets.all(10),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF2D2D2D),
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: Colors.grey.shade800, width: 1),
                                          ),
                                                      child: Row(
                                    children: [
                                                          Icon(
                                                            Icons.subdirectory_arrow_right,
                                                            size: 16,
                                                            color: Colors.grey.shade400,
                                                          ),
                                                          const SizedBox(width: 10),
                                                          // Subtask Name
                                      Expanded(
                                                            child: Text(
                                                              subtaskName,
                                                              style: const TextStyle(
                                                                color: Colors.white,
                                                                fontSize: 13,
                                                                fontWeight: FontWeight.w400,
                                                              ),
                                        ),
                                      ),
                                                          const SizedBox(width: 12),
                                                          // Subtask Date
                                                          if (subtaskDate != null)
                                                            Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                              decoration: BoxDecoration(
                                                                color: Colors.grey.shade800,
                                                                borderRadius: BorderRadius.circular(4),
                                        ),
                                                              child: Row(
                                                                mainAxisSize: MainAxisSize.min,
                                                                children: [
                                                                  Icon(
                                                                    Icons.calendar_today,
                                                                    size: 10,
                                                                    color: Colors.grey.shade400,
                          ),
                                                                  const SizedBox(width: 4),
                                                                  Text(
                                                                    subtaskDate,
                                                                    style: TextStyle(
                                                                      color: Colors.grey.shade300,
                                                                      fontSize: 10,
                                                                    ),
                                                                  ),
                      ],
                    ),
                  ),
                                                          const SizedBox(width: 8),
                                                          // Subtask Assigned Person
                  Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                                                              color: Colors.blue.shade800.withOpacity(0.3),
                                                              borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                                                              mainAxisSize: MainAxisSize.min,
                      children: [
                                                                Icon(
                                                                  Icons.person,
                                                                  size: 10,
                                                                  color: Colors.blue.shade300,
                        ),
                                                                const SizedBox(width: 4),
                                                                Text(
                                                                  subtaskAssigned,
                                                                  style: TextStyle(
                                                                    color: Colors.blue.shade300,
                                                                    fontSize: 10,
                                                                  ),
                                                                ),
                                                              ],
                          ),
                        ),
                      ],
                                                      ),
                                                    );
                                                  }).toList();
                                              }(),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          )
                        : const SizedBox.shrink(), // Non-Zoho projects handled elsewhere
                    ),
                  ),
              ],
            ),
          ),
        );
  }

  // Helper methods that need to be accessible
  String? _formatSimpleDate(dynamic dateValue) {
    if (dateValue == null) return null;
    
    try {
      // If it's already a formatted string, return it
      if (dateValue is String) {
        // Check if it's an ISO date string
        if (dateValue.contains('T') || dateValue.contains('Z')) {
          final date = DateTime.parse(dateValue);
          return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
        }
        // If it's already formatted, return as is
        return dateValue;
      }
      
      // If it's a timestamp (long)
      if (dateValue is int || dateValue is num) {
        final date = DateTime.fromMillisecondsSinceEpoch(dateValue.toInt());
        return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
      }
      
      return dateValue.toString();
    } catch (e) {
      return dateValue.toString();
    }
  }

  Widget _buildTaskInfoField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
                          ),
                        ),
                        const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                        ),
                    ),
                  ),
              ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    final statusLower = status.toLowerCase();
    if (statusLower.contains('completed') || statusLower.contains('done') || statusLower.contains('closed')) {
      return Colors.green;
    } else if (statusLower.contains('in progress') || statusLower.contains('working') || statusLower.contains('active')) {
      return Colors.blue;
    } else if (statusLower.contains('pending') || statusLower.contains('waiting') || statusLower.contains('on hold')) {
      return Colors.orange;
    } else if (statusLower.contains('cancelled') || statusLower.contains('rejected')) {
      return Colors.red;
    } else {
      return Colors.grey;
    }
  }

  Widget _buildCollapsibleSection({
    required String title,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade800, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                    color: Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) child,
        ],
      ),
    );
  }

  Widget _buildInfoField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade800, width: 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAllZohoFields(Map<String, dynamic> zohoData, {bool excludeCommon = false}) {
    final List<Widget> fields = [];
    final excludedKeys = excludeCommon ? [
      'id', 'name', 'description', 'status', 'start_date', 'end_date', 
      'owner_name', 'created_time', 'created_at', 'updated_at'
    ] : [];
    
    zohoData.forEach((key, value) {
      // Skip null, empty, or excluded values
      if (value == null || excludedKeys.contains(key)) return;
      
      // Skip complex objects and arrays (we'll handle them separately)
      if (value is Map || value is List) return;
      
      // Format the key name (convert snake_case to Title Case)
      String label = key
          .replaceAll('_', ' ')
          .split(' ')
          .map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1))
          .join(' ');
      
      // Format the value
      String displayValue = value.toString();
      if (value is num && key.contains('percentage')) {
        displayValue = '$value%';
      }
      
      fields.add(_buildInfoField(label, displayValue));
    });
    
    return fields;
  }

  String? _formatDateString(dynamic dateValue) {
    if (dateValue == null) return null;
    
    try {
      // Handle different date formats
      String dateStr = dateValue.toString();
      
      // Try parsing ISO format
      if (dateStr.contains('T') || dateStr.contains('Z')) {
        final date = DateTime.parse(dateStr);
        return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }
      
      // Try parsing other common formats
      if (dateStr.contains('/')) {
        return dateStr; // Already formatted
      }
      
      // Default: return as is
      return dateStr;
    } catch (e) {
      return dateValue.toString();
    }
  }
}

// Sync Zoho Members Button Widget
class _SyncZohoMembersButton extends StatefulWidget {
  final dynamic project;
  final ApiService apiService;
  final dynamic authProvider;
  final VoidCallback? onSyncComplete;

  const _SyncZohoMembersButton({
    required this.project,
    required this.apiService,
    required this.authProvider,
    this.onSyncComplete,
  });

  @override
  State<_SyncZohoMembersButton> createState() => _SyncZohoMembersButtonState();
}

class _SyncZohoMembersButtonState extends State<_SyncZohoMembersButton> {
  bool _isSyncing = false;

  // Get Zoho project ID
  String? _getZohoProjectId() {
    // Try different possible fields
    var zohoProjectId = widget.project['zoho_project_id']?.toString() ?? 
                        widget.project['zoho_id']?.toString() ??
                        widget.project['id']?.toString();
    
    // Also check zoho_data
    if (zohoProjectId == null) {
      final zohoData = widget.project['zoho_data'] as Map<String, dynamic>?;
      zohoProjectId = zohoData?['id']?.toString();
    }
    
    if (zohoProjectId == null) return null;
    
    // Remove 'zoho_' prefix if present
    if (zohoProjectId.startsWith('zoho_')) {
      return zohoProjectId.replaceFirst('zoho_', '');
    }
    
    return zohoProjectId;
  }

  // Get portal ID
  String? _getPortalId() {
    // Try multiple sources for portal ID
    final portalId = widget.project['portal_id']?.toString() ??
                     widget.project['portalId']?.toString();
    
    if (portalId != null) return portalId;
    
    final zohoData = widget.project['zoho_data'] as Map<String, dynamic>?;
    return zohoData?['portal_id']?.toString() ?? 
           zohoData?['portal']?.toString();
  }

  // Check if user has permission to sync
  bool _canSync() {
    final userRole = widget.authProvider.user?['role'];
    return userRole == 'admin' || userRole == 'project_manager' || userRole == 'lead';
  }

  Future<void> _syncMembers() async {
    final zohoProjectId = _getZohoProjectId();

    if (zohoProjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Zoho Project ID not found'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_canSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to sync members. Only admins, project managers, and leads can sync.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    final token = widget.authProvider.token;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not authenticated'), backgroundColor: Colors.red),
      );
      return;
    }

    final portalId = _getPortalId();
    final zohoProjectName = widget.project['name']?.toString();

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    Map<String, dynamic>? preview;
    try {
      preview = await widget.apiService.syncZohoProjectMembersPreview(
        zohoProjectId: zohoProjectId,
        portalId: portalId,
        zohoProjectName: zohoProjectName,
        token: token,
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load preview: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    final projectName = preview['projectName']?.toString() ?? 'Unknown';
    final existingProject = preview['existingProject'] == true;
    final domainsList = preview['domains'];
    final domains = domainsList is List ? domainsList : <dynamic>[];
    final domainNames = domains
        .map((d) => d is Map ? '${d['name'] ?? d['code'] ?? '?'} (${d['code'] ?? ''})'.trim().replaceAll(' ()', '') : '$d')
        .where((s) => s.isNotEmpty)
        .toList();
    final domainSummary = domainNames.isEmpty ? 'No domains from Zoho tasklists' : domainNames.join(', ');
    final technologyNode = preview['technology_node']?.toString();
    final startDate = preview['start_date']?.toString();
    final targetDate = preview['target_date']?.toString();
    final techLine = technologyNode != null && technologyNode.isNotEmpty ? 'Technology node: $technologyNode' : null;
    final startLine = startDate != null && startDate.isNotEmpty ? 'Start date: $startDate' : null;
    final targetLine = targetDate != null && targetDate.isNotEmpty ? 'Target date: $targetDate' : null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Sync Projects'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The following will be added or updated in the database:',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text('Project: $projectName', style: const TextStyle(fontWeight: FontWeight.w600)),
              if (existingProject) Text('(existing project will be updated)', style: Theme.of(ctx).textTheme.bodySmall),
              if (techLine != null) ...[const SizedBox(height: 6), Text(techLine, style: const TextStyle(fontWeight: FontWeight.w500))],
              if (startLine != null) ...[const SizedBox(height: 4), Text(startLine, style: const TextStyle(fontWeight: FontWeight.w500))],
              if (targetLine != null) ...[const SizedBox(height: 4), Text(targetLine, style: const TextStyle(fontWeight: FontWeight.w500))],
              const SizedBox(height: 8),
              Text('Domains: $domainSummary', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              const Text('Members from Zoho will be synced to this project. Continue?'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isSyncing = true;
    });
    try {
      final result = await widget.apiService.syncZohoProjectMembersByZohoId(
        zohoProjectId: zohoProjectId,
        portalId: portalId,
        zohoProjectName: zohoProjectName,
        token: token,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully synced ${result['updatedAssignments']} members. '
              'Created ${result['createdUsers']} new users.'
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );

        if (result['errors'] != null && (result['errors'] as List).isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Sync completed with ${(result['errors'] as List).length} errors. Check console for details.'
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }

        widget.onSyncComplete?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error syncing members: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canSync()) {
      return const SizedBox.shrink();
    }

    final zohoProjectId = _getZohoProjectId();
    final hasZohoProjectId = zohoProjectId != null;

    return Tooltip(
      message: !hasZohoProjectId
          ? 'Zoho Project ID not found'
          : 'Sync members from Zoho project',
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: (_isSyncing || !hasZohoProjectId) ? null : _syncMembers,
          icon: _isSyncing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.sync, size: 18),
          label: Text(_isSyncing ? 'Syncing...' : 'Sync Members from Zoho'),
          style: ElevatedButton.styleFrom(
            backgroundColor: hasZohoProjectId
                ? const Color(0xFF14B8A6)
                : Colors.grey.shade600,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}

