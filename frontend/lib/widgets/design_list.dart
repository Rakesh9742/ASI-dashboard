import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/dashboard_provider.dart';

class DesignList extends ConsumerWidget {
  const DesignList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final designsAsync = ref.watch(designsProvider);

    return designsAsync.when(
      data: (designs) {
        if (designs.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('No designs found')),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: designs.length > 5 ? 5 : designs.length,
          itemBuilder: (context, index) {
            final design = designs[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _getStatusColor(design['status']),
                  child: const Icon(Icons.design_services, color: Colors.white),
                ),
                title: Text(design['name'] ?? 'Unknown'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (design['chip_name'] != null)
                      Text('Chip: ${design['chip_name']}'),
                    if (design['design_type'] != null)
                      Text('Type: ${design['design_type']}'),
                  ],
                ),
                trailing: Chip(
                  label: Text(design['status'] ?? 'unknown'),
                  backgroundColor: _getStatusColor(design['status']),
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Error: $error'),
        ),
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'in_progress':
        return Colors.blue;
      case 'draft':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}
































