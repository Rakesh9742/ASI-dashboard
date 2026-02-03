import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:html' as html;
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../providers/error_handler_provider.dart';
import '../providers/tab_provider.dart';
import '../providers/view_screen_provider.dart';
import 'main_navigation_screen.dart';
import 'view_screen.dart';

// Brand accent for project cards (matches main nav)
const Color _kCardAccent = Color(0xFF6366F1);
const Color _kCardAccentSecondary = Color(0xFF4F46E5);

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
  /// Zoho connection status for admin: true = connected, false = not connected, null = not checked yet
  bool? _isZohoConnected;

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

      // Only request Zoho projects when user has actually connected Zoho (avoids showing Zoho projects from stale token).
      final isAdmin = ref.read(authProvider).user?['role'] == 'admin';
      bool includeZoho = false;
      if (isAdmin) {
        try {
          final status = await _apiService.getZohoStatus(token: token);
          final connected = status['connected'];
          includeZoho = connected == true || connected == 'true' || connected == 1;
        } catch (_) {
          includeZoho = false;
        }
      }

      Map<String, dynamic> projectsData;
      try {
        projectsData = await _apiService.getProjectsWithZoho(token: token, includeZoho: includeZoho);
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
          if (isAdmin) _isZohoConnected = includeZoho;
        });
        // Log what UI will show after Zoho auth / refresh (for debugging project card status)
        try {
          print('═══ [Projects UI] After load: ${_projects.length} projects ═══');
          for (int i = 0; i < _projects.length && i < 20; i++) {
            final p = _projects[i];
            final name = p['name'] ?? '?';
            final apiStatus = p['status'] ?? '';
            final exported = p['exported_to_linux'];
            final source = p['source'] ?? '?';
            final displayStatus = _getProjectStatus(p);
            print('  [$i] name=$name | source=$source | API status=$apiStatus | exported_to_linux=$exported | _getProjectStatus=>$displayStatus');
          }
          if (_projects.length > 20) print('  ... and ${_projects.length - 20} more');
          print('═══ [Projects UI] End ═══');
        } catch (e) {
          print('Projects UI log error: $e');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ref.read(errorHandlerProvider.notifier).showError(e, title: 'Failed to load projects');
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

  void _onZohoConnectMessage(html.Event event) {
    final messageEvent = event as html.MessageEvent;
    final data = messageEvent.data;
    if (data is Map && data['type'] == 'ZOHO_CONNECT_SUCCESS') {
      html.window.removeEventListener('message', _onZohoConnectMessage);
      if (mounted) {
        _loadProjects();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Zoho connected successfully. Projects refreshed.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
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
      // Open Zoho auth in a popup window (same tab, not new tab)
      try {
        html.window.addEventListener('message', _onZohoConnectMessage);
        html.window.open(
          authUrl,
          'zoho_connect',
          'width=600,height=700,scrollbars=yes,resizable=yes,location=yes',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Complete authorization in the popup window'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      } catch (e) {
        // Fallback: open in new tab if popup blocked or not web
        final uri = Uri.parse(authUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Complete authorization in the browser, then return here.'),
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
              const SnackBar(content: Text('Could not open authorization window'), backgroundColor: Colors.red),
            );
          }
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
    // Refresh projects when user navigates back to Projects screen (e.g. after closing popout)
    ref.listen(currentNavTabProvider, (prev, next) {
      if (next == 'Projects' && mounted) _loadProjects();
    });

    final stats = _projectStats;
    final filteredProjects = _filteredProjects;
    final isAdmin = ref.watch(authProvider).user?['role'] == 'admin';

    // Show Projects content (header is now in MainNavigationScreen)
    return Material(
      color: Colors.transparent,
      child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _loadProjects,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
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
                                Tooltip(
                                  message: 'Connect your Zoho Projects account to sync projects and members. Click to open the connection page.',
                                  child: FilledButton.icon(
                                    onPressed: _isZohoConnectLoading ? null : _connectZoho,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _isZohoConnected == true
                                        ? Colors.green.shade600
                                        : (_isZohoConnected == false
                                            ? Colors.red.shade700
                                            : Theme.of(context).colorScheme.primary),
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: _isZohoConnectLoading
                                      ? SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : Icon(
                                          _isZohoConnected == true ? Icons.check_circle_outline : Icons.link,
                                          size: 20,
                                        ),
                                    label: Text(_isZohoConnectLoading ? 'Connecting...' : 'Zoho Connect'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 32),

                          // Summary Cards
                          _buildSummaryCards(stats),
                          const SizedBox(height: 32),

                          // Search Bar
                          Tooltip(
                            message: 'Type here to search projects by name or description.',
                            child: SizedBox(
                              width: double.infinity,
                              child: _buildSearchBar(),
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Projects Grid
                          _buildProjectsGrid(filteredProjects),
                        ],
                      ),
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
                  Expanded(child: Tooltip(message: 'Total number of projects you have access to', child: _buildStatCard('Total Projects', stats['total']!.toString(), Theme.of(context).colorScheme.onSurface))),
                  const SizedBox(width: 16),
                  Expanded(child: Tooltip(message: 'Number of projects currently running', child: _buildStatCard('Running', stats['running']!.toString(), Theme.of(context).colorScheme.secondary))),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Tooltip(message: 'Number of projects that have completed', child: _buildStatCard('Completed', stats['completed']!.toString(), const Color(0xFF10B981)))),
                ],
              ),
            ],
          );
        }
        
        return Row(
          children: [
            Expanded(
              child: Tooltip(message: 'Total number of projects you have access to', child: _buildStatCard('Total Projects', stats['total']!.toString(), Theme.of(context).colorScheme.onSurface)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Tooltip(message: 'Number of projects currently running', child: _buildStatCard('Running', stats['running']!.toString(), Theme.of(context).colorScheme.secondary)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Tooltip(message: 'Number of projects that have completed', child: _buildStatCard('Completed', stats['completed']!.toString(), const Color(0xFF10B981))),
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
            childAspectRatio: 1.35, // Tighter ratio = less empty space; card fills cell
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
    // If exported to Linux, show RUNNING (exported = ready to run / running) — takes precedence
    final exportedValue = project['exported_to_linux'];
    final isExported = exportedValue == true ||
        exportedValue == 'true' ||
        exportedValue == 1 ||
        exportedValue == '1';
    if (isExported) {
      return 'RUNNING';
    }
    // Else use API status (COMPLETED, FAILED, RUNNING, IDLE)
    final status = (project['status'] ?? '').toString().toUpperCase();
    if (status == 'COMPLETED' || status == 'COMPLETE') {
      return 'COMPLETED';
    }
    if (status == 'FAILED' || status == 'ERROR') {
      return 'FAILED';
    }
    if (status == 'RUNNING' || status == 'IN PROGRESS' || status == 'IN_PROGRESS' || status == 'ACTIVE') {
      return 'RUNNING';
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

  /// Format last run timestamp for display (e.g. "Jan 15, 2025, 3:00 PM").
  String? _formatLastRunDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return null;
    try {
      final date = DateTime.parse(dateString);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
      final ampm = date.hour >= 12 ? 'PM' : 'AM';
      final min = date.minute.toString().padLeft(2, '0');
      return '${months[date.month - 1]} ${date.day}, ${date.year}, $hour:$min $ampm';
    } catch (e) {
      return null;
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
    // Use only project description; do not show owner/client name on the card
    final rawDescription = project['description'] ?? 'Hardware design project';
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
    // Prefer last_run_at (from stages) for last run; fallback to last_run / updated_at
    final lastRunAtRaw = project['last_run_at']?.toString() ?? project['last_run']?.toString() ?? project['updated_at']?.toString();
    final lastRun = _formatTimeAgo(lastRunAtRaw);
    final lastRunDateFormatted = lastRunAtRaw != null && lastRunAtRaw.isNotEmpty
        ? _formatLastRunDate(lastRunAtRaw)
        : null;
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

    void handleProjectAdminClick() {
      if (projectName == null) return;
      ref.read(viewScreenParamsProvider.notifier).state = ViewScreenParams(
        project: projectName!,
        viewType: 'management',
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ViewScreen(),
        ),
      );
    }

    final userRole = ref.read(authProvider).user?['role'];
    
    // Determine project identifier - prefer Zoho project ID for Zoho projects
    final projectIdentifier = project['zoho_project_id']?.toString() ?? 
                             project['id']?.toString() ?? 
                             projectName;
    
    // Check project-specific role (CAD, admin, etc.)
    return FutureBuilder<Map<String, dynamic>>(
      future: _checkProjectCadRole(projectIdentifier),
      builder: (context, snapshot) {
        // Get effective role and project-only role (project-specific if available, otherwise global)
        final effectiveRole = snapshot.hasData ? snapshot.data!['effectiveRole'] : userRole;
        final projectRole = snapshot.hasData ? snapshot.data!['projectRole'] : null;
        // Project-role admin (and not global admin/manager): only management view, no Setup button, open directly to management.
        // Managers (project_manager) always get dashboard on card tap, not management view.
        final isProjectAdminOnly = projectRole == 'admin' && userRole != 'admin' && userRole != 'project_manager';
        
        // Check if user is CAD engineer (global or project-specific)
        // Only CAD engineers should see Export to Linux button
        final isCadEngineerForProject = effectiveRole == 'cad_engineer' || 
                                        userRole == 'cad_engineer';
        
        // Check if user is NOT a CAD engineer and NOT project-role admin (project admin has no Setup)
        // Setup button is for non-CAD roles except global admin and project-role admin
        final isEngineerForProject = effectiveRole != 'cad_engineer' && 
                                     userRole != 'cad_engineer' &&
                                     userRole != 'admin' &&
                                     !isProjectAdminOnly;
        
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
          lastRunDateFormatted: lastRunDateFormatted,
          latestRunStatus: project['latest_run_status']?.toString(),
          progress: progress,
          isRunning: isRunning,
          runDirectory: runDirectory,
          runDirectories: runDirectories,
          onTap: isProjectAdminOnly ? handleProjectAdminClick : handleProjectClick,
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
          'color': isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          'icon': Icons.access_time_rounded,
          'textColor': isDark ? Colors.grey.shade200 : Colors.grey.shade800,
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
          'color': isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          'icon': Icons.access_time_rounded,
          'textColor': isDark ? Colors.grey.shade200 : Colors.grey.shade800,
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
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Dialog(
          backgroundColor: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _kCardAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.sync_rounded, size: 32, color: _kCardAccent),
                ),
                const SizedBox(height: 20),
                Text(
                  'Loading sync preview…',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Fetching project and members from Zoho',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(_kCardAccent),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Dialog(
          backgroundColor: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 480,
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.all(28),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _kCardAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _kCardAccent.withOpacity(0.5)),
                        ),
                        child: Icon(Icons.sync_rounded, size: 24, color: _kCardAccent),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sync project from Zoho',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Review and confirm to sync members',
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurface.withOpacity(0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.folder_rounded, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Project',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                projectName,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (existingProject)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Existing project will be updated',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (techLine != null || startLine != null || targetLine != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.dividerColor.withOpacity(0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (techLine != null)
                            Text(techLine, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface)),
                          if (startLine != null) ...[
                            if (techLine != null) const SizedBox(height: 4),
                            Text(startLine, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.8))),
                          ],
                          if (targetLine != null) ...[
                            if (techLine != null || startLine != null) const SizedBox(height: 2),
                            Text(targetLine, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.8))),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Domains',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          domainSummary,
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _kCardAccent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kCardAccent.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.people_rounded, size: 20, color: _kCardAccent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Project members from Zoho will be added to this project. Blocks and corresponding users will also be added so they can access the project.',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface.withOpacity(0.9),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        icon: const Icon(Icons.sync_rounded, size: 18),
                        label: const Text('Sync'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kCardAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;

    // Show "Syncing..." dialog so user sees that sync is in progress
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return Dialog(
            backgroundColor: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _kCardAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.sync_rounded, size: 32, color: _kCardAccent),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Syncing…',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Adding project members, blocks, and users from Zoho',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(_kCardAccent),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    try {
      final result = await _apiService.syncZohoProjectMembersByZohoId(
        zohoProjectId: zohoProjectId,
        portalId: effectivePortalId,
        zohoProjectName: zohoProjectName,
        token: token,
      );
      if (mounted) {
        Navigator.of(context).pop(); // Close syncing dialog
        _showSyncResultDialog(context, result, zohoProjectName ?? 'Project');
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close syncing dialog
        _showSyncResultDialog(context, null, zohoProjectName ?? 'Project', error: e.toString());
      }
    }
  }

  /// Shows a proper dialog with the complete sync result (same style as confirm sync dialog).
  void _showSyncResultDialog(
    BuildContext context,
    Map<String, dynamic>? result,
    String projectName, {
    String? error,
  }) {
    final hasError = error != null && error.isNotEmpty;
    final updated = result != null && result['updatedAssignments'] is int ? result['updatedAssignments'] as int : 0;
    final created = result != null && result['createdUsers'] is int ? result['createdUsers'] as int : 0;
    final errorsList = result != null && result['errors'] is List ? result['errors'] as List : <dynamic>[];
    final errCount = errorsList.length;

    showDialog(
      context: context,
      builder: (ctx) {
        final t = Theme.of(ctx);
        return Dialog(
          backgroundColor: t.colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 480,
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.all(28),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: hasError
                              ? Colors.red.withOpacity(0.12)
                              : (errCount > 0 ? Colors.orange : _kCardAccent).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: hasError
                                ? Colors.red.withOpacity(0.5)
                                : (errCount > 0 ? Colors.orange : _kCardAccent).withOpacity(0.5),
                          ),
                        ),
                        child: Icon(
                          hasError ? Icons.error_rounded : (errCount > 0 ? Icons.warning_rounded : Icons.check_circle_rounded),
                          size: 24,
                          color: hasError ? Colors.red : (errCount > 0 ? Colors.orange : _kCardAccent),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hasError ? 'Sync failed' : (errCount > 0 ? 'Sync completed with issues' : 'Sync completed'),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: t.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              projectName,
                              style: TextStyle(
                                fontSize: 13,
                                color: t.colorScheme.onSurface.withOpacity(0.55),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (hasError) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        error,
                        style: TextStyle(fontSize: 13, color: Colors.red.shade900),
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: t.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.dividerColor.withOpacity(0.5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _syncResultRow(ctx: ctx, icon: Icons.people_rounded, label: 'Project members added', value: '$updated'),
                          const SizedBox(height: 10),
                          _syncResultRow(ctx: ctx, icon: Icons.person_add_rounded, label: 'New users created', value: '$created'),
                          const SizedBox(height: 10),
                          _syncResultRow(ctx: ctx, icon: Icons.view_module_rounded, label: 'Blocks synced', value: 'Yes'),
                        ],
                      ),
                    ),
                    if (errCount > 0) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.warning_rounded, size: 18, color: Colors.orange.shade800),
                                const SizedBox(width: 8),
                                Text(
                                  '$errCount item${errCount == 1 ? '' : 's'} had issues',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange.shade900),
                                ),
                              ],
                            ),
                            if (errorsList.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              ...(errorsList.take(5).map((e) {
                                final map = e is Map ? e : <String, dynamic>{};
                                final email = map['email']?.toString() ?? '—';
                                final errMsg = map['error']?.toString() ?? '—';
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '$email: $errMsg',
                                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              })),
                              if (errorsList.length > 5)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '... and ${errorsList.length - 5} more',
                                    style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kCardAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _syncResultRow({required BuildContext ctx, required IconData icon, required String label, required String value}) {
    final theme = Theme.of(ctx);
    return Row(
      children: [
        Icon(icon, size: 18, color: _kCardAccent.withOpacity(0.9)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.85)),
          ),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
        ),
      ],
    );
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
            projectIdOrName: project['id'] ?? project['name'] ?? projectName,
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
  final String? lastRunDateFormatted;
  final String? latestRunStatus;
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
    this.lastRunDateFormatted,
    this.latestRunStatus,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statusColor = widget.statusConfig['color'] as Color;

    return TooltipTheme(
      data: TooltipThemeData(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        textStyle: TextStyle(
          color: Theme.of(context).colorScheme.onInverseSurface,
          fontSize: 12,
        ),
      ),
      child: Tooltip(
        message: 'Click to open this project. View blocks, runs, and dashboards.',
        preferBelow: false,
        child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
          height: double.infinity,
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isHovered ? _kCardAccent.withOpacity(0.4) : theme.dividerColor.withOpacity(0.6),
              width: _isHovered ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
                blurRadius: _isHovered ? 16 : 8,
                offset: Offset(0, _isHovered ? 4 : 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.max,
              children: [
                // Top accent bar by status
                Container(
                  height: 4,
                  color: statusColor,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header: icon + project name/status + actions at right end
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [_kCardAccent, _kCardAccentSecondary],
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: _kCardAccent.withOpacity(0.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.developer_board,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.projectName,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurface,
                                      letterSpacing: -0.3,
                                    ) ?? TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: statusColor.withOpacity(0.4), width: 1),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          widget.statusConfig['icon'] as IconData,
                                          size: 12,
                                          color: statusColor,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          widget.status,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: statusColor,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Actions at right end of card
                            if (widget.canSyncProjects || widget.canSetup || widget.canExportToLinux) ...[
                              const SizedBox(width: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                alignment: WrapAlignment.end,
                                children: [
                                  if (widget.canSyncProjects) _actionChip(context, Icons.sync_rounded, 'Sync', widget.onSyncProjects!, accent: _kCardAccent, tooltip: 'Sync members and blocks from Zoho to this project.'),
                                  if (widget.canSetup) _actionChip(context, Icons.settings_rounded, 'Experiment Setup', widget.onSetup!, tooltip: 'Create experiment run: choose block and enter experiment name.'),
                                  if (widget.canExportToLinux)
                                    (widget.isExported || widget.isSetupCompleted)
                                        ? Tooltip(
                                            message: 'Exported to Linux. You can run flows.',
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF10B981).withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.check_circle_rounded, size: 14, color: Colors.green.shade700),
                                                  const SizedBox(width: 5),
                                                  Text('Exported', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade700)),
                                                ],
                                              ),
                                            ),
                                          )
                                        : _actionChip(context, Icons.file_download_rounded, 'Project Setup', widget.onExportToLinux!, accent: _kCardAccent, tooltip: 'Export project to Linux (required before running flows).'),
                                ],
                              ),
                            ],
                          ],
                        ),
                        if (widget.description.isNotEmpty && widget.description != 'Hardware design project') ...[
                          const SizedBox(height: 12),
                          Text(
                            widget.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.65),
                              height: 1.35,
                            ) ?? TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface.withOpacity(0.65),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 16),
                        // Meta row: gate count, technology
                        Wrap(
                          spacing: 16,
                          runSpacing: 10,
                          children: [
                            if (widget.gateCount != 'N/A')
                              _metaChip(
                                context,
                                Icons.grid_view_rounded,
                                widget.gateCount,
                                'Gates',
                              ),
                            _metaChip(
                              context,
                              Icons.memory,
                              widget.technology,
                              'Tech',
                              valueFontSize: 20,
                            ),
                          ],
                        ),
                        // Last run history: date, relative time, and status
                        const SizedBox(height: 12),
                        _buildLastRunSection(context, theme, statusColor),
                        if (widget.startDate != null || widget.targetDate != null) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              if (widget.startDate != null)
                                Expanded(
                                  child: _dateRow(context, Icons.play_circle_outline_rounded, 'Start', widget.startDate!),
                                ),
                              if (widget.targetDate != null)
                                Expanded(
                                  child: _dateRow(context, Icons.flag_outlined, 'Target', widget.targetDate!),
                                ),
                            ],
                          ),
                        ],
                        if (widget.runDirectories.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: _kCardAccent.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _kCardAccent.withOpacity(0.2)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.folder_rounded, size: 16, color: _kCardAccent),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.runDirectories.last,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      color: theme.colorScheme.onSurface.withOpacity(0.8),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (widget.isRunning) ...[
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Progress',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                              Text(
                                '${widget.progress.toInt()}%',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: (widget.progress / 100).clamp(0.0, 1.0),
                              backgroundColor: theme.colorScheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                              minHeight: 6,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Divider(height: 1, color: theme.dividerColor.withOpacity(0.6)),
                        const SizedBox(height: 14),
                        // Footer: Open project only (actions are in upper card)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Open project',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: _kCardAccent,
                              ) ?? TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _kCardAccent,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.arrow_forward_rounded, size: 18, color: _kCardAccent),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    ),
    );
  }

  Widget _buildLastRunSection(BuildContext context, ThemeData theme, Color statusColor) {
    final hasDate = widget.lastRunDateFormatted != null && widget.lastRunDateFormatted!.isNotEmpty;
    final hasStatus = widget.latestRunStatus != null && widget.latestRunStatus!.isNotEmpty;
    final runStatus = widget.latestRunStatus?.toLowerCase() ?? '';
    Color runStatusColor = theme.colorScheme.onSurface.withOpacity(0.6);
    String runStatusLabel = widget.latestRunStatus ?? '';
    if (runStatus == 'pass' || runStatus == 'completed' || runStatus == 'done') {
      runStatusColor = const Color(0xFF10B981);
      runStatusLabel = 'Pass';
    } else if (runStatus == 'fail' || runStatus == 'failed' || runStatus == 'error') {
      runStatusColor = const Color(0xFFEF4444);
      runStatusLabel = 'Failed';
    } else if (runStatus == 'running' || runStatus == 'in progress' || runStatus == 'active') {
      runStatusColor = theme.colorScheme.secondary;
      runStatusLabel = 'Running';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, size: 14, color: theme.colorScheme.onSurface.withOpacity(0.6)),
              const SizedBox(width: 6),
              Text(
                'Last run',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (hasDate || widget.lastRun != 'N/A') ...[
            Text(
              hasDate
                  ? '${widget.lastRunDateFormatted} · ${widget.lastRun}'
                  : widget.lastRun,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (hasStatus) const SizedBox(height: 6),
          ],
          if (hasStatus)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: runStatusColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: runStatusColor.withOpacity(0.4)),
              ),
              child: Text(
                runStatusLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: runStatusColor,
                ),
              ),
            ),
          if (!hasDate && widget.lastRun == 'N/A' && !hasStatus)
            Text(
              'No runs yet',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _metaChip(BuildContext context, IconData icon, String value, String? label, {double? valueFontSize}) {
    final theme = Theme.of(context);
    final fontSize = valueFontSize ?? 13.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: fontSize > 13 ? 15 : 14, color: theme.colorScheme.onSurface.withOpacity(0.5)),
        const SizedBox(width: 5),
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        if (label != null) ...[
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: valueFontSize != null ? 12 : 11,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ],
    );
  }

  Widget _dateRow(BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurface.withOpacity(0.5)),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.5), fontWeight: FontWeight.w500)),
            Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
          ],
        ),
      ],
    );
  }

  Widget _actionChip(BuildContext context, IconData icon, String label, VoidCallback onTap, {Color? accent, String? tooltip}) {
    final theme = Theme.of(context);
    final color = accent ?? theme.colorScheme.primary;
    final chip = Padding(
      padding: const EdgeInsets.only(left: 6.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: color.withOpacity(0.6)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 5),
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
    if (tooltip != null && tooltip.isNotEmpty) {
      return Tooltip(message: tooltip, child: chip);
    }
    return chip;
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
            
            // Check for run directory under /CX_PROJ (setup uses --base-path /CX_PROJ)
            // Look for: /CX_PROJ/{project}/pd/users/{username}/*
            final escapedProject = projectNameSanitized.replaceAll("'", "'\\''");
            final escapedUsername = actualUsername.replaceAll("'", "'\\''");
            final findRunDirCommand = "find /CX_PROJ/$escapedProject/pd/users/$escapedUsername -maxdepth 3 -type d 2>/dev/null | head -1 || echo ''";
            
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
            
            // If not found, construct expected path based on setup (CX_PROJ)
            if (runDirectory == null || runDirectory.isEmpty) {
              runDirectory = '/CX_PROJ/$projectNameSanitized/pd/users/$actualUsername';
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
        ref.read(errorHandlerProvider.notifier).showError(e, title: 'SSH Error');
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(_kCardAccent),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Running…',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final theme = Theme.of(context);
          return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: 520,
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header (match new UI: icon + title)
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kCardAccent.withOpacity(0.6)),
                      ),
                      child: Icon(Icons.lock_rounded, size: 24, color: _kCardAccent),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Password Required',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Enter sudo password to continue export',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface.withOpacity(0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
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
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Info message (new UI: purple tint)
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _kCardAccent.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _kCardAccent.withOpacity(0.3)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline_rounded, color: _kCardAccent, size: 24),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'The command requires sudo password to continue execution.',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.85),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              // Command display
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E1E),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.code_rounded, color: _kCardAccent.withOpacity(0.9), size: 20),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Command to Execute:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                                            fontSize: 13,
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
                              const SizedBox(height: 20),
                              // Password input (new UI: purple focus)
                              TextField(
                                controller: passwordController,
                                obscureText: true,
                                autofocus: true,
                                decoration: InputDecoration(
                                  labelText: 'Enter Sudo Password',
                                  hintText: 'Enter your password',
                                  prefixIcon: Icon(Icons.lock_outline_rounded, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: _kCardAccent, width: 1.5),
                                  ),
                                  filled: true,
                                  fillColor: theme.colorScheme.surface,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                // Actions (new UI: purple primary button)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: showOutput && !isCommandRunning
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kCardAccent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
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
                                      child: Text(
                                        'Cancel',
                                        style: TextStyle(
                                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
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
                                        backgroundColor: _kCardAccent,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        elevation: 0,
                                      ),
                                      icon: isSendingPassword
                                          ? SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                              ),
                                            )
                                          : const Icon(Icons.send_rounded, size: 18),
                                      label: Text(isSendingPassword ? 'Sending…' : 'Send Password'),
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
          ref.read(errorHandlerProvider.notifier).showError(e, title: 'SSH Error');
        }
      }
    } catch (e) {
      onComplete('Error sending password: $e', null);
      if (context.mounted) {
        ref.read(errorHandlerProvider.notifier).showError(e, title: 'SSH Error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header (match _SetupDialog: icon + title + close)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kCardAccent.withOpacity(0.6)),
                  ),
                  child: Icon(Icons.terminal_rounded, size: 24, color: _kCardAccent),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Project Setup',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Select domains and export to Linux',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface.withOpacity(0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: theme.colorScheme.onSurface.withOpacity(0.6)),
                  onPressed: _isRunning ? null : () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.surface,
                    side: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Project Name (read-only, same style as _SetupDialog)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.folder_rounded, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Project',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.projectName,
                          style: TextStyle(
                            fontSize: 15,
                            color: theme.colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Domain Selection
            Text(
              'Select Domains',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 12),
            
            if (widget.domains.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No domains available for this project',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface.withOpacity(0.75),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
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
                      activeColor: _kCardAccent,
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

            // Output/Error Display (match new style)
            if (_output != null || _error != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _error != null
                        ? Colors.red.shade300
                        : Colors.green.shade300,
                    width: 1.5,
                  ),
                ),
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(
                    _error ?? _output ?? '',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.4,
                      color: _error != null
                          ? Colors.red.shade900
                          : Colors.green.shade900,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],

            // Action Buttons (match _SetupDialog: purple primary, rounded)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_exportSuccess) ...[
                  TextButton(
                    onPressed: _isRunning ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                if (_exportSuccess)
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kCardAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text('Close'),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _isRunning ? null : _runCommand,
                    icon: _isRunning
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.play_arrow_rounded, size: 20),
                    label: Text(_isRunning ? 'Running…' : 'Run Export'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kCardAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
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
  final dynamic projectIdOrName;
  final String projectName;
  final List<Map<String, dynamic>> blocks;
  final ApiService apiService;
  final String? zohoProjectId;
  final Function(String runDirectory)? onRunDirectorySaved;

  const _SetupDialog({
    required this.projectIdOrName,
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
  final TextEditingController _rtlTagCreateNewController = TextEditingController();
  bool _isRunning = false;
  bool _isSuccess = false;
  String? _output;
  String? _error;
  String? _successProjectName;
  String? _successBlockName;
  String? _successExperimentName;
  String? _successRtlTag;
  String? _successRunDirectory;
  String? _successUsername;
  final GlobalKey _blockDropdownKey = GlobalKey();
  bool _blockDropdownOpen = false;
  OverlayEntry? _blockDropdownOverlay;
  List<String> _rtlTags = [];
  bool _rtlTagsLoading = false;
  bool _rtlTagCreateNew = true; // true = Create new, false = Use existing
  String? _selectedRtlTag; // when use existing: selected tag

  @override
  void dispose() {
    _blockDropdownOverlay?.remove();
    _experimentController.dispose();
    _rtlTagCreateNewController.dispose();
    super.dispose();
  }

  Future<void> _loadRtlTags() async {
    if (_selectedBlock == null) {
      setState(() {
        _rtlTags = [];
        _selectedRtlTag = null;
      });
      return;
    }
    setState(() => _rtlTagsLoading = true);
    try {
      final token = ref.read(authProvider).token;
      final list = await widget.apiService.getRtlTagsForBlock(
        projectIdOrName: widget.projectIdOrName,
        blockName: _selectedBlock!,
        token: token,
      );
      if (mounted) {
        setState(() {
          _rtlTags = list;
          _rtlTagsLoading = false;
          if (!_rtlTagCreateNew && list.isNotEmpty && (_selectedRtlTag == null || !list.contains(_selectedRtlTag))) {
            _selectedRtlTag = list.first;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() { _rtlTags = []; _rtlTagsLoading = false; });
    }
  }

  String _getEffectiveRtlTag() {
    if (_rtlTagCreateNew) {
      return _rtlTagCreateNewController.text.trim().toLowerCase();
    }
    return _selectedRtlTag ?? '';
  }

  void _closeBlockDropdown() {
    if (_blockDropdownOverlay != null) {
      _blockDropdownOverlay!.remove();
      _blockDropdownOverlay = null;
    }
    if (_blockDropdownOpen) {
      _blockDropdownOpen = false;
      if (mounted) setState(() {});
    }
  }

  void _toggleBlockDropdown() {
    if (_isRunning) return;
    if (_blockDropdownOpen) {
      _closeBlockDropdown();
      return;
    }
    _blockDropdownOpen = true;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_blockDropdownOpen) return;
      final renderBox = _blockDropdownKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) {
        _blockDropdownOpen = false;
        if (mounted) setState(() {});
        return;
      }
      final position = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      final theme = Theme.of(context);
      _blockDropdownOverlay = OverlayEntry(
        builder: (context) => Stack(
          children: [
            ModalBarrier(
              dismissible: true,
              onDismiss: _closeBlockDropdown,
            ),
            Positioned(
              left: position.dx,
              top: position.dy + size.height + 4,
              width: size.width,
              child: Material(
                elevation: 8,
                shadowColor: Colors.black26,
                borderRadius: BorderRadius.circular(12),
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kCardAccent, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    children: widget.blocks.map((block) {
                      final name = block['block_name']?.toString() ?? block['name']?.toString() ?? '';
                      final isSelected = _selectedBlock == name;
                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedBlock = name;
                            _rtlTagCreateNew = true;
                            _selectedRtlTag = null;
                            _rtlTagCreateNewController.clear();
                          });
                          _closeBlockDropdown();
                          _loadRtlTags();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: isSelected ? _kCardAccent : theme.colorScheme.onSurface,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      Overlay.of(context).insert(_blockDropdownOverlay!);
    });
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
      final experimentName = _experimentController.text.trim().toLowerCase();
      final rtlTag = _getEffectiveRtlTag();

      // Build command: echo "setup -proj ... -domain ... -block ... -exp ... -rtltag ..." | newgrp {project}
      final rtlTagEscaped = rtlTag.replaceAll('"', '\\"');
      final command = 'echo "setup -proj $sanitizedProjectName -domain $domainCode -block $sanitizedBlockName -exp $experimentName -rtltag $rtlTagEscaped" | newgrp $sanitizedProjectName';

      print('═══════════════════════════════════════════════════════════');
      print('🚀 EXECUTING SETUP COMMAND:');
      print('   Command: $command');
      print('   Project (original): $projectName');
      print('   Project (sanitized): $sanitizedProjectName');
      print('   Domain: $domainCode');
      print('   Block (original): $blockName');
      print('   Block (sanitized): $sanitizedBlockName');
      print('   Experiment: $experimentName');
      print('   RTL tag: $rtlTag');
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
      final exitCode = result['exitCode'] as int?;
      final isSuccess = result['success'] == true && (exitCode == 0 || (exitCode == null && result['stdout']?.toString().toLowerCase().contains('done.') == true));
      String? savedRunDirectory;
      String? savedUsername;
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
          
          final rtlTagForPath = _getEffectiveRtlTag();
          
          // Step 2: Search for the directory that was just created
          // Setup uses --base-path /CX_PROJ, so run dirs are under /CX_PROJ/{project}/pd/users/...
          // Path includes RTL tag when set: /CX_PROJ/{project}/pd/users/{username}/{block}/{rtl_tag}/{experiment} or .../{block}/{experiment}
          print('   Step 2: Searching for directory created by setup command...');
          const runDirBasePath = '/CX_PROJ';
          
          // Escape variables for shell command
          final escapedProject = sanitizedProjectName.replaceAll("'", "'\\''");
          final escapedBlock = sanitizedBlockName.replaceAll("'", "'\\''");
          final escapedExperiment = experimentName.replaceAll("'", "'\\''");
          final escapedUsername = actualUsername.replaceAll("'", "'\\''");
          final escapedRtlTag = rtlTagForPath.replaceAll("'", "'\\''");
          
          // Construct expected path (with rtl_tag segment when non-empty) — use CX_PROJ to match setup command
          final expectedPath = rtlTagForPath.isEmpty
              ? '$runDirBasePath/$escapedProject/pd/users/$escapedUsername/$escapedBlock/$escapedExperiment'
              : '$runDirBasePath/$escapedProject/pd/users/$escapedUsername/$escapedBlock/$escapedRtlTag/$escapedExperiment';
          
          // Command to find the directory: try expected path first, then search under CX_PROJ
          final findPathCommand = "EXPECTED_PATH='$expectedPath'; if [ -d \"\$EXPECTED_PATH\" ]; then echo \"\$EXPECTED_PATH\"; else find $runDirBasePath/$escapedProject/pd/users/$escapedUsername -type d -name '$escapedExperiment' -mmin -5 2>/dev/null | head -1 || find $runDirBasePath/$escapedProject/pd/users/$escapedUsername -type d -name '$escapedExperiment' 2>/dev/null | head -1; fi";
          
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
            // Last resort: construct path with rtl_tag when set — use /CX_PROJ to match setup command
            actualRunDirectory = rtlTagForPath.isEmpty
                ? '/CX_PROJ/$sanitizedProjectName/pd/users/$actualUsername/$sanitizedBlockName/$experimentName'
                : '/CX_PROJ/$sanitizedProjectName/pd/users/$actualUsername/$sanitizedBlockName/$rtlTagForPath/$experimentName';
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
          
          final rtlTag = _getEffectiveRtlTag();
          await widget.apiService.saveRunDirectory(
            projectName: projectName,
            blockName: blockName,
            experimentName: experimentName,
            runDirectory: actualRunDirectory,
            username: actualUsername,
            rtlTag: rtlTag.isEmpty ? null : rtlTag,
            zohoProjectId: widget.zohoProjectId,
            domainCode: domainCode,
            token: token,
          );
          savedRunDirectory = actualRunDirectory;
          savedUsername = actualUsername;
          print('✅ Run directory path saved successfully');
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
          _successProjectName = projectName;
          _successBlockName = blockName;
          _successExperimentName = experimentName;
          _successRtlTag = _getEffectiveRtlTag().isEmpty ? null : _getEffectiveRtlTag();
          _successRunDirectory = savedRunDirectory;
          _successUsername = savedUsername;
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
          // Keep dialog open and show success info card (no auto-close)
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
        ref.read(errorHandlerProvider.notifier).showError(e, title: 'SSH Error');
      }
    }
  }

  Widget _buildSuccessInfoRow(ThemeData theme, String label, String value) {
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
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withOpacity(0.5),
                letterSpacing: 0.3,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withOpacity(0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String labelText,
    String? hintText,
    Widget? prefixIcon,
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: prefixIcon,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: compact ? 12 : 14,
      ),
      filled: true,
      fillColor: theme.colorScheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _kCardAccent, width: 1.5),
      ),
      labelStyle: TextStyle(
        fontSize: 12,
        color: theme.colorScheme.onSurface.withOpacity(0.6),
        fontWeight: FontWeight.w500,
      ),
      hintStyle: TextStyle(
        fontSize: 15,
        color: theme.colorScheme.onSurface.withOpacity(0.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kCardAccent.withOpacity(0.6)),
                  ),
                  child: Icon(Icons.science_rounded, size: 24, color: _kCardAccent),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Setup Experiment',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Choose block and enter experiment name',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface.withOpacity(0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: theme.colorScheme.onSurface.withOpacity(0.6)),
                  onPressed: _isRunning ? null : () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.surface,
                    side: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // While running show simple "Running......." UI; else show full form
            if (_isRunning)
              Container(
                constraints: const BoxConstraints(minHeight: 200),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(_kCardAccent),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Running setup…',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
            // Project Name (read-only, same style as block field)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.folder_rounded, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Project',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.projectName,
                          style: TextStyle(
                            fontSize: 15,
                            color: theme.colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Block Selection Dropdown
            if (widget.blocks.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No blocks available. Sync blocks from Zoho (admin) or ask an admin to add blocks.',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface.withOpacity(0.75),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              GestureDetector(
                key: _blockDropdownKey,
                onTap: _toggleBlockDropdown,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _blockDropdownOpen ? _kCardAccent : theme.dividerColor.withOpacity(0.5),
                      width: _blockDropdownOpen ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.view_module_rounded,
                        size: 18,
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              'Block name',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedBlock ?? 'Select a block',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _selectedBlock != null
                                      ? theme.colorScheme.onSurface
                                      : theme.colorScheme.onSurface.withOpacity(0.5),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _blockDropdownOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: _kCardAccent,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 18),

            // RTL Tag: two clear options — Create new | Use existing
            if (_selectedBlock != null) ...[
              Text(
                'RTL tag',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withOpacity(0.85),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _isRunning ? null : () => setState(() {
                        _rtlTagCreateNew = true;
                        _rtlTagCreateNewController.clear();
                      }),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        decoration: BoxDecoration(
                          color: _rtlTagCreateNew ? _kCardAccent.withOpacity(0.12) : theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _rtlTagCreateNew ? _kCardAccent : theme.dividerColor.withOpacity(0.5),
                            width: _rtlTagCreateNew ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.add_circle_outline_rounded,
                              size: 22,
                              color: _rtlTagCreateNew ? _kCardAccent : theme.colorScheme.onSurface.withOpacity(0.5),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Create new RTL tag',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _rtlTagCreateNew ? _kCardAccent : theme.colorScheme.onSurface.withOpacity(0.8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: _isRunning ? null : () => setState(() {
                        _rtlTagCreateNew = false;
                        if (_rtlTags.isNotEmpty) _selectedRtlTag = _rtlTags.first;
                      }),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        decoration: BoxDecoration(
                          color: !_rtlTagCreateNew ? _kCardAccent.withOpacity(0.12) : theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: !_rtlTagCreateNew ? _kCardAccent : theme.dividerColor.withOpacity(0.5),
                            width: !_rtlTagCreateNew ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.label_rounded,
                              size: 22,
                              color: !_rtlTagCreateNew ? _kCardAccent : theme.colorScheme.onSurface.withOpacity(0.5),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Use existing RTL tag',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: !_rtlTagCreateNew ? _kCardAccent : theme.colorScheme.onSurface.withOpacity(0.8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_rtlTagCreateNew)
                TextField(
                  controller: _rtlTagCreateNewController,
                  enabled: !_isRunning,
                  decoration: _inputDecoration(
                    labelText: 'New RTL tag name (lowercase only)',
                    hintText: 'e.g. v1, rtl_jan',
                    compact: true,
                    prefixIcon: Icon(Icons.edit_rounded, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  ),
                  style: TextStyle(fontSize: 15, color: theme.colorScheme.onSurface, fontWeight: FontWeight.w500),
                  inputFormatters: [
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      final lower = newValue.text.toLowerCase();
                      final allowed = lower.replaceAll(RegExp(r'[^a-z0-9_]'), '');
                      return TextEditingValue(
                        text: allowed,
                        selection: TextSelection.collapsed(offset: allowed.length),
                      );
                    }),
                  ],
                  onChanged: (_) => setState(() {}),
                )
              else
                _rtlTagsLoading
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _kCardAccent)),
                          const SizedBox(width: 12),
                          Text('Loading RTL tags...', style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.6))),
                        ],
                      ),
                    )
                  : _rtlTags.isEmpty
                    ? Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'No RTL tags yet for this block. Select "Create new RTL tag" above.',
                                style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.7)),
                              ),
                            ),
                          ],
                        ),
                      )
                    : DropdownButtonFormField<String>(
                        value: _selectedRtlTag ?? (_rtlTags.isNotEmpty ? _rtlTags.first : null),
                        isExpanded: true,
                        decoration: _inputDecoration(
                          labelText: 'Select existing RTL tag',
                          hintText: 'Choose one',
                          compact: true,
                          prefixIcon: Icon(Icons.label_rounded, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                        ),
                        items: _rtlTags.map((tag) => DropdownMenuItem(value: tag, child: Text(tag))).toList(),
                        onChanged: _isRunning ? null : (value) => setState(() => _selectedRtlTag = value),
                      ),
              const SizedBox(height: 18),
            ],

            // Experiment Name (lowercase only; same white + blue border style as block)
            TextField(
              controller: _experimentController,
              enabled: !_isRunning,
              decoration: _inputDecoration(
                labelText: 'Experiment name (lowercase only)',
                hintText: 'e.g. exp1, run_01',
                compact: true,
                prefixIcon: Icon(
                  Icons.edit_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
              style: TextStyle(
                fontSize: 15,
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              inputFormatters: [
                TextInputFormatter.withFunction((oldValue, newValue) {
                  final lower = newValue.text.toLowerCase();
                  final allowed = lower.replaceAll(RegExp(r'[^a-z0-9_]'), '');
                  return TextEditingValue(
                    text: allowed,
                    selection: TextSelection.collapsed(offset: allowed.length),
                  );
                }),
              ],
            ),
            const SizedBox(height: 24),

            // Success info card (what we did) when experiment setup done
            if (_isSuccess && (_successProjectName != null || _successBlockName != null)) ...[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.green.shade200, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 26),
                        const SizedBox(width: 10),
                        Text(
                          'Experiment setup completed',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildSuccessInfoRow(theme, 'Project', _successProjectName ?? '—'),
                    _buildSuccessInfoRow(theme, 'Block', _successBlockName ?? '—'),
                    _buildSuccessInfoRow(theme, 'Experiment', _successExperimentName ?? '—'),
                    if (_successRtlTag != null && _successRtlTag!.isNotEmpty)
                      _buildSuccessInfoRow(theme, 'RTL tag', _successRtlTag!),
                    if (_successUsername != null)
                      _buildSuccessInfoRow(theme, 'Username', _successUsername!),
                    if (_successRunDirectory != null && _successRunDirectory!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Run directory',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        _successRunDirectory!,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: theme.colorScheme.onSurface.withOpacity(0.9),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],

            // Output/Error Display (same white + border style)
            if (!_isSuccess && (_output != null || _error != null)) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _error != null
                        ? Colors.red.shade300
                        : Colors.green.shade300,
                    width: 1.5,
                  ),
                ),
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(
                    _error ?? _output ?? '',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.4,
                      color: _error != null
                          ? Colors.red.shade900
                          : Colors.green.shade900,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],
                  ],
                ),
              ),
            ),
            // Action Buttons (outside scroll so always visible)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_isSuccess) ...[
                  TextButton(
                    onPressed: _isRunning ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                if (_isSuccess)
                  ElevatedButton(
                    onPressed: () {
                      if (widget.onRunDirectorySaved != null && _successRunDirectory != null) {
                        widget.onRunDirectorySaved!(_successRunDirectory!);
                      }
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kCardAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text('Done'),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: (_isRunning || widget.blocks.isEmpty) ? null : _runSetup,
                    icon: _isRunning
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.play_arrow_rounded, size: 20),
                    label: Text(_isRunning ? 'Running…' : 'Run Setup'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kCardAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
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
