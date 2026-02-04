import 'package:flutter/material.dart';

// ASI Brand colors
const Color _kBrandPrimary = Color(0xFF6366F1);
const Color _kSuccessGreen = Color(0xFF10B981);
const Color _kDangerRed = Color(0xFFEF4444);
const Color _kWarningOrange = Color(0xFFF59E0B);

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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: statusData['color'].withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusData['color'].withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            statusData['icon'],
            size: 14,
            color: statusData['color'],
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              statusData['label'],
              style: TextStyle(
                color: statusData['color'],
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
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
          'color': Colors.grey.shade600,
          'icon': Icons.pending_outlined,
        };
      case 'pass':
        return {
          'label': 'Pass',
          'color': _kSuccessGreen,
          'icon': Icons.check_circle_rounded,
        };
      case 'fail':
        return {
          'label': 'Fail',
          'color': _kDangerRed,
          'icon': Icons.cancel_rounded,
        };
      case 'warn':
      case 'warning':
        return {
          'label': 'Warn',
          'color': _kWarningOrange,
          'icon': Icons.warning_rounded,
        };
      case 'skip':
      case 'skipped':
        return {
          'label': 'Skip',
          'color': Colors.blueGrey,
          'icon': Icons.skip_next_rounded,
        };
      case 'n/a':
      case 'na':
        return {
          'label': 'N/A',
          'color': Colors.grey.shade500,
          'icon': Icons.remove_circle_outline_rounded,
        };
      case 'in_review':
        return {
          'label': 'In Review',
          'color': _kBrandPrimary,
          'icon': Icons.visibility_rounded,
        };
      case 'fixed':
        return {
          'label': 'Fixed',
          'color': _kWarningOrange,
          'icon': Icons.build_rounded,
        };
      case 'submitted_for_approval':
        return {
          'label': 'Submitted for Approval',
          'color': _kWarningOrange,
          'icon': Icons.pending_actions_rounded,
        };
      case 'submitted':
        return {
          'label': 'Submitted',
          'color': _kSuccessGreen,
          'icon': Icons.check_circle_rounded,
        };
      case 'approved':
        return {
          'label': 'Approved',
          'color': _kSuccessGreen,
          'icon': Icons.verified_rounded,
        };
      case 'not_approved':
      case 'rejected':
        return {
          'label': 'Rejected',
          'color': _kDangerRed,
          'icon': Icons.cancel_rounded,
        };
      case 'draft':
      default:
        return {
          'label': 'Pending',
          'color': Colors.grey.shade600,
          'icon': Icons.pending_outlined,
        };
    }
  }
}

