import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
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
  bool _isZohoConnectLoading = false;

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
      // Log error for debugging but continue with fallback
      print('Error checking project CAD role for $projectIdentifier: $e');
    }
    return {'effectiveRole': null};
  }

  Future<void> _loadProjects() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final token = ref.read(authProvider).token;
      if (token == null) {
        throw Exception('No authentication token');
      }

      // Non-admin (including CAD engineer): use DB only. Request Zoho projects only for admin.
      final isAdmin = ref.read(authProvider).user?['role'] == 'admin';
      Map<String, dynamic> projectsData;
      try {
        projectsData = await _apiService.getProjectsWithZoho(token: token, includeZoho: isAdmin);
      } catch (e) {
        // If that fails, fallback to regular projects
        final projects = await _apiService.getProjects(token: token);
        projectsData = {'all': projects, 'local': projects, 'zoho': []};
      }
      
      if (mounted) {
        setState(() {
          // Handle both array and object response formats
          final allProjects = projectsData['all'] ?? projectsData['local'] ?? [];
          if (allProjects is List) {
            _projects = List<Map<String, dynamic>>.from(allProjects);
          } else {
            _projects = [];
          }
          _isLoading = false;
        });
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

    for (var project in _projects) {
      final status = _getProjectStatus(project);
      if (status == 'RUNNING') {
        running++;
      } else if (status == 'COMPLETED') {
        completed++;
      }
    }

    return {
      'total': _projects.length,
      'running': running,
      'completed': completed,
    };
  }

  Future<void> _connectZoho() async {
    final token = ref.read(authProvider).token;
    if (token == null) return;
    setState(() => _isZohoConnectLoading = true);
    try {
      final response = await _apiService.getZohoAuthUrl(token: token);
      final authUrl = response['authUrl'] as String?;
      if (authUrl == null || authUrl.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not get Zoho authorization URL'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Complete authorization in the browser, then return here. Projects will refresh automatically.'),
              duration: Duration(seconds: 5),
            ),
          );
          Future.delayed(const Duration(seconds: 4), () {
            if (mounted) _loadProjects();
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open browser'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Zoho connect failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isZohoConnectLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _projectStats;
    final filteredProjects = _filteredProjects;
    final isAdmin = ref.watch(authProvider).user?['role'] == 'admin';

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
                          // Header with Zoho Connect (admin only)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
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
                              ),
                              if (isAdmin) ...[
                                const SizedBox(width: 16),
                                FilledButton.icon(
                                  onPressed: _isZohoConnectLoading ? null : _connectZoho,
                                  icon: _isZohoConnectLoading
                                      ? SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(Icons.link, size: 20),
                                  label: Text(_isZohoConnectLoading ? 'Connecting...' : 'Zoho Connect'),
                                ),
                              ],
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
            childAspectRatio: 1.15, // Reduced from 1.35 to make cards taller
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
    
    // Check if project is exported to Linux - ONLY show RUNNING if exported
    // Handle both boolean true and string "true" values
    final exportedValue = project['exported_to_linux'];
    final isExported = exportedValue == true || 
                       exportedValue == 'true' || 
                       exportedValue == 1 ||
                       exportedValue == '1';
    if (isExported) {
      return 'RUNNING';
    }
    
    // If not exported, show other statuses or default to IDLE
    if (status == 'COMPLETED' || status == 'COMPLETE') {
      return 'COMPLETED';
    } else if (status == 'FAILED' || status == 'ERROR') {
      return 'FAILED';
    }
    // Default to IDLE for all other cases (including RUNNING/IN_PROGRESS if not exported)
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
    // Get technology node from project details - check multiple possible locations
    final projectDetails = project['project_details'] as Map<String, dynamic>?;
    final zohoData = project['zoho_data'] as Map<String, dynamic>?;
    final technology = project['technology_node'] ?? 
                       project['technology'] ?? 
                       projectDetails?['technology_node'] ?? 
                       zohoData?['technology_node'] ?? 
                       'N/A';
    final lastRun = _formatTimeAgo(project['last_run']?.toString() ?? project['updated_at']?.toString());
    // Get run directories - check for array first, then fallback to single
    final runDirectoriesList = project['run_directories'];
    final List<String> runDirectories = runDirectoriesList != null && runDirectoriesList is List
        ? runDirectoriesList.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : (project['run_directory']?.toString() != null && project['run_directory'].toString().isNotEmpty
            ? [project['run_directory'].toString()]
            : []);
    final runDirectory = runDirectories.isNotEmpty ? runDirectories[0] : null; // Keep for backward compatibility
    // Check if project is exported to Linux - handle both boolean and string values
    final exportedValue = project['exported_to_linux'];
    final isExported = exportedValue == true || 
                       exportedValue == 'true' || 
                       exportedValue == 1 ||
                       exportedValue == '1';
    final progressValue = project['progress'];
    // If exported, show 10% progress. Otherwise use the normal progress calculation
    final progress = isExported 
        ? 10.0
        : (progressValue != null 
            ? (progressValue is num ? progressValue.toDouble() : double.tryParse(progressValue.toString()) ?? 0.0)
            : (status == 'RUNNING' ? 65.0 : 0.0));
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
    
    // Determine project identifier - prefer Zoho project ID for Zoho projects
    final projectIdentifier = project['zoho_project_id']?.toString() ?? 
                             project['id']?.toString() ?? 
                             projectName;
    
    // Check project-specific CAD engineer role
    return FutureBuilder<Map<String, dynamic>>(
      future: _checkProjectCadRole(projectIdentifier),
      builder: (context, snapshot) {
        // Get effective role (project-specific if available, otherwise global)
        final effectiveRole = snapshot.hasData ? snapshot.data!['effectiveRole'] : userRole;
        
        // Check if user is CAD engineer (global or project-specific)
        // Only CAD engineers should see Export to Linux button
        final isCadEngineerForProject = effectiveRole == 'cad_engineer' || 
                                        userRole == 'cad_engineer';
        
        // Check if user is NOT a CAD engineer
        // Setup button is for non-CAD roles except admin (admin only sees Sync Projects on cards)
        final isEngineerForProject = effectiveRole != 'cad_engineer' && 
                                     userRole != 'cad_engineer' &&
                                     userRole != 'admin';
        
        // Check export status from project data (from API) - handle both boolean and string values
        final exportedValue = project['exported_to_linux'];
        final isExported = exportedValue == true || 
                           exportedValue == 'true' || 
                           exportedValue == 1 ||
                           exportedValue == '1';
        // Setup completed (from projects table) - when true, show "Exported" instead of Setup/Project Setup
        final setupCompletedValue = project['setup_completed'];
        final isSetupCompleted = setupCompletedValue == true ||
                                 setupCompletedValue == 'true' ||
                                 setupCompletedValue == 1 ||
                                 setupCompletedValue == '1';
        
        final isZohoProject = project['source'] == 'zoho';
        final showSyncProjects = userRole == 'admin' && isZohoProject;
        final startDate = project['start_date']?.toString() ??
            projectDetails?['start_date']?.toString() ??
            zohoData?['start_date']?.toString();
        final targetDate = project['target_date']?.toString() ??
            projectDetails?['target_date']?.toString() ??
            zohoData?['target_date']?.toString();

        return _ProjectCardWidget(
          project: project,
          status: status,
          statusConfig: statusConfig,
          projectName: projectName,
          description: description.isEmpty ? 'Hardware design project' : description,
          gateCount: gateCount.toString(),
          technology: technology,
          startDate: startDate?.isNotEmpty == true ? startDate : null,
          targetDate: targetDate?.isNotEmpty == true ? targetDate : null,
          lastRun: lastRun,
          progress: progress,
          isRunning: isRunning,
          runDirectory: runDirectory,
          runDirectories: runDirectories,
          onTap: handleProjectClick,
          canExportToLinux: isCadEngineerForProject,
          isExported: isExported,
          isSetupCompleted: isSetupCompleted,
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
          canSyncProjects: showSyncProjects,
          onSyncProjects: showSyncProjects ? () => _syncProjectMembers(context, project) : null,
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

  /// Get Zoho project ID from project map.
  String? _getZohoProjectId(Map<String, dynamic> project) {
    var id = project['zoho_project_id']?.toString() ??
        project['zoho_id']?.toString() ??
        project['id']?.toString();
    final zohoData = project['zoho_data'] as Map<String, dynamic>?;
    if (id == null) id = zohoData?['id']?.toString();
    if (id == null) return null;
    if (id.startsWith('zoho_')) return id.replaceFirst('zoho_', '');
    return id;
  }

  /// Sync members from Zoho project. Shows confirmation with project and domains, then syncs.
  Future<void> _syncProjectMembers(BuildContext context, Map<String, dynamic> project) async {
    final zohoProjectId = _getZohoProjectId(project);
    if (zohoProjectId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Zoho Project ID not found'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    final token = ref.read(authProvider).token;
    if (token == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not authenticated'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    final portalId = project['portal_id']?.toString() ?? project['portalId']?.toString();
    final zohoData = project['zoho_data'] as Map<String, dynamic>?;
    final portalIdFromZoho = zohoData?['portal_id']?.toString() ?? zohoData?['portal']?.toString();
    final effectivePortalId = portalId ?? portalIdFromZoho;
    final zohoProjectName = project['name']?.toString();

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    Map<String, dynamic>? preview;
    try {
      preview = await _apiService.syncZohoProjectMembersPreview(
        zohoProjectId: zohoProjectId,
        portalId: effectivePortalId,
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

    try {
      final result = await _apiService.syncZohoProjectMembersByZohoId(
        zohoProjectId: zohoProjectId,
        portalId: effectivePortalId,
        zohoProjectName: zohoProjectName,
        token: token,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully synced ${result['updatedAssignments']} members. Created ${result['createdUsers']} new users.',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
        if (result['errors'] != null && (result['errors'] as List).isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sync completed with ${(result['errors'] as List).length} errors.'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
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

      // Non-admin (including CAD engineer): use DB only. Zoho only for auth.
      final userRole = ref.read(authProvider).user?['role']?.toString();
      final isAdmin = userRole == 'admin';
      
      // Get project ID - handle both zoho_ prefix and direct ID (only for Zoho projects when admin)
      final isZohoProject = project['source'] == 'zoho' ||
          (project['zoho_project_id'] != null && project['zoho_project_id'].toString().trim().isNotEmpty);
      final rawId = isZohoProject ? (project['zoho_project_id'] ?? project['id'])?.toString() ?? '' : '';
      final actualProjectId = rawId.startsWith('zoho_') ? rawId.replaceFirst('zoho_', '') : rawId;
      
      List<Map<String, dynamic>> domains = [];
      
      // Only admin can fetch domains from Zoho; non-admin use DB only
      if (isAdmin && isZohoProject && actualProjectId.isNotEmpty) {
        try {
          final zohoData = project['zoho_data'] as Map<String, dynamic>?;
          final portalId = zohoData?['portal_id']?.toString() ?? zohoData?['portal']?.toString();
          
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
        
        // Get project ID and portal ID for export tracking
        final projectId = project['zoho_project_id']?.toString() ?? 
                         project['id']?.toString() ?? '';
        final portalId = project['portal_id']?.toString() ?? 
                        project['zoho_data']?['portal_id']?.toString();
        
        showDialog(
          context: context,
          builder: (context) => _ExportToLinuxDialog(
            projectName: projectName,
            projectId: projectId,
            portalId: portalId,
            domains: domains,
            apiService: _apiService,
            onExportSuccess: () {
              // Reload projects to get updated export status from API
              _loadProjects();
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
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Not authenticated'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Fetch blocks from DB only (no Zoho). Use project id (local) or project name for resolution.
      final projectIdOrName = project['id'] ?? project['name'] ?? projectName;
      List<dynamic> blocksRaw = [];
      try {
        blocksRaw = await _apiService.getProjectBlocks(
          projectIdOrName: projectIdOrName,
          filterByAssigned: true,
          token: token,
        );
      } catch (e) {
        print('Error fetching blocks from DB: $e');
      }
      final blocks = (blocksRaw)
          .where((b) => b != null && b is Map<String, dynamic>)
          .map((b) => Map<String, dynamic>.from(b as Map))
          .toList();

      // Zoho project ID for save-run-directory (if linked)
      final isZohoProject = project['source'] == 'zoho' ||
          (project['zoho_project_id'] != null && project['zoho_project_id'].toString().trim().isNotEmpty);
      final rawZohoId = isZohoProject
          ? (project['zoho_project_id'] ?? project['id'])?.toString() ?? ''
          : '';
      String? actualZohoProjectId = rawZohoId.startsWith('zoho_')
          ? rawZohoId.replaceFirst('zoho_', '')
          : (rawZohoId.isNotEmpty ? rawZohoId : null);
      if (actualZohoProjectId != null && actualZohoProjectId.isEmpty) actualZohoProjectId = null;

      if (mounted) {
        Navigator.of(context).pop();
        showDialog(
          context: context,
          builder: (context) => _SetupDialog(
            projectName: projectName,
            blocks: blocks,
            apiService: _apiService,
            zohoProjectId: actualZohoProjectId,
            onRunDirectorySaved: (_) {
              _loadProjects();
            },
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
  final String? startDate;
  final String? targetDate;
  final String lastRun;
  final double progress;
  final bool isRunning;
  final String? runDirectory;
  final List<String> runDirectories;
  final VoidCallback onTap;
  final bool canExportToLinux;
  final bool isExported;
  final bool isSetupCompleted;
  final VoidCallback? onExportToLinux;
  final bool canSetup;
  final VoidCallback? onSetup;
  final bool canSyncProjects;
  final VoidCallback? onSyncProjects;

  const _ProjectCardWidget({
    required this.project,
    required this.status,
    required this.statusConfig,
    required this.projectName,
    required this.description,
    required this.gateCount,
    required this.technology,
    this.startDate,
    this.targetDate,
    required this.lastRun,
    required this.progress,
    required this.isRunning,
    this.runDirectory,
    this.runDirectories = const [],
    required this.onTap,
    this.canExportToLinux = false,
    this.isExported = false,
    this.isSetupCompleted = false,
    this.onExportToLinux,
    this.canSetup = false,
    this.onSetup,
    this.canSyncProjects = false,
    this.onSyncProjects,
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
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
              const SizedBox(height: 12),
              
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
              const SizedBox(height: 16),
              
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
              if (widget.startDate != null || widget.targetDate != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (widget.startDate != null)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Start',
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.startDate!,
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (widget.targetDate != null)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Target',
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.targetDate!,
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 12),
              
              // Last Run
              Text(
                'Last run: ${widget.lastRun}',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              
              // Run Directories (if available) - show only latest
              if (widget.runDirectories.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.runDirectories.last, // Show only the latest directory
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.primary,
                              fontFamily: 'monospace',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              
              const SizedBox(height: 12),
              
              // Progress Bar (if running)
              if (widget.isRunning) ...[
                const SizedBox(height: 8),
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
                const SizedBox(height: 8),
              ],
              
              // Divider
              Divider(
                color: Theme.of(context).dividerColor,
                height: 1,
              ),
              const SizedBox(height: 8),
              
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
                      if (widget.canSyncProjects)
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: OutlinedButton.icon(
                            onPressed: widget.onSyncProjects,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              side: BorderSide(color: const Color(0xFF14B8A6)),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.sync, size: 16),
                            label: const Text(
                              'Sync Projects',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
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
                          child: (widget.isExported || widget.isSetupCompleted)
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
                                    'Project Setup',
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
      ),
    );
  }
}

class _ExportToLinuxDialog extends ConsumerStatefulWidget {
  final String projectName;
  final String projectId;
  final String? portalId;
  final List<Map<String, dynamic>> domains;
  final ApiService apiService;
  final VoidCallback? onExportSuccess;

  const _ExportToLinuxDialog({
    required this.projectName,
    required this.projectId,
    this.portalId,
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
  bool _exportSuccess = false;
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
      // Project group: derived from project name (sanitized)
      final projectNameSanitized = widget.projectName.replaceAll(' ', '_');
      final command = 'sudo python3 /CX_CAD/REL/env_scripts/infra/latest/createDir.py --base-path /CX_PROJ --proj $projectNameSanitized --dom $domainCodesStr --project-group $projectNameSanitized --scratch-base-path /CX_RUN_NEW';

      // Print command to console with final substituted values
      print('═══════════════════════════════════════════════════════════');
      print('🚀 EXECUTING SSH COMMAND:');
      print('   Final Command: $command');
      print('   Project Name: ${widget.projectName}');
      print('   Sanitized Project: $projectNameSanitized');
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

      // Build full output message combining stdout and stderr
      String fullOutput = '';
      if (result['stdout'] != null && result['stdout'].toString().trim().isNotEmpty) {
        fullOutput = result['stdout'].toString().trim();
      }
      if (result['stderr'] != null && result['stderr'].toString().trim().isNotEmpty) {
        final stderr = result['stderr'].toString().trim();
        // Filter out "DISPLAY: Undefined variable" warnings but keep real errors
        final stderrLines = stderr.split('\n').where((line) => 
          !line.contains('DISPLAY: Undefined variable')
        ).toList();
        if (stderrLines.isNotEmpty) {
          final filteredStderr = stderrLines.join('\n');
          if (fullOutput.isNotEmpty) {
            fullOutput += '\n\n--- Stderr ---\n$filteredStderr';
          } else {
            fullOutput = filteredStderr;
          }
        }
      }
      
      final exitCode = result['exitCode'] as int?;
      final isSuccess = result['success'] == true && (exitCode == 0 || exitCode == null);
      
      setState(() {
        _isRunning = false;
        if (isSuccess) {
          // Success: show full output
          _output = fullOutput.isNotEmpty 
              ? fullOutput 
              : 'Command executed successfully';
        } else {
          // Error: show full output (stdout + stderr) so user sees the real error
          final errorMsg = result['error']?.toString();
          if (fullOutput.isNotEmpty) {
            _error = fullOutput;
            if (errorMsg != null && errorMsg.isNotEmpty) {
              _error = '$errorMsg\n\n--- Command Output ---\n$fullOutput';
            }
          } else {
            _error = errorMsg ?? 'Command execution failed';
          }
          // Add exit code info if available
          if (exitCode != null && exitCode != 0) {
            _error = 'Exit Code: $exitCode\n\n$_error';
          }
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
        final success = await _showPasswordRequiredDialog(context, command, output);
        if (success == true && mounted) {
          setState(() {
            _isRunning = false;
            _exportSuccess = true;
            _output = 'Export completed successfully.';
            _error = null;
          });
          // Update DB: mark project setup completed when CAD engineer finishes Export to Linux
          try {
            await widget.apiService.markProjectSetupCompleted(
              projectId: widget.projectId,
              projectName: widget.projectName,
              token: token,
            );
            widget.onExportSuccess?.call();
          } catch (e) {
            print('⚠️ Failed to mark setup completed: $e');
          }
        } else if (mounted) {
          setState(() => _isRunning = false);
        }
      } else if (mounted && isSuccess) {
        // Update DB: mark project setup completed when CAD engineer finishes Export to Linux
        try {
          await widget.apiService.markProjectSetupCompleted(
            projectId: widget.projectId,
            projectName: widget.projectName,
            token: token,
          );
          widget.onExportSuccess?.call();
        } catch (e) {
          print('⚠️ Failed to mark setup completed: $e');
        }
        // Try to fetch and display the run directory path after successful execution
        try {
          print('═══════════════════════════════════════════════════════════');
          print('🔍 FETCHING RUN DIRECTORY PATH AFTER createDir.py:');
          print('   Project: ${widget.projectName}');
          print('   Sanitized Project: $projectNameSanitized');
          print('═══════════════════════════════════════════════════════════');
          
          // Get the actual username from the remote server
          final whoamiResult = await widget.apiService.executeSSHCommand(
            command: 'whoami',
            token: token,
          );
          
          String? actualUsername;
          if (whoamiResult['success'] == true && whoamiResult['stdout'] != null) {
            actualUsername = whoamiResult['stdout'].toString().trim();
            print('   ✅ Actual username on server: $actualUsername');
          }
          
          if (actualUsername != null && actualUsername.isNotEmpty) {
            // Check if the project directory was created under /CX_PROJ
            // The createDir.py script typically creates: /CX_PROJ/{project}/...
            // Run directories are typically under: /CX_RUN_NEW/{project}/pd/users/{username}/...
            // But we should check what was actually created
            
            // First, check if project directory exists under /CX_PROJ
            final checkProjDirCommand = 'if [ -d "/CX_PROJ/$projectNameSanitized" ]; then echo "/CX_PROJ/$projectNameSanitized"; else echo ""; fi';
            final projDirResult = await widget.apiService.executeSSHCommand(
              command: checkProjDirCommand,
              token: token,
            );
            
            String? projectDir;
            if (projDirResult['success'] == true && projDirResult['stdout'] != null) {
              final stdout = projDirResult['stdout'].toString().trim();
              if (stdout.isNotEmpty && stdout.startsWith('/')) {
                projectDir = stdout;
                print('   ✅ Found project directory: $projectDir');
              }
            }
            
            // Check for run directory under /CX_RUN_NEW (common pattern)
            // Look for: /CX_RUN_NEW/{project}/pd/users/{username}/*
            final escapedProject = projectNameSanitized.replaceAll("'", "'\\''");
            final escapedUsername = actualUsername.replaceAll("'", "'\\''");
            final findRunDirCommand = "find /CX_RUN_NEW/$escapedProject/pd/users/$escapedUsername -maxdepth 3 -type d 2>/dev/null | head -1 || echo ''";
            
            final runDirResult = await widget.apiService.executeSSHCommand(
              command: findRunDirCommand,
              token: token,
            );
            
            String? runDirectory;
            if (runDirResult['success'] == true && runDirResult['stdout'] != null) {
              final stdout = runDirResult['stdout'].toString().trim();
              if (stdout.isNotEmpty && stdout.startsWith('/')) {
                runDirectory = stdout.split('\n').first.trim();
                print('   ✅ Found run directory: $runDirectory');
              }
            }
            
            // If not found, construct expected path based on common pattern
            if (runDirectory == null || runDirectory.isEmpty) {
              // Common pattern: /CX_RUN_NEW/{project}/pd/users/{username}
              runDirectory = '/CX_RUN_NEW/$projectNameSanitized/pd/users/$actualUsername';
              print('   ⚠️ Run directory not found via search, using expected path: $runDirectory');
            }
            
            print('═══════════════════════════════════════════════════════════');
            print('📁 DIRECTORY PATHS:');
            if (projectDir != null) {
              print('   Project Directory: $projectDir');
            }
            print('   Run Directory: $runDirectory');
            print('═══════════════════════════════════════════════════════════');
            
            // Update the output to include the run directory path
            if (mounted) {
              setState(() {
                _output = '${_output ?? 'Command executed successfully'}\n\n📁 Project Directory: ${projectDir ?? 'Not found'}\n📁 Run Directory: $runDirectory';
              });
            }
          }
        } catch (e) {
          print('⚠️ Warning: Failed to fetch run directory path: $e');
          // Don't fail the entire operation if fetching path fails
        }
        
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

  Future<bool?> _showPasswordRequiredDialog(BuildContext context, String command, String output) async {
    final passwordController = TextEditingController();
    bool isSendingPassword = false;
    bool showOutput = false;
    String liveOutput = output;
    bool isCommandRunning = false;
    int? lastExitCode;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Minimal "Running......." only UI when Send Password hit or command running (no big form)
          final showMinimalRunning = (showOutput && isCommandRunning) || isSendingPassword;
          if (showMinimalRunning) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Running.......',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return Dialog(
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
                // Content: when complete show full output; else password form
                Expanded(
                  child: showOutput
                      ? (isCommandRunning
                          ? const SizedBox.shrink() // minimal state handled above
                          : _buildLiveOutputView(
                              liveOutput,
                              setDialogState,
                              isComplete: true,
                              exitCode: lastExitCode,
                            ))
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
                                      () {
                                        setDialogState(() {
                                          showOutput = true;
                                          isCommandRunning = true;
                                          isSendingPassword = false;
                                        });
                                      },
                                      (newOutput, exitCode) {
                                        setDialogState(() {
                                          liveOutput = newOutput;
                                          lastExitCode = exitCode;
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
                // Actions: when output shown and complete -> Close only; when password form -> Cancel + Send Password (enabled when text not empty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade300),
                    )
                  ),
                  child: showOutput && !isCommandRunning
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              ),
                              child: const Text('Close'),
                            ),
                          ],
                        )
                      : !showOutput
                          ? ValueListenableBuilder<TextEditingValue>(
                              valueListenable: passwordController,
                              builder: (context, value, child) {
                                final hasPassword = value.text.trim().isNotEmpty;
                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: isSendingPassword ? null : () => Navigator.of(context).pop(null),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                      ),
                                      child: const Text('Cancel'),
                                    ),
                                    const SizedBox(width: 12),
                                    ElevatedButton.icon(
                                      onPressed: isSendingPassword || !hasPassword
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
                                                () {
                                                  setDialogState(() {
                                                    showOutput = true;
                                                    isCommandRunning = true;
                                                    isSendingPassword = false;
                                                  });
                                                },
                                                (newOutput, exitCode) {
                                                  setDialogState(() {
                                                    liveOutput = newOutput;
                                                    lastExitCode = exitCode;
                                                    isCommandRunning = false;
                                                  });
                                                },
                                              );
                                              if (mounted) setDialogState(() {
                                                isSendingPassword = false;
                                              });
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
                                );
                              },
                            )
                          : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        );
        },
      ),
    );
  }

  Widget _buildLiveOutputView(String output, StateSetter setDialogState, {bool isComplete = false, int? exitCode}) {
    final scrollController = ScrollController();

    // Clean up output - remove shell prompts and command echo
    String cleanOutput = _cleanCommandOutput(output);
    // When complete, prefer showing something: use raw output if cleaning stripped everything
    final displayOutput = cleanOutput.isNotEmpty ? cleanOutput : (isComplete && output.trim().isNotEmpty ? output.trim() : '');

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
                          ? (isSuccess ? 'Project Setup Completed Successfully' : 'Project Setup Failed')
                          : 'Setting up project...',
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
                  // Output content: when complete never show spinner; show output or "Command completed."
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      child: (displayOutput.isEmpty && !isComplete)
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
                        : (displayOutput.isEmpty && isComplete)
                            ? Center(
                                child: Text(
                                  'Command completed.',
                                  style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 14,
                                  ),
                                ),
                              )
                            : SingleChildScrollView(
                            controller: scrollController,
                            child: SelectableText(
                              displayOutput,
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
    VoidCallback showOutputView,
    void Function(String output, int? exitCode) onComplete,
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

        final exitCode = result['exitCode'] as int?;
        onComplete(finalOutput, exitCode);

        // Only close dialog when command completes successfully
        // Success criteria:
        // 1. result['success'] == true AND
        // 2. (exitCode == 0 OR (exitCode == null AND output contains "Done." and no errors))
        final hasDoneMessage = finalOutput.toLowerCase().contains('done.');
        final hasError = finalOutput.toLowerCase().contains('error') || 
                        finalOutput.toLowerCase().contains('failed');
        // Consider success if: exit code is 0, OR (exit code is null but we see "Done." and no errors)
        final isSuccess = result['success'] == true && 
                         (exitCode == 0 || (exitCode == null && hasDoneMessage && !hasError));
        
        if (isSuccess) {
          // Mark project as exported in the database
          try {
            final token = ref.read(authProvider).token;
            await widget.apiService.markZohoProjectExported(
              projectId: widget.projectId,
              token: token,
              portalId: widget.portalId,
              projectName: widget.projectName,
            );
          } catch (e) {
            // Log error but don't fail the export - it was successful
            print('Error marking project as exported: $e');
          }
          
          // Notify parent that export was successful
          if (widget.onExportSuccess != null) {
            widget.onExportSuccess!();
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
          await Future.delayed(const Duration(milliseconds: 400));
          if (context.mounted) {
            Navigator.of(context).pop(true);
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
        onComplete('Error executing command: $e', null);
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
      onComplete('Error sending password: $e', null);
      
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
                  'Project Setup',
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

            // Action Buttons: on success only Close; else Cancel + Run
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_exportSuccess) ...[
                  TextButton(
                    onPressed: _isRunning ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                ],
                if (_exportSuccess)
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Close'),
                  )
                else
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
  final List<Map<String, dynamic>> blocks;
  final ApiService apiService;
  final String? zohoProjectId;
  final Function(String runDirectory)? onRunDirectorySaved;

  const _SetupDialog({
    required this.projectName,
    required this.blocks,
    required this.apiService,
    this.zohoProjectId,
    this.onRunDirectorySaved,
  });

  @override
  ConsumerState<_SetupDialog> createState() => _SetupDialogState();
}

class _SetupDialogState extends ConsumerState<_SetupDialog> {
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

  Future<void> _runSetup() async {
    if (_selectedBlock == null || _experimentController.text.trim().isEmpty) {
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

      // Build the command: echo "setup ..." | newgrp {project}. Domain is pd (blocks from DB are PD only).
      final projectName = widget.projectName;
      final sanitizedProjectName = projectName.replaceAll(' ', '_');
      const domainCode = 'pd';
      final blockName = _selectedBlock!;
      final sanitizedBlockName = blockName.replaceAll(' ', '_');
      final experimentName = _experimentController.text.trim();

      // Build command: echo "setup -proj ... -domain ... -block ... -exp ..." | newgrp {project}
      final command = 'echo "setup -proj $sanitizedProjectName -domain $domainCode -block $sanitizedBlockName -exp $experimentName" | newgrp $sanitizedProjectName';

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

      // Determine success: exit code must be 0 (or null if command completed without explicit exit code)
      // If exit code is 1 or any non-zero value, it's an error
      final exitCode = result['exitCode'] as int?;
      final isSuccess = result['success'] == true && (exitCode == 0 || (exitCode == null && result['stdout']?.toString().toLowerCase().contains('done.') == true));
      
      // If setup command succeeded, fetch the actual run directory path from remote server and save it
      if (isSuccess) {
        try {
          print('═══════════════════════════════════════════════════════════');
          print('🔍 FETCHING RUN DIRECTORY PATH FROM REMOTE SERVER:');
          print('   Project: $projectName');
          print('   Block: $blockName');
          print('   Experiment: $experimentName');
          print('═══════════════════════════════════════════════════════════');
          
          // Step 1: Get the actual username from the remote server
          print('   Step 1: Getting actual username from remote server...');
          final whoamiResult = await widget.apiService.executeSSHCommand(
            command: 'whoami',
            token: token,
          );
          
          String? actualUsername;
          if (whoamiResult['success'] == true && whoamiResult['stdout'] != null) {
            actualUsername = whoamiResult['stdout'].toString().trim();
            print('   ✅ Actual username on server: $actualUsername');
          }
          
          if (actualUsername == null || actualUsername.isEmpty) {
            throw Exception('Unable to get username from remote server');
          }
          
          // Step 2: Search for the directory that was just created
          // The setup command creates a directory matching: /CX_RUN_NEW/{project}/pd/users/{username}/{block}/{experiment}
          // We'll search for recently created directories matching this pattern
          print('   Step 2: Searching for directory created by setup command...');
          
          // Escape variables for shell command
          final escapedProject = sanitizedProjectName.replaceAll("'", "'\\''");
          final escapedBlock = sanitizedBlockName.replaceAll("'", "'\\''");
          final escapedExperiment = experimentName.replaceAll("'", "'\\''");
          final escapedUsername = actualUsername.replaceAll("'", "'\\''");
          
          // Construct expected path
          final expectedPath = '/CX_RUN_NEW/$escapedProject/pd/users/$escapedUsername/$escapedBlock/$escapedExperiment';
          
          // Command to find the directory:
          // 1. Try the expected path first
          // 2. If not found, search for directories matching the pattern
          // 3. Look for recently modified directories (created in last 5 minutes) matching the experiment name
          // Use single quotes to prevent variable expansion, and escape properly
          final findPathCommand = "EXPECTED_PATH='$expectedPath'; if [ -d \"\$EXPECTED_PATH\" ]; then echo \"\$EXPECTED_PATH\"; else find /CX_RUN_NEW/$escapedProject/pd/users/$escapedUsername -type d -name '$escapedExperiment' -mmin -5 2>/dev/null | head -1 || find /CX_RUN_NEW/$escapedProject/pd/users/$escapedUsername -type d -name '$escapedExperiment' 2>/dev/null | head -1; fi";
          
          final pathResult = await widget.apiService.executeSSHCommand(
            command: findPathCommand,
            token: token,
          );
          
          String? actualRunDirectory;
          if (pathResult['success'] == true && pathResult['stdout'] != null) {
            final stdout = pathResult['stdout'].toString().trim();
            if (stdout.isNotEmpty && stdout.startsWith('/')) {
              actualRunDirectory = stdout.split('\n').first.trim();
              print('   ✅ Found run directory: $actualRunDirectory');
            }
          }
          
          if (actualRunDirectory == null || actualRunDirectory.isEmpty) {
            // Last resort: construct path using actual username from server
            actualRunDirectory = '/CX_RUN_NEW/$sanitizedProjectName/pd/users/$actualUsername/$sanitizedBlockName/$experimentName';
            print('   ⚠️ Directory not found via search, using constructed path: $actualRunDirectory');
          }
          
          print('═══════════════════════════════════════════════════════════');
          print('💾 SAVING RUN DIRECTORY PATH TO DATABASE:');
          print('   Path: $actualRunDirectory');
          print('═══════════════════════════════════════════════════════════');
          
          print('   📤 Sending to backend:');
          print('      Project: $projectName');
          print('      Zoho Project ID: ${widget.zohoProjectId ?? "null"}');
          print('      Username: $actualUsername');
          print('      Run Directory: $actualRunDirectory');
          
          await widget.apiService.saveRunDirectory(
            projectName: projectName,
            blockName: blockName,
            experimentName: experimentName,
            runDirectory: actualRunDirectory,
            username: actualUsername,
            zohoProjectId: widget.zohoProjectId,
            domainCode: domainCode,
            token: token,
          );
          
          print('✅ Run directory path saved successfully');
          
          // Notify parent to update the project with the new run directory
          if (widget.onRunDirectorySaved != null) {
            widget.onRunDirectorySaved!(actualRunDirectory);
          }
        } catch (e) {
          print('⚠️ Warning: Failed to fetch/save run directory path: $e');
          // Don't fail the entire setup if saving path fails, just log it
          // The setup command already succeeded, so we continue
        }
      }
      
      // Build full output message combining stdout and stderr
      String fullOutput = '';
      if (result['stdout'] != null && result['stdout'].toString().trim().isNotEmpty) {
        fullOutput = result['stdout'].toString().trim();
      }
      if (result['stderr'] != null && result['stderr'].toString().trim().isNotEmpty) {
        final stderr = result['stderr'].toString().trim();
        // Filter out "DISPLAY: Undefined variable" warnings but keep real errors
        final stderrLines = stderr.split('\n').where((line) => 
          !line.contains('DISPLAY: Undefined variable')
        ).toList();
        if (stderrLines.isNotEmpty) {
          final filteredStderr = stderrLines.join('\n');
          if (fullOutput.isNotEmpty) {
            fullOutput += '\n\n--- Stderr ---\n$filteredStderr';
          } else {
            fullOutput = filteredStderr;
          }
        }
      }
      
      setState(() {
        _isRunning = false;
        _isSuccess = isSuccess;
        if (isSuccess) {
          // Success: show full output
          _output = fullOutput.isNotEmpty 
              ? fullOutput 
              : 'Setup command executed successfully';
        } else {
          // Error: show full output (stdout + stderr) so user sees the real error
          final errorMsg = result['error']?.toString();
          if (fullOutput.isNotEmpty) {
            _error = fullOutput;
            if (errorMsg != null && errorMsg.isNotEmpty) {
              _error = '$errorMsg\n\n--- Command Output ---\n$fullOutput';
            }
          } else {
            _error = errorMsg ?? 'Setup command execution failed';
          }
          // Add exit code info if available
          if (exitCode != null && exitCode != 0) {
            _error = 'Exit Code: $exitCode\n\n$_error';
          }
        }
      });

      if (mounted) {
        if (isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Setup completed successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
          // Close Project Setup dialog automatically when setup is done
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) Navigator.of(context).pop();
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Setup failed${exitCode != null ? ' (Exit Code: $exitCode)' : ''}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
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

            // While running show simple "Running......." UI; else show full form
            if (_isRunning)
              Container(
                constraints: const BoxConstraints(minHeight: 200),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Running.......',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
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

            // Block Selection Dropdown (from DB only; no domain shown)
            widget.blocks.isEmpty
                ? Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No blocks available for this project. Sync blocks from Zoho (admin) or ask an admin to add blocks.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : DropdownButtonFormField<String>(
                    value: _selectedBlock,
                    decoration: InputDecoration(
                      labelText: 'Block',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                    ),
                    items: widget.blocks.map((block) {
                      final name = block['block_name']?.toString() ?? block['name']?.toString() ?? '';
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

            // Experiment Name (input only, not fetched)
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

            // Action Buttons: on success show only Close; while running show Cancel disabled + Running...; else Cancel + Setup
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_isSuccess) ...[
                  TextButton(
                    onPressed: _isRunning ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                ],
                if (_isSuccess)
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Close'),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: (_isRunning || widget.blocks.isEmpty) ? null : _runSetup,
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
                    ),
                  ),
              ],
            ),
            ], // end else (full form)
          ],
        ),
      ),
    );
  }
}
