import 'package:flutter/material.dart';

class QmsStatusBadge extends StatelessWidget {
  final String status;

  const QmsStatusBadge({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final statusData = _getStatusData(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: statusData['color'].withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: statusData['color'].withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            statusData['icon'],
            size: 12,
            color: statusData['color'],
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              statusData['label'],
              style: TextStyle(
                color: statusData['color'],
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.visible,
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getStatusData(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return {
          'label': 'Pending',
          'color': Colors.grey,
          'icon': Icons.pending,
        };
      case 'in_review':
        return {
          'label': 'In Review',
          'color': Colors.blue,
          'icon': Icons.visibility,
        };
      case 'fixed':
        return {
          'label': 'Fixed',
          'color': Colors.orange,
          'icon': Icons.build,
        };
      case 'submitted_for_approval':
        return {
          'label': 'Submitted for Approval',
          'color': Colors.orange,
          'icon': Icons.pending_actions,
        };
      case 'submitted':
        return {
          'label': 'Submitted',
          'color': Colors.green,
          'icon': Icons.check_circle,
        };
      case 'approved':
        return {
          'label': 'Approved',
          'color': Colors.green.shade700,
          'icon': Icons.verified,
        };
      case 'not_approved':
      case 'rejected':
        return {
          'label': 'Rejected',
          'color': Colors.red,
          'icon': Icons.cancel,
        };
      case 'draft':
      default:
        return {
          'label': 'Draft',
          'color': Colors.grey.shade600,
          'icon': Icons.edit,
        };
    }
  }
}

