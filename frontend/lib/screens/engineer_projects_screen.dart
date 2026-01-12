import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/view_screen_provider.dart';
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

  void _navigateToViewScreen(dynamic project) {
    final isMapped = project['is_mapped'] == true;
    
    // If project is mapped, show dialog with two buttons
    if (isMapped) {
      _showMappedProjectOptions(project);
    } else {
      // Project not mapped - show details dialog instead
      _showProjectDetails(project);
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
                    const SizedBox(height: 8),
                    const Text(
                      'Choose an option to proceed:',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Project Plan Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _showProjectPlan(project);
                        },
                        icon: const Icon(Icons.list_alt, size: 20),
                        label: const Text(
                          'Project Plan',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // View Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          // Navigate to View screen
      ref.read(viewScreenParamsProvider.notifier).state = ViewScreenParams(
        project: project['name'],
        viewType: 'engineer',
      );
      // Switch to View tab (index 2 for engineers) in MainNavigationScreen
      ref.read(navigationIndexProvider.notifier).state = 2;
      // Pop any dialogs first, then the ViewScreen in MainNavigationScreen will read params and auto-load
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((route) => route.isFirst || route.settings.name == '/');
      }
                        },
                        icon: const Icon(Icons.visibility, size: 20),
                        label: const Text(
                          'View',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
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
      
      final response = await _apiService.getZohoTasks(
        projectId: actualProjectId,
        token: token,
        portalId: portalId,
      );
      
      final tasks = response['tasks'] ?? [];

      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        
        // Show tasks and subtasks dialog
        _showTasksDialog(project, tasks);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading tasks: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
      final block = <String, dynamic>{
        'name': taskName,
        'type': domainType == 'PD' ? 'block' : 'module',
        'requirements': <Map<String, dynamic>>[],
      };
      
      // Map subtasks as requirements (only for DV)
      if (domainType == 'DV' && subtasks.isNotEmpty) {
        for (final subtask in subtasks) {
          final subtaskName = (subtask['name'] ?? subtask['task_name'] ?? 'Unnamed Subtask').toString();
          block['requirements'].add({
            'name': subtaskName,
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

  void _showTasksDialog(dynamic project, List<dynamic> tasks) {
    final projectName = project['name'] ?? 'Project';
    
    // Map tasks to project structure
    final mappedData = _mapTasksToProjectStructure(tasks);
    final domains = mappedData['domains'] as List<dynamic>;
    
    // Store original tasks and project for export
    final originalTasks = List<dynamic>.from(tasks);
    final projectData = project;
    
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
                          _exportMappedData(projectName, mappedData, originalTasks: originalTasks, project: projectData);
                        },
                        icon: const Icon(Icons.download, size: 16),
                        label: const Text('Export JSON'),
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
                          // Navigate to View screen
                          ref.read(viewScreenParamsProvider.notifier).state = ViewScreenParams(
                            project: project['name'],
                            viewType: 'engineer',
                          );
                          // Switch to View tab (index 2 for engineers) in MainNavigationScreen
                          ref.read(navigationIndexProvider.notifier).state = 2;
                          // Pop any dialogs first, then the ViewScreen in MainNavigationScreen will read params and auto-load
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).popUntil((route) => route.isFirst || route.settings.name == '/');
                          }
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

  void _exportMappedData(String projectName, Map<String, dynamic> mappedData, {List<dynamic>? originalTasks, dynamic project}) {
    // Create simplified export data structure with only essential fields
    final domains = mappedData['domains'] as List<dynamic>;
    
    // Get project dates
    final startDate = project?['start_date']?.toString() ?? '';
    final updatedDate = project?['updated_at']?.toString() ?? '';
    
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
        
        // Get dates from original task if available
        String? blockStartDate;
        String? blockUpdatedDate;
        
        if (originalTasks != null) {
          for (final task in originalTasks) {
            final taskName = (task['name'] ?? task['task_name'] ?? '').toString();
            if (taskName == blockName) {
              blockStartDate = task['start_date']?.toString() ?? task['created_time']?.toString() ?? '';
              blockUpdatedDate = task['updated_at']?.toString() ?? task['modified_time']?.toString() ?? '';
              break;
            }
          }
        }
        
        final simplifiedBlock = <String, dynamic>{
          'block': blockName,
          if (blockStartDate != null && blockStartDate.isNotEmpty) 'start_date': blockStartDate,
          if (blockUpdatedDate != null && blockUpdatedDate.isNotEmpty) 'updated_date': blockUpdatedDate,
        };
        
        // Add requirements/modules only for DV domains
        if (requirements.isNotEmpty) {
          simplifiedBlock['requirements'] = requirements.map((req) {
            final reqName = req['name'] ?? '';
            return reqName;
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
    
    // Create simplified export data structure
    final exportData = {
      'project_name': projectName,
      if (startDate.isNotEmpty) 'start_date': startDate,
      if (updatedDate.isNotEmpty) 'updated_date': updatedDate,
      'domains': exportDomains,
    };
    
    // Convert to JSON string with pretty formatting
    final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
    
    // Show dialog with JSON data
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
              // JSON Content
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
                      jsonString,
                      style: const TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
              // Footer with Copy button
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
                        // Download JSON file
                        final blob = html.Blob([jsonString], 'application/json');
                        final url = html.Url.createObjectUrlFromBlob(blob);
                        final anchor = html.AnchorElement(href: url)
                          ..setAttribute('download', '${projectName.replaceAll(' ', '_')}_project_plan.json')
                          ..click();
                        html.Url.revokeObjectUrl(url);
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('JSON file downloaded: ${projectName.replaceAll(' ', '_')}_project_plan.json'),
                            backgroundColor: Colors.green,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Download JSON'),
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
                            content: Text('JSON data is selectable. Copy manually or use browser copy (Ctrl+C)'),
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // View Data button (only show if project has domains and is mapped)
                      if (domains.isNotEmpty && project['is_mapped'] == true) ...[
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            // Set parameters and switch to View tab
                            final firstDomain = domains[0];
                            ref.read(viewScreenParamsProvider.notifier).state = ViewScreenParams(
                              project: project['name'],
                              domain: firstDomain['name'],
                              viewType: 'engineer',
                            );
                            // Switch to View tab (index 2 for engineers)
                            ref.read(navigationIndexProvider.notifier).state = 2;
                          },
                          icon: const Icon(Icons.visibility, size: 18),
                          label: const Text('View Data'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
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

  Widget _buildInfoChip(IconData icon, String label, MaterialColor color, {double iconSize = 14}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.shade200, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: color.shade700),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value, MaterialColor color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color.shade600),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade900,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                            fontSize: 20,
                          ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${_projects.length} project${_projects.length != 1 ? 's' : ''} assigned',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
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
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _projects.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final project = _projects[index];
                  final isZohoProject = project['source'] == 'zoho';
                  final zohoData = project['zoho_data'] as Map<String, dynamic>?;
                  final projectName = project['name'] ?? 'Project';
                  final startDate = _formatDate(project['start_date']);
                  final dueDate = _formatDate(project['target_date']);
                  final duration = _calculateDuration(project['start_date'], project['target_date']);
                  
                  // Extract Zoho-specific fields
                  final completionPercentage = isZohoProject && zohoData != null && zohoData['completion_percentage'] != null
                      ? '${zohoData['completion_percentage']}%'
                      : '-';
                  
                  // Get status from Zoho data or default to Active
                  final status = isZohoProject && zohoData != null && zohoData['status'] != null
                      ? zohoData['status'].toString()
                      : 'Active';
                  
                  final isMapped = project['is_mapped'] == true;
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _navigateToViewScreen(project),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isMapped ? Colors.green.shade200 : Colors.grey.shade200,
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isMapped 
                                  ? Colors.green.shade100.withOpacity(0.5)
                                  : Colors.black.withOpacity(0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header Row
                              Row(
                                children: [
                                  // Icon with gradient background
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: isMapped
                                          ? [Colors.green.shade400, Colors.green.shade600]
                                          : (isZohoProject 
                                              ? [Colors.blue.shade400, Colors.blue.shade600]
                                              : [Colors.purple.shade400, Colors.purple.shade600]),
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [
                                        BoxShadow(
                                          color: (isMapped ? Colors.green : (isZohoProject ? Colors.blue : Colors.purple))
                                            .withOpacity(0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      isMapped
                                        ? Icons.check_circle
                                        : (isZohoProject ? Icons.cloud : Icons.folder),
                                      size: 24,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Project Name and Mapped Badge
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                projectName,
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.grey.shade900,
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                            ),
                                            if (isMapped)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [Colors.green.shade400, Colors.green.shade600],
                                                  ),
                                                  borderRadius: BorderRadius.circular(6),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.green.withOpacity(0.3),
                                                      blurRadius: 4,
                                                      offset: const Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.check_circle,
                                                      size: 12,
                                                      color: Colors.white,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Mapped',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        // Source Badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: (isZohoProject ? Colors.blue : Colors.purple).shade50,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: (isZohoProject ? Colors.blue : Colors.purple).shade200,
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                isZohoProject ? Icons.cloud : Icons.folder,
                                                size: 12,
                                                color: (isZohoProject ? Colors.blue : Colors.purple).shade700,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                isZohoProject ? 'Zoho Project' : 'Local Project',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: (isZohoProject ? Colors.blue : Colors.purple).shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Info Grid
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    // Status
                                    Expanded(
                                      child: _buildInfoItem(
                                        Icons.circle,
                                        'Status',
                                        status,
                                        Colors.green,
                                      ),
                                    ),
                                    Container(
                                      width: 1,
                                      height: 30,
                                      color: Colors.grey.shade300,
                                    ),
                                    // Start Date
                                    if (startDate != 'N/A')
                                      Expanded(
                                        child: _buildInfoItem(
                                          Icons.calendar_today,
                                          'Start',
                                          startDate,
                                          Colors.blue,
                                        ),
                                      ),
                                    if (startDate != 'N/A')
                                      Container(
                                        width: 1,
                                        height: 30,
                                        color: Colors.grey.shade300,
                                      ),
                                    // End Date
                                    if (dueDate != 'N/A')
                                      Expanded(
                                        child: _buildInfoItem(
                                          Icons.event,
                                          'End',
                                          dueDate,
                                          Colors.orange,
                                        ),
                                      ),
                                    if (dueDate != 'N/A' && duration != '-')
                                      Container(
                                        width: 1,
                                        height: 30,
                                        color: Colors.grey.shade300,
                                      ),
                                    // Duration
                                    if (duration != '-')
                                      Expanded(
                                        child: _buildInfoItem(
                                          Icons.access_time,
                                          'Duration',
                                          duration,
                                          Colors.purple,
                                        ),
                                      ),
                                    if (duration != '-' && completionPercentage != '-')
                                      Container(
                                        width: 1,
                                        height: 30,
                                        color: Colors.grey.shade300,
                                      ),
                                    // Completion %
                                    if (completionPercentage != '-')
                                      Expanded(
                                        child: _buildInfoItem(
                                          Icons.percent,
                                          'Progress',
                                          completionPercentage,
                                          Colors.teal,
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
                },
              ),
          ],
        ),
      ),
    );
  }
}

