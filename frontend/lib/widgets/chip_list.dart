import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/dashboard_provider.dart';

class ChipList extends ConsumerWidget {
  const ChipList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chipsAsync = ref.watch(chipsProvider);

    return chipsAsync.when(
      data: (chips) {
        if (chips.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('No chips found')),
            ),
          );
        }

        return SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: chips.length,
            itemBuilder: (context, index) {
              final chip = chips[index];
              return SizedBox(
                width: 300,
                child: Card(
                  margin: const EdgeInsets.only(right: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                chip['name'] ?? 'Unknown',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Chip(
                              label: Text(chip['status'] ?? 'unknown'),
                              backgroundColor: _getStatusColor(chip['status']),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (chip['architecture'] != null)
                          Text(
                            'Architecture: ${chip['architecture']}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        if (chip['process_node'] != null)
                          Text(
                            'Process: ${chip['process_node']}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        if (chip['description'] != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            chip['description'],
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
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
      case 'production':
        return Colors.green;
      case 'design':
        return Colors.orange;
      case 'testing':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}









