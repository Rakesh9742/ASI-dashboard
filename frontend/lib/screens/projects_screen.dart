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
    
    // Check project-specific CAD engineer role
    return FutureBuilder<Map<String, dynamic>>(
      future: _checkProjectCadRole(projectName),
      builder: (context, snapshot) {
        // Check if user is CAD engineer for this project (global or project-specific)
        final isCadEngineerForProject = globalCanExportToLinux || 
            (snapshot.hasData && snapshot.data!['effectiveRole'] == 'cad_engineer');
        
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
          onExportToLinux: isCadEngineerForProject
              ? () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Export to Linux triggered for \"$projectName\"'),
                    ),
                  );
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
  final VoidCallback? onExportToLinux;

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
    this.onExportToLinux,
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
                      if (widget.canExportToLinux)
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: OutlinedButton.icon(
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
