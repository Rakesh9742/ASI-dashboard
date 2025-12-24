import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class EngineerProjectsScreen extends ConsumerStatefulWidget {
  const EngineerProjectsScreen({super.key});

  @override
  ConsumerState<EngineerProjectsScreen> createState() => _EngineerProjectsScreenState();
}

class _EngineerProjectsScreenState extends ConsumerState<EngineerProjectsScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  List<dynamic> _projects = [];
  final ScrollController _horizontalScrollController = ScrollController();
  bool _isZohoConnected = false;

  @override
  void initState() {
    super.initState();
    _checkZohoStatus().then((_) {
      _loadProjects();
    });
  }

  Future<void> _checkZohoStatus() async {
    try {
      final authState = ref.read(authProvider);
      final token = authState.token;
      if (token == null) {
        setState(() {
          _isZohoConnected = false;
        });
        return;
      }

      final status = await _apiService.getZohoStatus(token: token);
      setState(() {
        _isZohoConnected = status['connected'] ?? false;
      });
    } catch (e) {
      setState(() {
        _isZohoConnected = false;
      });
    }
  }

  Future<void> _loadProjects() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authState = ref.read(authProvider);
      final token = authState.token;

      // Load projects with Zoho option
      Map<String, dynamic> projectsData;
      if (_isZohoConnected) {
        projectsData = await _apiService.getProjectsWithZoho(token: token, includeZoho: true);
      } else {
        final projects = await _apiService.getProjects(token: token);
        projectsData = {'all': projects, 'local': projects, 'zoho': []};
      }

      setState(() {
        _projects = projectsData['all'] ?? projectsData['local'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading projects: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showProjectDetails(dynamic project) {
    final isZohoProject = project['source'] == 'zoho';
    final domains = (project['domains'] as List<dynamic>? ?? []);
    final zohoData = project['zoho_data'] as Map<String, dynamic>?;
    
    // State for collapsible sections
    final Map<String, bool> sectionStates = {
      'description': false,
      'projectInfo': true,
      'domains': domains.isNotEmpty,
      'zohoInfo': isZohoProject && zohoData != null,
    };
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
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
                          color: isZohoProject ? Colors.blue.shade700 : Colors.purple.shade700,
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
                // Project Title and Status
                Container(
                  padding: const EdgeInsets.all(20),
                  color: const Color(0xFF1E1E1E),
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
                // Content with Collapsible Sections
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Description Section
                        if (project['plan'] != null) ...[
                          _buildCollapsibleSection(
                            title: 'Description',
                            isExpanded: sectionStates['description']!,
                            onToggle: () => setState(() => sectionStates['description'] = !sectionStates['description']!),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 20, top: 12, bottom: 16),
                              child: Text(
                                project['plan'],
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        // Project Information Section
                        _buildCollapsibleSection(
                          title: 'Project Information',
                          isExpanded: sectionStates['projectInfo']!,
                          onToggle: () => setState(() => sectionStates['projectInfo'] = !sectionStates['projectInfo']!),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 20, top: 12, bottom: 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left Column
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildInfoField('Project ID', project['id']?.toString() ?? 'N/A'),
                                      if (project['technology_node'] != null)
                                        _buildInfoField('Technology', project['technology_node']),
                                      if (project['start_date'] != null)
                                        _buildInfoField('Start Date', _formatDateString(project['start_date']) ?? 'N/A'),
                                      if (project['target_date'] != null)
                                        _buildInfoField('Due Date', _formatDateString(project['target_date']) ?? 'N/A'),
                                      // Zoho specific fields
                                      if (isZohoProject && zohoData != null) ...[
                                        if (zohoData['owner_name'] != null)
                                          _buildInfoField('Owner', zohoData['owner_name'].toString()),
                                        if (zohoData['created_by'] != null || zohoData['created_by_name'] != null)
                                          _buildInfoField('Created By', (zohoData['created_by_name'] ?? zohoData['created_by'] ?? 'N/A').toString()),
                                        if (zohoData['priority'] != null)
                                          _buildInfoField('Priority', zohoData['priority'].toString()),
                                        if (zohoData['completion_percentage'] != null)
                                          _buildInfoField('Completion Percentage', '${zohoData['completion_percentage']}%'),
                                        if (zohoData['work_hours'] != null || zohoData['work_hours_p'] != null)
                                          _buildInfoField('Work Hours', (zohoData['work_hours_p'] ?? zohoData['work_hours'] ?? '00:00').toString()),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 24),
                                // Right Column
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildInfoField('Status', isZohoProject && zohoData != null && zohoData['status'] != null ? zohoData['status'].toString() : 'Active'),
                                      if (project['start_date'] != null && project['target_date'] != null)
                                        _buildInfoField('Duration', _calculateDuration(project['start_date'], project['target_date'])),
                                      if (project['created_at'] != null)
                                        _buildInfoField('Created', _formatDateString(project['created_at']) ?? 'N/A'),
                                      if (project['updated_at'] != null)
                                        _buildInfoField('Updated', _formatDateString(project['updated_at']) ?? 'N/A'),
                                      // Zoho specific fields
                                      if (isZohoProject && zohoData != null) ...[
                                        if (zohoData['timelog_total'] != null || zohoData['timelog_total_t'] != null)
                                          _buildInfoField('Timelog Total', (zohoData['timelog_total_t'] ?? zohoData['timelog_total'] ?? '00:00').toString()),
                                        if (zohoData['billing_type'] != null)
                                          _buildInfoField('Billing Type', zohoData['billing_type'].toString()),
                                        if (zohoData['associated_team'] != null || zohoData['team_name'] != null)
                                          _buildInfoField('Associated Team', (zohoData['team_name'] ?? zohoData['associated_team'] ?? 'Not Associated').toString()),
                                        if (zohoData['completion_date'] != null)
                                          _buildInfoField('Completion Date', _formatDateString(zohoData['completion_date']) ?? 'N/A'),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Domains Section
                        if (domains.isNotEmpty) ...[
                          _buildCollapsibleSection(
                            title: 'Domains',
                            isExpanded: sectionStates['domains']!,
                            onToggle: () => setState(() => sectionStates['domains'] = !sectionStates['domains']!),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 20, top: 12, bottom: 16),
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: domains.map((domain) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2D2D2D),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.grey.shade700, width: 1),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          domain['code'] ?? domain['name'] ?? 'Domain',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Icon(
                                          Icons.close,
                                          size: 14,
                                          color: Colors.grey.shade500,
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        // Tags Section (if available)
                        if (isZohoProject && zohoData != null && (zohoData['tags'] != null || zohoData['tag_names'] != null)) ...[
                          _buildCollapsibleSection(
                            title: 'Tags',
                            isExpanded: false,
                            onToggle: () => setState(() {}),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 20, top: 12, bottom: 16),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: ((zohoData['tags'] is List ? zohoData['tags'] : zohoData['tag_names'] is List ? zohoData['tag_names'] : []) as List).map((tag) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2D2D2D),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.blue.shade700, width: 1),
                                    ),
                                    child: Text(
                                      tag.toString(),
                                      style: TextStyle(
                                        color: Colors.blue.shade300,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        // Zoho All Fields Section - Shows ALL fields from zoho_data
                        if (isZohoProject && zohoData != null) ...[
                          _buildCollapsibleSection(
                            title: 'All Zoho Project Fields',
                            isExpanded: sectionStates['zohoInfo']!,
                            onToggle: () => setState(() => sectionStates['zohoInfo'] = !sectionStates['zohoInfo']!),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 20, top: 12, bottom: 16),
                              child: Builder(
                                builder: (context) {
                                  final allFields = _buildAllZohoFields(zohoData, excludeCommon: true);
                                  if (allFields.isEmpty) {
                                    return const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text(
                                        'No additional fields available',
                                        style: TextStyle(color: Colors.grey, fontSize: 14),
                                      ),
                                    );
                                  }
                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: allFields.take((allFields.length / 2).ceil()).toList(),
                                        ),
                                      ),
                                      const SizedBox(width: 24),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: allFields.skip((allFields.length / 2).ceil()).toList(),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        const SizedBox(height: 20),
                      ],
                    ),
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
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Close',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
      String dateStr = dateValue.toString();
      if (dateStr.contains('T') || dateStr.contains('Z')) {
        final date = DateTime.parse(dateStr);
        return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }
      return dateStr;
    } catch (e) {
      return dateValue.toString();
    }
  }

  String _formatDate(dynamic dateValue) {
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadProjects,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Projects',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_projects.length} project${_projects.length != 1 ? 's' : ''} assigned',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Projects Table View
            if (_projects.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(
                        Icons.folder_open,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No projects assigned',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
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
                    ],
                    rows: _projects.map((project) {
                      final isZohoProject = project['source'] == 'zoho';
                      final zohoData = project['zoho_data'] as Map<String, dynamic>?;
                      final projectId = project['id']?.toString() ?? 'N/A';
                      final projectName = project['name'] ?? 'Project';
                      final startDate = _formatDate(project['start_date']);
                      final dueDate = _formatDate(project['target_date']);
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
                                      color: isZohoProject ? Colors.blue.shade50 : Colors.purple.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(
                                      isZohoProject ? Icons.cloud : Icons.folder,
                                      size: 18,
                                      color: isZohoProject ? Colors.blue.shade700 : Colors.purple.shade700,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: Text(
                                      projectName,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
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
}

