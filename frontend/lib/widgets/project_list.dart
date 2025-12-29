import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/dashboard_provider.dart';

class ProjectList extends ConsumerWidget {
  const ProjectList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // We can get projects from the dashboard state since we already fetched them there
    final dashboardState = ref.watch(dashboardProvider);

    return dashboardState.when(
      data: (stats) {
        final projects = stats['projects']['list'] as List<dynamic>? ?? [];

        if (projects.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('No projects found')),
            ),
          );
        }

        // Show top 5 recent projects
        final recentProjects = List.from(projects)..sort((a, b) {
           // Sort by creation or start date descending if available
           // Assuming higher ID is newer if no date, or parsing start_date
           String? dateA = a['start_date'];
           String? dateB = b['start_date'];
           if (dateA != null && dateB != null) {
             return dateB.compareTo(dateA);
           }
           return (b['id'] ?? 0).compareTo(a['id'] ?? 0);
        });
        
        final displayProjects = recentProjects.take(5).toList();

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: displayProjects.length,
          itemBuilder: (context, index) {
            final project = displayProjects[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: Colors.indigo.shade50,
                  child: const Icon(Icons.folder_copy, color: Colors.indigo),
                ),
                title: Text(
                  project['name'] ?? 'Untitled Project',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (project['client'] != null)
                      Text('Client: ${project['client']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    Text(
                      'Tech: ${project['technology_node'] ?? 'N/A'}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(project['status'] ?? 'active').withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        (project['status'] ?? 'Active').toUpperCase(),
                        style: TextStyle(
                          color: _getStatusColor(project['status'] ?? 'active'),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (project['target_date'] != null)
                      Text(
                        project['target_date'],
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text('Error loading projects: $error'),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed': return Colors.green;
      case 'on_hold': return Colors.orange;
      case 'delayed': return Colors.red;
      case 'active': return Colors.blue;
      default: return Colors.blue;
    }
  }
}
