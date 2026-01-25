import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/stat_card.dart';
import '../widgets/dashboard_charts.dart';
import '../widgets/project_list.dart';
import '../widgets/engineer_list.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardState = ref.watch(dashboardProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // Light grey background
      body: dashboardState.when(
        data: (stats) => RefreshIndicator(
          onRefresh: () => ref.read(dashboardProvider.notifier).refresh(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header (optional if not covered by MainNavigation)
                Text(
                  'Dashboard Overview',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Welcome back, here is your project summary',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 32),

                // Statistics Cards
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Mobile vs Desktop layout
                    if (constraints.maxWidth < 800) {
                      return Column(
                        children: [
                          _buildStatRow(context, stats, isMobile: true),
                        ],
                      );
                    }
                    return _buildStatRow(context, stats, isMobile: false);
                  },
                ),
                
                const SizedBox(height: 32),

                // Charts Section
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 1100) {
                      return const Column(
                        children: [
                          ProjectTrendChart(),
                          SizedBox(height: 24),
                          DomainDistributionChart(),
                        ],
                      );
                    }
                    return const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: ProjectTrendChart(),
                        ),
                        SizedBox(width: 24),
                        Expanded(
                          flex: 1,
                          child: DomainDistributionChart(),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 32),
                
                // Recent Projects & Engineers
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 1200) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recent Projects',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const ProjectList(),
                          const SizedBox(height: 32),
                          Text(
                            'Engineers',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Card(
                            color: Colors.white,
                            surfaceTintColor: Colors.white,
                            child: EngineerList()
                          ),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Recent Projects',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1A1A1A),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const ProjectList(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Engineers',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1A1A1A),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Card(
                                color: Colors.white,
                                surfaceTintColor: Colors.white,
                                child: EngineerList()
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Error Loading Dashboard',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString().contains('Cannot connect to backend') || 
                  error.toString().contains('server is running')
                    ? 'Backend server is not running.\n\nPlease start the backend server:\ncd backend\nnpm run dev'
                    : error.toString(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => ref.read(dashboardProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Create feature coming soon')),
          );
        },
        backgroundColor: Colors.purple.shade600,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildStatRow(BuildContext context, Map<String, dynamic> stats, {required bool isMobile}) {
    final projectStats = stats['projects'] ?? {
      'total': 0,
      'running': 0,
      'completed': 0,
      'failed': 0,
    };

    final children = [
      Expanded(
        flex: isMobile ? 0 : 1,
        child: StatCard(
          title: 'Total Projects',
          value: projectStats['total'].toString(),
          icon: Icons.folder_special,
          color: Colors.blue,
        ),
      ),
      SizedBox(width: isMobile ? 0 : 16, height: isMobile ? 16 : 0),
      Expanded(
        flex: isMobile ? 0 : 1,
        child: StatCard(
          title: 'Running',
          value: (projectStats['running'] ?? 0).toString(),
          icon: Icons.play_circle_outline,
          color: Colors.orange,
        ),
      ),
      SizedBox(width: isMobile ? 0 : 16, height: isMobile ? 16 : 0),
      Expanded(
        flex: isMobile ? 0 : 1,
        child: StatCard(
          title: 'Completed',
          value: (projectStats['completed'] ?? 0).toString(),
          icon: Icons.check_circle_outline,
          color: Colors.green,
        ),
      ),
      SizedBox(width: isMobile ? 0 : 16, height: isMobile ? 16 : 0),
      Expanded(
        flex: isMobile ? 0 : 1,
        child: StatCard(
          title: 'Failed',
          value: (projectStats['failed'] ?? 0).toString(),
          icon: Icons.error_outline,
          color: Colors.red,
        ),
      ),
    ];

    if (isMobile) {
      return Column(children: children);
    }
    return Row(children: children);
  }
}

