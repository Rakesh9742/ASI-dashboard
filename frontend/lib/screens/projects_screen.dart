import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../providers/tab_provider.dart';
import 'main_navigation_screen.dart';

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

  Future<void> _loadProjects() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final token = ref.read(authProvider).token;
      if (token == null) {
        throw Exception('No authentication token');
      }

      // Fetch projects from Zoho
      final response = await _apiService.getZohoProjects(token: token);
      if (mounted) {
        setState(() {
          _projects = List<Map<String, dynamic>>.from(response['projects'] ?? []);
          // If no projects, show empty list (will display "No projects found")
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
    return _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title
                          Text(
                            'Projects',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Select a project to open',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Summary Cards
                          _buildSummaryCards(stats),
                          const SizedBox(height: 24),

                          // Search Bar
                          _buildSearchBar(),
                          const SizedBox(height: 24),

                          // Projects Grid
                          _buildProjectsGrid(filteredProjects),
                        ],
      ),
    );
  }

  Widget _buildSummaryCards(Map<String, int> stats) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard('Total Projects', stats['total']!.toString(), Colors.grey.shade900),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard('Running', stats['running']!.toString(), const Color(0xFF14B8A6)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard('Completed', stats['completed']!.toString(), const Color(0xFF10B981)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard('Failed', stats['failed']!.toString(), const Color(0xFFEF4444)),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
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
          const SizedBox(height: 4),
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
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
          prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildProjectsGrid(List<Map<String, dynamic>> projects) {
    if (projects.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48.0),
          child: Text(
            _searchQuery.isEmpty ? 'No projects found' : 'No projects match your search',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
        childAspectRatio: 1.35,
      ),
      itemCount: projects.length,
      itemBuilder: (context, index) {
        return _buildProjectCard(projects[index]);
      },
    );
  }

  String _getProjectStatus(Map<String, dynamic> project) {
    final status = (project['status'] ?? '').toString().toUpperCase();
    if (status == 'RUNNING' || status == 'IN_PROGRESS') {
      return 'RUNNING';
    } else if (status == 'FAILED' || status == 'ERROR') {
      return 'FAILED';
    }
    return 'IDLE';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'RUNNING':
        return Colors.blue.shade600;
      case 'FAILED':
        return Colors.red.shade600;
      default:
        return Colors.grey.shade600;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'RUNNING':
        return Icons.play_circle_filled;
      case 'FAILED':
        return Icons.error;
      default:
        return Icons.access_time;
    }
  }

  String _formatTimeAgo(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inMinutes < 60) {
        return '${difference.inMinutes} minutes ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
      } else {
        return 'about ${(difference.inDays / 7).floor()} week${(difference.inDays / 7).floor() > 1 ? 's' : ''} ago';
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
    final statusColor = _getStatusColor(status);
    final statusIcon = _getStatusIcon(status);
    final projectName = project['name'] ?? 'Unnamed Project';
    final rawDescription = project['description'] ?? project['client'] ?? 'Hardware design project';
    final description = _stripHtmlTags(rawDescription.toString());
    final gateCount = project['gate_count'] ?? project['gateCount'] ?? 'N/A';
    final technology = project['technology'] ?? project['technology_node'] ?? 'Sky130 PDK';
    final lastRun = _formatTimeAgo(project['last_run']?.toString() ?? project['updated_at']?.toString());
    final progressValue = project['progress'];
    final progress = progressValue != null 
        ? (progressValue is num ? progressValue.toDouble() : double.tryParse(progressValue.toString()) ?? 0.0)
        : (status == 'RUNNING' ? 65.0 : 0.0); // Default to 65% for running projects if no progress data
    final isRunning = status == 'RUNNING';

    return InkWell(
      onTap: () {
        // Open project in a tab
        ref.read(tabProvider.notifier).openProject(project);
        // Switch to show the project tab
        ref.read(currentNavTabProvider.notifier).state = 'project_tab';
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with Icon and Status Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Container(
                  width: 48,
                  height: 48,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E96B1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.memory,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        statusIcon,
                        size: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                Text(
                        status,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Title
            Text(
              projectName,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            // Description
            Text(
              description.isEmpty ? 'Hardware design project' : description,
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
            // Details Row with gap
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gate Count',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        gateCount.toString(),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 60),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Technology',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 3),
                Text(
                        technology,
                  style: TextStyle(
                          fontSize: 18,
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
            const SizedBox(height: 12),
            // Last Run and Progress Section
            Text(
              'Last run: $lastRun',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            if (isRunning) ...[
              const SizedBox(height: 5),
              // Progress Label and Percentage Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Progress',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  Text(
                    '${progress.toInt()}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              // Progress Bar
              Container(
                width: double.infinity,
                height: 7,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (progress / 100).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E96B1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Click to open with border top
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor, width: 1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Click to open',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                Icon(
                  Icons.arrow_forward,
                    size: 13,
                    color: Theme.of(context).colorScheme.primary,
                ),
              ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

