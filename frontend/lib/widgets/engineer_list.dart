import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/dashboard_provider.dart';

class EngineerList extends ConsumerWidget {
  const EngineerList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardState = ref.watch(dashboardProvider);
    // Trigger load if not already loading/loaded
    final notifier = ref.read(dashboardProvider.notifier);
    if (!dashboardState.isLoading && !dashboardState.hasValue) {
      notifier.loadStats();
    }

    return dashboardState.when(
      data: (stats) {
        final allUsers = stats['engineers']?['list'] as List<dynamic>? ?? [];
        
        // Filter to only show engineers (double-check in case provider didn't filter)
        final engineers = allUsers.where((user) => 
          user['role']?.toString().toLowerCase() == 'engineer'
        ).toList();

        if (engineers.isEmpty) {
          // If empty, it might be permission issue or no engineers.
          // Don't show "Error" but just "No engineers found or access denied" or hidden.
          // User asked to "show information", so a message is better than nothing.
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('No engineers found')),
            ),
          );
        }

        // Limit to 5 or 10? User said "information for the engineers we have". 
        // Showing all might be too much if there are many. Let's show up to 10.
        final displayEngineers = engineers.take(10).toList();

        return Column(
          children: [
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayEngineers.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final user = displayEngineers[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.shade50,
                    child: Text(
                      (user['full_name'] ?? user['username'] ?? 'U')[0].toUpperCase(),
                      style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(
                    user['full_name'] ?? user['username'] ?? 'Unknown User',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    user['email'] ?? '',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  trailing: Container(
                     padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                     decoration: BoxDecoration(
                       color: Colors.grey.shade100,
                       borderRadius: BorderRadius.circular(12),
                       border: Border.all(color: Colors.grey.shade300),
                     ),
                     child: Text(
                       user['role'] ?? 'User',
                       style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                     ),
                  ),
                );
              },
            ),
            if (engineers.length > 10)
               Padding(
                 padding: const EdgeInsets.all(8.0),
                 child: TextButton(onPressed: (){}, child: Text('View All (${engineers.length})')),
               ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text('Error loading engineers: $error'),
    );
  }
}
