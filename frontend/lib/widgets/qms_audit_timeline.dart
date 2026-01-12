import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class QmsAuditTimeline extends StatelessWidget {
  final List<dynamic> history;

  const QmsAuditTimeline({
    super.key,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(
            child: Text(
              'No history available',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Audit Trail',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...history.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isLast = index == history.length - 1;

              return _buildTimelineItem(
                context,
                item,
                isLast,
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineItem(
    BuildContext context,
    dynamic item,
    bool isLast,
  ) {
    final actionType = item['action_type'] ?? 'unknown';
    final actionData = _getActionData(actionType);
    final timestamp = item['created_at'];
    final username = item['username'] ?? 'Unknown';
    final fullName = item['full_name'] ?? username;
    final actionDetails = item['action_details'];

    DateTime? dateTime;
    if (timestamp != null) {
      try {
        dateTime = DateTime.parse(timestamp);
      } catch (e) {
        // Ignore parse errors
      }
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline line
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: actionData['color'],
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 2,
                  ),
                ),
                child: Icon(
                  actionData['icon'],
                  size: 12,
                  color: Colors.white,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: Colors.grey.shade300,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          actionData['label'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (dateTime != null)
                        Text(
                          DateFormat('MMM dd, yyyy HH:mm').format(dateTime),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'By: $fullName ($username)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  if (actionDetails != null && actionDetails is Map) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _formatActionDetails(Map<String, dynamic>.from(actionDetails)),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getActionData(String actionType) {
    switch (actionType.toLowerCase()) {
      case 'fill_action':
        return {
          'label': 'Fill Action Executed',
          'color': Colors.blue,
          'icon': Icons.file_upload,
        };
      case 'comment_added':
        return {
          'label': 'Comment Added',
          'color': Colors.orange,
          'icon': Icons.comment,
        };
      case 'submitted':
        return {
          'label': 'Submitted for Approval',
          'color': Colors.green,
          'icon': Icons.send,
        };
      case 'approved':
        return {
          'label': 'Approved',
          'color': Colors.green.shade700,
          'icon': Icons.check_circle,
        };
      case 'rejected':
      case 'not_approved':
        return {
          'label': 'Rejected',
          'color': Colors.red,
          'icon': Icons.cancel,
        };
      case 'approver_assigned':
        return {
          'label': 'Approver Assigned',
          'color': Colors.purple,
          'icon': Icons.person_add,
        };
      case 'checklist_submitted':
        return {
          'label': 'Checklist Submitted',
          'color': Colors.teal,
          'icon': Icons.checklist,
        };
      default:
        return {
          'label': actionType.replaceAll('_', ' ').toUpperCase(),
          'color': Colors.grey,
          'icon': Icons.info,
        };
    }
  }

  String _formatActionDetails(Map<String, dynamic> details) {
    final parts = <String>[];
    
    if (details.containsKey('report_path')) {
      parts.add('Report: ${details['report_path']}');
    }
    if (details.containsKey('rows_count')) {
      parts.add('Rows: ${details['rows_count']}');
    }
    if (details.containsKey('comments')) {
      parts.add('Comments: ${details['comments']}');
    }
    if (details.containsKey('approver_id')) {
      parts.add('Approver ID: ${details['approver_id']}');
    }
    if (details.containsKey('updates')) {
      final updates = details['updates'] as Map?;
      if (updates != null) {
        final updateParts = <String>[];
        if (updates.containsKey('fix_details')) {
          updateParts.add('Fix Details');
        }
        if (updates.containsKey('engineer_comments')) {
          updateParts.add('Engineer Comments');
        }
        if (updateParts.isNotEmpty) {
          parts.add('Updated: ${updateParts.join(", ")}');
        }
      }
    }

    return parts.isEmpty ? 'No details' : parts.join('\n');
  }
}

