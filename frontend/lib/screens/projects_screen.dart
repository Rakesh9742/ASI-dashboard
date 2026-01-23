import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../providers/tab_provider.dart';
import '../providers/view_screen_provider.dart';
import 'main_navigation_screen.dart';
import 'view_screen.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  final _apiService = ApiService();
  List<Map<String, dynamic>> _projects = [];
  bool _isLoading = true;
  String _searchQuery = '';
  // Track which projects have been exported to Linux
  final Set<String> _exportedProjects = <String>{};

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<Map<String, dynamic>> _checkProjectCadRole(String projectIdentifier) async {
    try {
      final token = ref.read(authProvider).token;
      if (token == null) return {'effectiveRole': null};
      
      final roleResponse = await _apiService.getUserProjectRole(
        projectIdentifier: projectIdentifier,
        token: token,
      );
      
      if (roleResponse['success'] == true) {
        return {
          'effectiveRole': roleResponse['effectiveRole'],
          'projectRole': roleResponse['projectRole'],
        };
      }
    } catch (e) {
      // Silently fail - will default to global role check
    }
    return {'effectiveRole': null};
  }

  Future<void> _loadProjects() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final token = ref.read(authProvider).token;
      final userRole = ref.read(authProvider).user?['role'];
      if (token == null) {
        throw Exception('No authentication token');
      }

      // For customers, use regular getProjects API which filters by user_projects
      // For others, try Zoho first, fallback to regular projects
      if (userRole == 'customer') {
        // Customers should use the regular projects API (filters by user_projects)
        final projectsResponse = await _apiService.getProjects(token: token);
        if (mounted) {
          setState(() {
            // Handle both array and object response formats
            if (projectsResponse is List) {
              _projects = List<Map<String, dynamic>>.from(projectsResponse);
            } else {
              // Try to get from map structure
              final projectsMap = projectsResponse as dynamic;
              final allProjects = projectsMap['all'] ?? projectsMap['local'] ?? [];
              if (allProjects is List) {
                _projects = List<Map<String, dynamic>>.from(allProjects);
              } else {
                _projects = [];
              }
            }
            _isLoading = false;
          });
        }
      } else {
        // For non-customers, try Zoho first
        try {
          final response = await _apiService.getZohoProjects(token: token);
          if (mounted) {
            setState(() {
              _projects = List<Map<String, dynamic>>.from(response['projects'] ?? []);
              _isLoading = false;
            });
          }
        } catch (zohoError) {
          // Fallback to regular projects API if Zoho fails
          final projectsResponse = await _apiService.getProjects(token: token);
          if (mounted) {
            setState(() {
              if (projectsResponse is List) {
                _projects = List<Map<String, dynamic>>.from(projectsResponse);
              } else {
                final projectsMap = projectsResponse as dynamic;
                final allProjects = projectsMap['all'] ?? projectsMap['local'] ?? [];
                if (allProjects is List) {
                  _projects = List<Map<String, dynamic>>.from(allProjects);
                } else {
                  _projects = [];
                }
              }
              _isLoading = false;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load projects: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredProjects {
    if (_searchQuery.isEmpty) {
      return _projects;
    }
    return _projects.where((project) {
      final name = (project['name'] ?? '').toString().toLowerCase();
      final description = (project['description'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || description.contains(query);
    }).toList();
  }


  Map<String, int> get _projectStats {
    int running = 0;
    int completed = 0;
    int failed = 0;

    for (var project in _projects) {
      final status = (project['status'] ?? '').toString().toUpperCase();
      if (status == 'RUNNING') {
        running++;
      } else if (status == 'COMPLETED') {
        completed++;
      } else if (status == 'FAILED') {
        failed++;
      }
    }

    return {
      'total': _projects.length,
      'running': running,
      'completed': completed,
      'failed': failed,
    };
  }

  @override
  Widget build(BuildContext context) {
    final stats = _projectStats;
    final filteredProjects = _filteredProjects;

    // Show Projects content (header is now in MainNavigationScreen)
    return Material(
      color: Colors.transparent,
      child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'RTL2GDS Projects',
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Manage and monitor your chip design projects',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),

                          // Summary Cards
                          _buildSummaryCards(stats),
                          const SizedBox(height: 32),

                          // Search Bar
                          SizedBox(
                            width: double.infinity,
                            child: _buildSearchBar(),
                          ),
                          const SizedBox(height: 32),

                          // Projects Grid
                          _buildProjectsGrid(filteredProjects),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildSummaryCards(Map<String, int> stats) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        
        if (isMobile) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: _buildStatCard('Total Projects', stats['total']!.toString(), Theme.of(context).colorScheme.onSurface)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard('Running', stats['running']!.toString(), Theme.of(context).colorScheme.secondary)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildStatCard('Completed', stats['completed']!.toString(), const Color(0xFF10B981))),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard('Failed', stats['failed']!.toString(), const Color(0xFFEF4444))),
                ],
              ),
            ],
          );
        }
        
        return Row(
          children: [
            Expanded(
              child: _buildStatCard('Total Projects', stats['total']!.toString(), Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard('Running', stats['running']!.toString(), Theme.of(context).colorScheme.secondary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard('Completed', stats['completed']!.toString(), const Color(0xFF10B981)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard('Failed', stats['failed']!.toString(), const Color(0xFFEF4444)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final searchWidth = maxWidth > 600 ? 384.0 : double.infinity;
        
        return Container(
          width: searchWidth,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: TextField(
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: 'Search projects...',
              hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
              prefixIcon: Icon(
                Icons.search, 
                size: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProjectsGrid(List<Map<String, dynamic>> projects) {
    if (projects.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48.0),
          child: Text(
            _searchQuery.isEmpty ? 'No projects found' : 'No projects found matching your search.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 3;
        if (constraints.maxWidth < 600) {
          crossAxisCount = 1;
        } else if (constraints.maxWidth < 1024) {
          crossAxisCount = 2;
        }
        
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.35,
          ),
          itemCount: projects.length,
          itemBuilder: (context, index) {
            return _buildProjectCard(projects[index]);
          },
        );
      },
    );
  }

  String _getProjectStatus(Map<String, dynamic> project) {
    final status = (project['status'] ?? '').toString().toUpperCase();
    if (status == 'RUNNING' || status == 'IN_PROGRESS') {
      return 'RUNNING';
    } else if (status == 'COMPLETED' || status == 'COMPLETE') {
      return 'COMPLETED';
    } else if (status == 'FAILED' || status == 'ERROR') {
      return 'FAILED';
    }
    return 'IDLE';
  }


  String _formatTimeAgo(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inMinutes < 1) {
        return 'just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
      } else if (difference.inDays < 30) {
        return 'about ${(difference.inDays / 7).floor()} week${(difference.inDays / 7).floor() > 1 ? 's' : ''} ago';
      } else if (difference.inDays < 365) {
        return 'about ${(difference.inDays / 30).floor()} month${(difference.inDays / 30).floor() > 1 ? 's' : ''} ago';
      } else {
        return 'about ${(difference.inDays / 365).floor()} year${(difference.inDays / 365).floor() > 1 ? 's' : ''} ago';
      }
    } catch (e) {
      return dateString;
    }
  }

  String _stripHtmlTags(String? htmlString) {
    if (htmlString == null || htmlString.isEmpty) return '';
    // Remove HTML tags using regex
    return htmlString
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'&nbsp;'), ' ')
        .replaceAll(RegExp(r'&amp;'), '&')
        .replaceAll(RegExp(r'&lt;'), '<')
        .replaceAll(RegExp(r'&gt;'), '>')
        .replaceAll(RegExp(r'&quot;'), '"')
        .trim();
  }

  Widget _buildProjectCard(Map<String, dynamic> project) {
    final status = _getProjectStatus(project);
    final statusConfig = _getStatusConfig(status);
    final projectName = project['name'] ?? 'Unnamed Project';
    final rawDescription = project['description'] ?? project['client'] ?? 'Hardware design project';
    final description = _stripHtmlTags(rawDescription.toString());
    final gateCount = project['gate_count'] ?? project['gateCount'] ?? 'N/A';
    final technology = project['technology'] ?? project['technology_node'] ?? 'Sky130 PDK';
    final lastRun = _formatTimeAgo(project['last_run']?.toString() ?? project['updated_at']?.toString());
    final progressValue = project['progress'];
    final progress = progressValue != null 
        ? (progressValue is num ? progressValue.toDouble() : double.tryParse(progressValue.toString()) ?? 0.0)
        : (status == 'RUNNING' ? 65.0 : 0.0);
    final isRunning = status == 'RUNNING';

    void handleProjectClick() {
      final userRole = ref.read(authProvider).user?['role'];
      final projectName = project['name']?.toString();
      
      // For customers, navigate directly to ViewScreen with customer view
      if (userRole == 'customer' && projectName != null) {
        // Set view screen parameters
        ref.read(viewScreenParamsProvider.notifier).state = ViewScreenParams(
          project: projectName,
          viewType: 'customer',
        );
        
        // Navigate to ViewScreen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ViewScreen(),
          ),
        );
      } else {
        // For other roles, open project in a tab (SemiconDashboardScreen)
        ref.read(tabProvider.notifier).openProject(project);
        // Switch to show the project tab
        ref.read(currentNavTabProvider.notifier).state = 'project_tab';
      }
    }

    final userRole = ref.read(authProvider).user?['role'];
    final globalCanExportToLinux = userRole == 'cad_engineer' || userRole == 'admin';
    final isEngineer = userRole == 'engineer' || userRole == 'admin';
    
    // Check project-specific CAD engineer role
    return FutureBuilder<Map<String, dynamic>>(
      future: _checkProjectCadRole(projectName),
      builder: (context, snapshot) {
        // Check if user is CAD engineer for this project (global or project-specific)
        final isCadEngineerForProject = globalCanExportToLinux || 
            (snapshot.hasData && snapshot.data!['effectiveRole'] == 'cad_engineer');
        
        // Check if user is engineer for this project (global or project-specific)
        // Exclude CAD engineers - Setup button is only for regular engineers
        final effectiveRole = snapshot.hasData ? snapshot.data!['effectiveRole'] : userRole;
        final isEngineerForProject = (isEngineer || effectiveRole == 'engineer') && 
            !isCadEngineerForProject && effectiveRole != 'cad_engineer';
        
        final isExported = _exportedProjects.contains(projectName);
        
        return _ProjectCardWidget(
          project: project,
          status: status,
          statusConfig: statusConfig,
          projectName: projectName,
          description: description.isEmpty ? 'Hardware design project' : description,
          gateCount: gateCount.toString(),
          technology: technology,
          lastRun: lastRun,
          progress: progress,
          isRunning: isRunning,
          onTap: handleProjectClick,
          canExportToLinux: isCadEngineerForProject,
          isExported: isExported,
          onExportToLinux: isCadEngineerForProject
              ? () {
                  _showExportToLinuxDialog(context, project);
                }
              : null,
          canSetup: isEngineerForProject,
          onSetup: isEngineerForProject
              ? () {
                  _showSetupDialog(context, project);
                }
              : null,
        );
      },
    );
  }

  Map<String, dynamic> _getStatusConfig(String status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (status) {
      case 'IDLE':
        return {
          'color': isDark ? Colors.grey.shade700 : Colors.grey.shade300,
          'icon': Icons.access_time,
          'textColor': Colors.white,
        };
      case 'RUNNING':
        return {
          'color': Theme.of(context).colorScheme.secondary, // info color
          'icon': Icons.play_circle,
          'textColor': Colors.white,
        };
      case 'COMPLETED':
        return {
          'color': const Color(0xFF10B981), // success green
          'icon': Icons.check_circle,
          'textColor': Colors.white,
        };
      case 'FAILED':
        return {
          'color': const Color(0xFFEF4444), // danger red
          'icon': Icons.cancel,
          'textColor': Colors.white,
        };
      default:
        return {
          'color': isDark ? Colors.grey.shade700 : Colors.grey.shade300,
          'icon': Icons.access_time,
          'textColor': Colors.white,
        };
    }
  }

  void _showExportToLinuxDialog(BuildContext context, Map<String, dynamic> project) async {
    final projectName = project['name'] ?? 'Unnamed Project';
    
    // Show loading dialog while fetching domains from project plan
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final token = ref.read(authProvider).token;
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
      
      List<Map<String, dynamic>> domains = [];
      
      // Try to fetch domains from Zoho tasks (project plan)
      if (actualProjectId.isNotEmpty) {
        try {
          // Get portal ID from zoho_data if available
          final zohoData = project['zoho_data'] as Map<String, dynamic>?;
          final portalId = zohoData?['portal_id']?.toString() ?? 
                          zohoData?['portal']?.toString();
          
          final tasksResponse = await _apiService.getZohoTasks(
            projectId: actualProjectId,
            token: token,
            portalId: portalId,
          );
          
          final tasks = tasksResponse['tasks'] ?? [];
          
          // Extract unique domains from tasklist_name
          final domainMap = <String, Map<String, dynamic>>{};
          
          for (final task in tasks) {
            final tasklistName = (task['tasklist_name'] ?? task['tasklistName'] ?? '').toString();
            
            if (tasklistName.isNotEmpty && !domainMap.containsKey(tasklistName)) {
              final tasklistNameLower = tasklistName.toLowerCase();
              
              // Determine domain code from tasklist name
              String domainCode;
              if (tasklistNameLower.contains('pd') || 
                  tasklistNameLower.contains('physical') || 
                  tasklistNameLower.contains('physical design')) {
                domainCode = 'pd';
              } else if (tasklistNameLower.contains('dv') || 
                        tasklistNameLower.contains('design verification') ||
                        tasklistNameLower.contains('verification')) {
                domainCode = 'dv';
              } else if (tasklistNameLower.contains('rtl')) {
                domainCode = 'rtl';
              } else if (tasklistNameLower.contains('dft')) {
                domainCode = 'dft';
              } else if (tasklistNameLower.contains('al')) {
                domainCode = 'al';
              } else {
                // Use first few characters of tasklist name as code
                domainCode = tasklistName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').substring(0, tasklistName.length > 3 ? 3 : tasklistName.length);
              }
              
              domainMap[tasklistName] = {
                'name': tasklistName, // Use actual tasklist name as domain name
                'code': domainCode,
              };
            }
          }
          
          domains = domainMap.values.toList();
        } catch (e) {
          print('Error fetching domains from Zoho tasks: $e');
          // Fallback to project domains if Zoho fetch fails
        }
      }
      
      // Fallback to project domains if no domains found from Zoho
      if (domains.isEmpty) {
        domains = (project['domains'] as List<dynamic>? ?? [])
            .where((d) => d != null && d is Map<String, dynamic>)
            .map((d) => d as Map<String, dynamic>)
            .toList();
      }
      
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        
        showDialog(
          context: context,
          builder: (context) => _ExportToLinuxDialog(
            projectName: projectName,
            domains: domains,
            apiService: _apiService,
            onExportSuccess: (projectName) {
              setState(() {
                _exportedProjects.add(projectName);
              });
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading domains: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showSetupDialog(BuildContext context, Map<String, dynamic> project) async {
    final projectName = project['name'] ?? 'Unnamed Project';
    
    // Show loading dialog while fetching domains and blocks from project plan
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final token = ref.read(authProvider).token;
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
      
      // Get portal ID from zoho_data if available
      final zohoData = project['zoho_data'] as Map<String, dynamic>?;
      final portalId = zohoData?['portal_id']?.toString() ?? 
                      zohoData?['portal']?.toString();
      
      // Get current user info
      final currentUser = ref.read(authProvider).user;
      final currentUserEmail = currentUser?['email']?.toString() ?? '';
      
      // Fetch tasks from Zoho to get domains and blocks
      List<Map<String, dynamic>> userDomains = [];
      Map<String, List<Map<String, dynamic>>> domainBlocksMap = {};
      
      if (actualProjectId.isNotEmpty) {
        try {
          final tasksResponse = await _apiService.getZohoTasks(
            projectId: actualProjectId,
            token: token,
            portalId: portalId,
          );
          
          final tasks = tasksResponse['tasks'] ?? [];
          
          // Extract domains (tasklists) and blocks (tasks) assigned to current user
          final domainMap = <String, Map<String, dynamic>>{};
          final blocksByDomain = <String, List<Map<String, dynamic>>>{};
          
          for (final task in tasks) {
            final tasklistName = (task['tasklist_name'] ?? task['tasklistName'] ?? '').toString();
            final taskName = (task['name'] ?? task['task_name'] ?? '').toString();
            
            // Get task owner information
            String? ownerEmail = task['owner_email']?.toString() ?? 
                               task['owner']?['email']?.toString() ??
                               task['details']?['owners']?[0]?['email']?.toString();
            
            // Check if current user is assigned to this task (owner or in owners list)
            bool isAssignedToUser = false;
            if (ownerEmail != null && ownerEmail.toLowerCase() == currentUserEmail.toLowerCase()) {
              isAssignedToUser = true;
            } else if (task['details'] != null && task['details'] is Map) {
              final details = task['details'] as Map;
              if (details['owners'] != null && details['owners'] is List) {
                for (final owner in details['owners'] as List) {
                  final email = owner['email']?.toString() ?? '';
                  if (email.toLowerCase() == currentUserEmail.toLowerCase()) {
                    isAssignedToUser = true;
                    break;
                  }
                }
              }
            }
            
            // Only include tasks/domains assigned to the current user
            if (isAssignedToUser && tasklistName.isNotEmpty && taskName.isNotEmpty) {
              // Add domain if not already added
              if (!domainMap.containsKey(tasklistName)) {
                final tasklistNameLower = tasklistName.toLowerCase();
                
                // Determine domain code from tasklist name
                String domainCode;
                if (tasklistNameLower.contains('pd') || 
                    tasklistNameLower.contains('physical') || 
                    tasklistNameLower.contains('physical design')) {
                  domainCode = 'pd';
                } else if (tasklistNameLower.contains('dv') || 
                          tasklistNameLower.contains('design verification') ||
                          tasklistNameLower.contains('verification')) {
                  domainCode = 'dv';
                } else if (tasklistNameLower.contains('rtl')) {
                  domainCode = 'rtl';
                } else if (tasklistNameLower.contains('dft')) {
                  domainCode = 'dft';
                } else if (tasklistNameLower.contains('al')) {
                  domainCode = 'al';
                } else {
                  // Use first few characters of tasklist name as code
                  domainCode = tasklistName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').substring(0, tasklistName.length > 3 ? 3 : tasklistName.length);
                }
                
                domainMap[tasklistName] = {
                  'name': tasklistName,
                  'code': domainCode,
                };
                blocksByDomain[tasklistName] = [];
              }
              
              // Add block (task) to the domain
              if (blocksByDomain.containsKey(tasklistName)) {
                blocksByDomain[tasklistName]!.add({
                  'name': taskName,
                  'id': task['id']?.toString() ?? task['task_id']?.toString() ?? '',
                });
              }
            }
          }
          
          userDomains = domainMap.values.toList();
          domainBlocksMap = blocksByDomain;
        } catch (e) {
          print('Error fetching domains and blocks from Zoho tasks: $e');
          // Fallback to project domains if Zoho fetch fails
          userDomains = (project['domains'] as List<dynamic>? ?? [])
              .where((d) => d != null && d is Map<String, dynamic>)
              .map((d) => d as Map<String, dynamic>)
              .toList();
        }
      }
      
      // Fallback to project domains if no domains found from Zoho
      if (userDomains.isEmpty) {
        userDomains = (project['domains'] as List<dynamic>? ?? [])
            .where((d) => d != null && d is Map<String, dynamic>)
            .map((d) => d as Map<String, dynamic>)
            .toList();
      }
      
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        
        showDialog(
          context: context,
          builder: (context) => _SetupDialog(
            projectName: projectName,
            domains: userDomains,
            domainBlocksMap: domainBlocksMap,
            apiService: _apiService,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading setup data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _ProjectCardWidget extends StatefulWidget {
  final Map<String, dynamic> project;
  final String status;
  final Map<String, dynamic> statusConfig;
  final String projectName;
  final String description;
  final String gateCount;
  final String technology;
  final String lastRun;
  final double progress;
  final bool isRunning;
  final VoidCallback onTap;
  final bool canExportToLinux;
  final bool isExported;
  final VoidCallback? onExportToLinux;
  final bool canSetup;
  final VoidCallback? onSetup;

  const _ProjectCardWidget({
    required this.project,
    required this.status,
    required this.statusConfig,
    required this.projectName,
    required this.description,
    required this.gateCount,
    required this.technology,
    required this.lastRun,
    required this.progress,
    required this.isRunning,
    required this.onTap,
    this.canExportToLinux = false,
    this.isExported = false,
    this.onExportToLinux,
    this.canSetup = false,
    this.onSetup,
  });

  @override
  State<_ProjectCardWidget> createState() => _ProjectCardWidgetState();
}

class _ProjectCardWidgetState extends State<_ProjectCardWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovered 
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.5)
                  : Theme.of(context).dividerColor, 
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with Icon and Status Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon with gradient background
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.secondary,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.memory,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  // Status Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: widget.statusConfig['color'] as Color,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.statusConfig['icon'] as IconData,
                          size: 12,
                          color: widget.statusConfig['textColor'] as Color? ?? Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.status,
                          style: TextStyle(
                            color: widget.statusConfig['textColor'] as Color? ?? Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Project Name
              Text(
                widget.projectName,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              
              // Description
              Text(
                widget.description,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),
              
              // Details Grid - Gate Count and Technology
              Row(
                children: [
                  if (widget.gateCount != 'N/A')
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gate Count',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.gateCount,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Technology',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.technology,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Last Run
              Text(
                'Last run: ${widget.lastRun}',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              
              const Spacer(),
              
              // Progress Bar (if running)
              if (widget.isRunning) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Progress',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    Text(
                      '${widget.progress.toInt()}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (widget.progress / 100).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: widget.statusConfig['color'] as Color,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              
              // Divider
              Divider(
                color: Theme.of(context).dividerColor,
                height: 1,
              ),
              const SizedBox(height: 12),
              
              // Footer actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Click to open',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  Row(
                    children: [
                      if (widget.canSetup)
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: OutlinedButton.icon(
                            onPressed: widget.onSetup,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              side: BorderSide(color: Theme.of(context).colorScheme.secondary),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.settings, size: 16),
                            label: const Text(
                              'Setup',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      if (widget.canExportToLinux)
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: widget.isExported
                              ? ElevatedButton.icon(
                                  onPressed: null, // Disabled when already exported
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: Colors.green.shade700,
                                    disabledForegroundColor: Colors.white,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  icon: const Icon(Icons.check_circle, size: 16),
                                  label: const Text(
                                    'Exported',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                )
                              : OutlinedButton.icon(
                                  onPressed: widget.onExportToLinux,
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    side: BorderSide(color: Theme.of(context).colorScheme.primary),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  icon: const Icon(Icons.file_download, size: 16),
                                  label: const Text(
                                    'Export to Linux',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                        ),
                      Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExportToLinuxDialog extends ConsumerStatefulWidget {
  final String projectName;
  final List<Map<String, dynamic>> domains;
  final ApiService apiService;
  final Function(String)? onExportSuccess;

  const _ExportToLinuxDialog({
    required this.projectName,
    required this.domains,
    required this.apiService,
    this.onExportSuccess,
  });

  @override
  ConsumerState<_ExportToLinuxDialog> createState() => _ExportToLinuxDialogState();
}

class _ExportToLinuxDialogState extends ConsumerState<_ExportToLinuxDialog> {
  final Set<String> _selectedDomainCodes = {};
  bool _isRunning = false;
  String? _output;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Select all domains by default
    for (var domain in widget.domains) {
      final code = domain['code']?.toString();
      if (code != null && code.isNotEmpty) {
        _selectedDomainCodes.add(code);
      }
    }
  }

  /// Map Zoho domain codes to command domain values
  /// Example: "dv" from Zoho maps to "verification" in the command
  String _mapDomainCodeToCommand(String zohoCode) {
    // Convert to lowercase for case-insensitive matching
    final code = zohoCode.toLowerCase().trim();
    
    // Domain code mapping: Zoho code -> Command value
    switch (code) {
      case 'dv':
        return 'verification';
      case 'pd':
        return 'pd'; // Keep as-is or map to 'physical' if needed
      case 'rtl':
        return 'rtl'; // Keep as-is
      case 'dft':
        return 'dft'; // Keep as-is
      case 'al':
        return 'al'; // Keep as-is
      default:
        // For unknown codes, use as-is
        return zohoCode;
    }
  }

  Future<void> _runCommand() async {
    if (_selectedDomainCodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one domain'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isRunning = true;
      _output = null;
      _error = null;
    });

    try {
      final token = ref.read(authProvider).token;
      if (token == null) {
        throw Exception('No authentication token');
      }

      // Map Zoho domain codes to command domain values
      final mappedDomainCodes = _selectedDomainCodes.map((code) {
        return _mapDomainCodeToCommand(code);
      }).toList();
      
      // Build domain codes string (comma-separated) with mapped values
      final domainCodesStr = mappedDomainCodes.join(',');
      
      // Build the command with sudo python3 using full path
      // Project name: replace spaces with underscores (e.g., "mohan r4" -> "mohan_r4")
      // Project group: hardcoded as "projectk"
      final projectNameSanitized = widget.projectName.replaceAll(' ', '_');
      final command = 'sudo python3 /CX_CAD/REL/env_scripts/infra/latest/createDir.py --base-path /CX_PROJ --proj $projectNameSanitized --dom $domainCodesStr --project-group projectk --scratch-base-path /CX_RUN_NEW';

      // Print command to console
      print('═══════════════════════════════════════════════════════════');
      print('🚀 EXECUTING SSH COMMAND:');
      print('   Command: $command');
      print('   Project: ${widget.projectName}');
      print('   Zoho Domains: ${_selectedDomainCodes.join(', ')}');
      print('   Mapped Domains: $domainCodesStr');
      print('═══════════════════════════════════════════════════════════');

      // Execute via SSH
      final result = await widget.apiService.executeSSHCommand(
        command: command,
        token: token,
      );
      
      // Print result to console
      print('═══════════════════════════════════════════════════════════');
      print('📤 SSH COMMAND RESULT:');
      print('   Success: ${result['success']}');
      print('   Exit Code: ${result['exitCode']}');
      if (result['stdout'] != null) {
        print('   Stdout: ${result['stdout']}');
      }
      if (result['stderr'] != null) {
        print('   Stderr: ${result['stderr']}');
      }
      if (result['requiresPassword'] == true) {
        print('   ⚠️ Password Required!');
      }
      print('═══════════════════════════════════════════════════════════');

      setState(() {
        _isRunning = false;
        if (result['success'] == true) {
          _output = result['stdout']?.toString() ?? 'Command executed successfully';
          if (result['stderr'] != null && result['stderr'].toString().isNotEmpty) {
            _output = '${_output}\n\nStderr: ${result['stderr']}';
          }
        } else {
          _error = result['error']?.toString() ?? 'Command execution failed';
        }
      });

      // Check if password is required - also check exit code and output
      final requiresPassword = result['requiresPassword'] == true || 
          (result['exitCode'] == 1 && 
           (result['stdout']?.toString().contains('password') == true ||
            result['stderr']?.toString().contains('password') == true));
      
      if (mounted && requiresPassword) {
        final output = (result['stdout']?.toString() ?? '') + 
                      (result['stderr']?.toString() ?? '');
        _showPasswordRequiredDialog(context, command, output);
      } else if (mounted && result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Command executed successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isRunning = false;
        _error = e.toString();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showPasswordRequiredDialog(BuildContext context, String command, String output) async {
    final passwordController = TextEditingController();
    bool isSendingPassword = false;
    bool showOutput = false;
    String liveOutput = output;
    bool isCommandRunning = false;
    int? lastExitCode;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: 700,
            constraints: const BoxConstraints(maxHeight: 700),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange.shade400, Colors.orange.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.lock, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          'Password Required',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Scrollable content
                Expanded(
                  child: showOutput
                      ? _buildLiveOutputView(
                          liveOutput, 
                          setDialogState,
                          isComplete: !isCommandRunning,
                          exitCode: isCommandRunning ? null : lastExitCode,
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Info message
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.blue.shade200),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 24),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'The command requires sudo password to continue execution.',
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: Colors.blue.shade900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              // Command display
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E1E),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade700),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.code, color: Colors.blue.shade300, size: 20),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Command to Execute:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey.shade300,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    SelectableText(
                                      command,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        color: Color(0xFFD4D4D4),
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              // Password input with better styling
                              TextField(
                                controller: passwordController,
                                obscureText: true,
                                autofocus: true,
                                decoration: InputDecoration(
                                  labelText: 'Enter Sudo Password',
                                  hintText: 'Enter your password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.grey.shade400),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.orange.shade600, width: 2),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                ),
                                enabled: !isSendingPassword,
                                onSubmitted: (value) async {
                                  if (value.isNotEmpty && !isSendingPassword) {
                                    setDialogState(() {
                                      isSendingPassword = true;
                                    });
                                    await _sendPasswordAndShowOutput(
                                      context, 
                                      value, 
                                      command,
                                      setDialogState,
                                      (newOutput) {
                                        setDialogState(() {
                                          liveOutput = newOutput;
                                        });
                                      },
                                      () {
                                        setDialogState(() {
                                          showOutput = true;
                                          isCommandRunning = true;
                                          isSendingPassword = false;
                                        });
                                      },
                                      (exitCode) {
                                        setDialogState(() {
                                          lastExitCode = exitCode;
                                        });
                                      },
                                      () {
                                        setDialogState(() {
                                          isCommandRunning = false;
                                        });
                                      },
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                ),
                // Actions
                if (!showOutput)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isSendingPassword ? null : () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: isSendingPassword || passwordController.text.isEmpty
                              ? null
                              : () async {
                                  setDialogState(() {
                                    isSendingPassword = true;
                                  });
                                  await _sendPasswordAndShowOutput(
                                    context, 
                                    passwordController.text, 
                                    command,
                                    setDialogState,
                                    (newOutput) {
                                      setDialogState(() {
                                        liveOutput = newOutput;
                                      });
                                    },
                                    () {
                                      setDialogState(() {
                                        showOutput = true;
                                        isCommandRunning = true;
                                        isSendingPassword = false;
                                      });
                                    },
                                    (exitCode) {
                                      setDialogState(() {
                                        lastExitCode = exitCode;
                                      });
                                    },
                                    () {
                                      setDialogState(() {
                                        isCommandRunning = false;
                                      });
                                    },
                                  );
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: isSendingPassword
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(Icons.send, size: 18),
                          label: Text(isSendingPassword ? 'Sending...' : 'Send Password'),
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

  Widget _buildLiveOutputView(String output, StateSetter setDialogState, {bool isComplete = false, int? exitCode}) {
    final scrollController = ScrollController();
    
    // Clean up output - remove shell prompts and command echo
    String cleanOutput = _cleanCommandOutput(output);
    
    // Determine status
    bool isSuccess = isComplete && exitCode == 0;
    
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status header with better design
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isComplete 
                ? (isSuccess ? Colors.green.shade50 : Colors.red.shade50)
                : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isComplete 
                  ? (isSuccess ? Colors.green.shade200 : Colors.red.shade200)
                  : Colors.blue.shade200,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isComplete 
                      ? (isSuccess ? Colors.green.shade100 : Colors.red.shade100)
                      : Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isComplete 
                      ? (isSuccess ? Icons.check_circle : Icons.error)
                      : Icons.sync,
                    color: isComplete 
                      ? (isSuccess ? Colors.green.shade700 : Colors.red.shade700)
                      : Colors.blue.shade700,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isComplete 
                          ? (isSuccess ? 'Export Completed Successfully' : 'Export Failed')
                          : 'Exporting to Linux...',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isComplete 
                            ? (isSuccess ? Colors.green.shade900 : Colors.red.shade900)
                            : Colors.blue.shade900,
                        ),
                      ),
                      if (!isComplete)
                        const SizedBox(height: 4),
                      if (!isComplete)
                        Text(
                          'Please wait while the project is being exported...',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue.shade700,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!isComplete)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                if (isComplete && exitCode != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSuccess ? Colors.green.shade200 : Colors.red.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Exit: $exitCode',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isSuccess ? Colors.green.shade900 : Colors.red.shade900,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Output console with better styling
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E), // Darker, more terminal-like
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isComplete 
                    ? (isSuccess ? Colors.green.shade400 : Colors.red.shade400)
                    : Colors.grey.shade600,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Console header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(10),
                        topRight: Radius.circular(10),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Command Output',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        if (isComplete)
                          Icon(
                            isSuccess ? Icons.check_circle : Icons.error,
                            color: isSuccess ? Colors.green.shade400 : Colors.red.shade400,
                            size: 18,
                          ),
                      ],
                    ),
                  ),
                  // Output content
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      child: cleanOutput.isEmpty 
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Waiting for command output...',
                                  style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
                            controller: scrollController,
                            child: SelectableText(
                              cleanOutput,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                color: Color(0xFFD4D4D4), // Better contrast
                                height: 1.5,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _cleanCommandOutput(String output) {
    if (output.isEmpty) return '';
    
    // Split into lines
    List<String> lines = output.split('\n');
    List<String> cleanedLines = [];
    
    // Patterns to remove
    final promptPattern = RegExp(r'^[\w@\-]+[:\/][\w\/~]+[#$>]\s*$');
    final lastLoginPattern = RegExp(r'^Last login:');
    final commandEchoPattern = RegExp(r'^sudo python3');
    final passwordPromptPattern = RegExp(r'\[sudo\] password for');
    final passwordSentPattern = RegExp(r'Password prompt detected');
    
    bool skipNextEmpty = false;
    
    for (int i = 0; i < lines.length; i++) {
      String line = lines[i].trim();
      
      // Skip empty lines after prompts
      if (skipNextEmpty && line.isEmpty) {
        skipNextEmpty = false;
        continue;
      }
      skipNextEmpty = false;
      
      // Skip shell prompts
      if (promptPattern.hasMatch(line)) {
        skipNextEmpty = true;
        continue;
      }
      
      // Skip "Last login" messages
      if (lastLoginPattern.hasMatch(line)) {
        continue;
      }
      
      // Skip command echo (but keep the actual output)
      if (commandEchoPattern.hasMatch(line) && line.length > 50) {
        // This is the command being echoed, skip it
        continue;
      }
      
      // Skip password prompts
      if (passwordPromptPattern.hasMatch(line)) {
        continue;
      }
      
      // Skip password sent messages
      if (passwordSentPattern.hasMatch(line)) {
        continue;
      }
      
      // Skip "DISPLAY: Undefined variable" warnings (common and not important)
      if (line.contains('DISPLAY: Undefined variable')) {
        continue;
      }
      
      // Keep the line if it's not empty or if it's meaningful
      if (line.isNotEmpty || cleanedLines.isEmpty || cleanedLines.last.isNotEmpty) {
        cleanedLines.add(line);
      }
    }
    
    // Join lines and clean up multiple empty lines
    String result = cleanedLines.join('\n');
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n'); // Max 2 consecutive newlines
    result = result.trim();
    
    return result;
  }

  Future<void> _sendPasswordAndShowOutput(
    BuildContext context, 
    String password, 
    String command,
    StateSetter setDialogState,
    Function(String) updateOutput,
    VoidCallback showOutputView,
    Function(int?) setExitCode,
    VoidCallback commandComplete,
  ) async {
    try {
      final token = ref.read(authProvider).token;
      if (token == null) {
        throw Exception('No authentication token');
      }

      // Send password
      await widget.apiService.sendSSHPassword(
        password: password,
        token: token,
      );

      // Show output view
      showOutputView();

      // Wait a moment for password to be processed
      await Future.delayed(const Duration(milliseconds: 500));

      // Re-execute the command to get the full output (password is already sent)
      // The command should complete this time
      try {
        final result = await widget.apiService.executeSSHCommand(
          command: command,
          token: token,
        );

        // Update output with final result
        String finalOutput = '';
        if (result['stdout'] != null) {
          finalOutput += result['stdout'].toString();
        }
        if (result['stderr'] != null && result['stderr'].toString().isNotEmpty) {
          if (finalOutput.isNotEmpty) finalOutput += '\n';
          finalOutput += result['stderr'].toString();
        }

        // Store exit code
        final exitCode = result['exitCode'] as int?;
        
        updateOutput(finalOutput);
        setExitCode(exitCode);
        commandComplete();

        // Only close dialog when command completes successfully (exit code 0)
        // Do NOT close on password send or command start - only on successful completion
        final isSuccess = result['success'] == true && exitCode == 0;
        
        if (isSuccess) {
          // Notify parent that export was successful
          if (widget.onExportSuccess != null) {
            widget.onExportSuccess!(widget.projectName);
          }
          
          // Show success message
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Export completed successfully!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
          
          // Close dialog ONLY after successful command completion
          // Wait a brief moment to show the success state, then close
          await Future.delayed(const Duration(milliseconds: 500));
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        } else {
          // Show error message but keep dialog open so user can see the error
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Command failed with exit code: ${exitCode ?? 'unknown'}'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } catch (e) {
        updateOutput('Error executing command: $e');
        commandComplete();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      commandComplete();
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending password: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendPassword(
    BuildContext context, 
    String password, 
    StateSetter setDialogState,
    VoidCallback setSending,
    VoidCallback setNotSending,
  ) async {
    try {
      final token = ref.read(authProvider).token;
      if (token == null) {
        throw Exception('No authentication token');
      }

      await widget.apiService.sendSSHPassword(
        password: password,
        token: token,
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password sent. Waiting for command to complete...'),
            backgroundColor: Colors.blue,
          ),
        );
        
        // Wait a bit and check command status again
        await Future.delayed(const Duration(seconds: 2));
        // Re-run the command check or wait for completion
      }
    } catch (e) {
      setNotSending();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending password: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
        width: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Export to Linux',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _isRunning ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Project Name (read-only)
            TextField(
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Project Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              controller: TextEditingController(text: widget.projectName),
            ),
            const SizedBox(height: 20),

            // Domain Selection
            Text(
              'Select Domains',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            
            if (widget.domains.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'No domains available for this project',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.domains.length,
                  itemBuilder: (context, index) {
                    final domain = widget.domains[index];
                    final code = domain['code']?.toString() ?? '';
                    final name = domain['name']?.toString() ?? code;
                    final isSelected = _selectedDomainCodes.contains(code);

                    return CheckboxListTile(
                      title: Text(name),
                      subtitle: code.isNotEmpty && code != name.toLowerCase() 
                          ? Text('Code: $code') 
                          : null,
                      value: isSelected,
                      onChanged: _isRunning
                          ? null
                          : (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedDomainCodes.add(code);
                                } else {
                                  _selectedDomainCodes.remove(code);
                                }
                              });
                            },
                    );
                  },
                ),
              ),
            const SizedBox(height: 24),

            // Output/Error Display
            if (_output != null || _error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _error != null
                      ? Colors.red.shade50
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _error != null
                        ? Colors.red.shade300
                        : Colors.green.shade300,
                  ),
                ),
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(
                    _error ?? _output ?? '',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: _error != null
                          ? Colors.red.shade900
                          : Colors.green.shade900,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isRunning ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isRunning ? null : _runCommand,
                  icon: _isRunning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_isRunning ? 'Running...' : 'Run'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupDialog extends ConsumerStatefulWidget {
  final String projectName;
  final List<Map<String, dynamic>> domains;
  final Map<String, List<Map<String, dynamic>>> domainBlocksMap;
  final ApiService apiService;

  const _SetupDialog({
    required this.projectName,
    required this.domains,
    required this.domainBlocksMap,
    required this.apiService,
  });

  @override
  ConsumerState<_SetupDialog> createState() => _SetupDialogState();
}

class _SetupDialogState extends ConsumerState<_SetupDialog> {
  String? _selectedDomainCode;
  String? _selectedBlock;
  final TextEditingController _experimentController = TextEditingController();
  bool _isRunning = false;
  bool _isSuccess = false;
  String? _output;
  String? _error;

  @override
  void dispose() {
    _experimentController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _availableBlocks {
    if (_selectedDomainCode == null) return [];
    
    // Find the domain name that matches the selected domain code
    final selectedDomain = widget.domains.firstWhere(
      (d) => d['code']?.toString() == _selectedDomainCode,
      orElse: () => {},
    );
    
    final domainName = selectedDomain['name']?.toString() ?? '';
    
    if (domainName.isEmpty) return [];
    
    // Get blocks for this domain
    return widget.domainBlocksMap[domainName] ?? [];
  }

  Future<void> _runSetup() async {
    if (_selectedDomainCode == null || _selectedBlock == null || _experimentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isRunning = true;
      _output = null;
      _error = null;
    });

    try {
      final token = ref.read(authProvider).token;
      if (token == null) {
        throw Exception('No authentication token');
      }

      // Build the command: setup -proj {project} -domain {domain} -block {block} -exp {experiment}
      // Replace spaces with underscores in project name and block name (e.g., "mohan r4" -> "mohan_r4")
      final projectName = widget.projectName;
      final sanitizedProjectName = projectName.replaceAll(' ', '_');
      final domainCode = _selectedDomainCode!;
      final blockName = _selectedBlock!;
      final sanitizedBlockName = blockName.replaceAll(' ', '_');
      final experimentName = _experimentController.text.trim();

      // Build command with sanitized names (spaces replaced with underscores)
      final command = 'setup -proj $sanitizedProjectName -domain $domainCode -block $sanitizedBlockName -exp $experimentName';

      print('═══════════════════════════════════════════════════════════');
      print('🚀 EXECUTING SETUP COMMAND:');
      print('   Command: $command');
      print('   Project (original): $projectName');
      print('   Project (sanitized): $sanitizedProjectName');
      print('   Domain: $domainCode');
      print('   Block (original): $blockName');
      print('   Block (sanitized): $sanitizedBlockName');
      print('   Experiment: $experimentName');
      print('═══════════════════════════════════════════════════════════');

      // Execute via SSH
      final result = await widget.apiService.executeSSHCommand(
        command: command,
        token: token,
      );
      
      print('═══════════════════════════════════════════════════════════');
      print('📤 SETUP COMMAND RESULT:');
      print('   Success: ${result['success']}');
      print('   Exit Code: ${result['exitCode']}');
      if (result['stdout'] != null) {
        print('   Stdout: ${result['stdout']}');
      }
      if (result['stderr'] != null) {
        print('   Stderr: ${result['stderr']}');
      }
      print('═══════════════════════════════════════════════════════════');

      final isSuccess = result['success'] == true && (result['exitCode'] == 0 || result['exitCode'] == null);
      
      setState(() {
        _isRunning = false;
        _isSuccess = isSuccess;
        if (isSuccess) {
          _output = result['stdout']?.toString() ?? 'Setup command executed successfully';
          if (result['stderr'] != null && result['stderr'].toString().isNotEmpty) {
            _output = '${_output}\n\nStderr: ${result['stderr']}';
          }
        } else {
          _error = result['error']?.toString() ?? 
                  (result['stderr']?.toString() ?? 'Setup command execution failed');
        }
      });

      if (mounted && isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Setup command executed successfully'),
            backgroundColor: Colors.green,
          ),
        );
        // Close dialog after a short delay to show success message
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      setState(() {
        _isRunning = false;
        _error = e.toString();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
        width: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Setup Experiment',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _isRunning ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Project Name (read-only)
            TextField(
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Project Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              controller: TextEditingController(text: widget.projectName),
            ),
            const SizedBox(height: 20),

            // Domain Selection Dropdown
            DropdownButtonFormField<String>(
              value: _selectedDomainCode,
              decoration: InputDecoration(
                labelText: 'Domain',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
              ),
              items: widget.domains.map((domain) {
                final code = domain['code']?.toString() ?? '';
                final name = domain['name']?.toString() ?? code;
                return DropdownMenuItem<String>(
                  value: code,
                  child: Text(name),
                );
              }).toList(),
              onChanged: _isRunning
                  ? null
                  : (value) {
                      setState(() {
                        _selectedDomainCode = value;
                        _selectedBlock = null; // Reset block when domain changes
                      });
                    },
            ),
            const SizedBox(height: 20),

            // Block Selection Dropdown (filtered by selected domain)
            DropdownButtonFormField<String>(
              value: _selectedBlock,
              decoration: InputDecoration(
                labelText: 'Block/Module',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
              ),
              items: _availableBlocks.map((block) {
                final name = block['name']?.toString() ?? '';
                return DropdownMenuItem<String>(
                  value: name,
                  child: Text(name),
                );
              }).toList(),
              onChanged: _isRunning
                  ? null
                  : (value) {
                      setState(() {
                        _selectedBlock = value;
                      });
                    },
            ),
            const SizedBox(height: 20),

            // Experiment Input
            TextField(
              controller: _experimentController,
              enabled: !_isRunning,
              decoration: InputDecoration(
                labelText: 'Experiment Name',
                hintText: 'Enter experiment name (e.g., exp1)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
              ),
            ),
            const SizedBox(height: 24),

            // Output/Error Display
            if (_output != null || _error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _error != null
                      ? Colors.red.shade50
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _error != null
                        ? Colors.red.shade300
                        : Colors.green.shade300,
                  ),
                ),
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(
                    _error ?? _output ?? '',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: _error != null
                          ? Colors.red.shade900
                          : Colors.green.shade900,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isRunning ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isRunning ? null : _runSetup,
                  icon: _isRunning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.settings),
                  label: Text(_isRunning ? 'Running...' : 'Setup'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    backgroundColor: _isSuccess ? Colors.green : null,
                    foregroundColor: _isSuccess ? Colors.white : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
