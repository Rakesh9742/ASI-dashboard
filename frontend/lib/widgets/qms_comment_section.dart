import 'package:flutter/material.dart';

class QmsCommentSection extends StatelessWidget {
  final String? engineerComments;
  final String? leadComments;
  final String? approvalComments;
  final bool canEdit;
  final Function(String)? onEngineerCommentChanged;
  final Function(String)? onLeadCommentChanged;

  const QmsCommentSection({
    super.key,
    this.engineerComments,
    this.leadComments,
    this.approvalComments,
    this.canEdit = false,
    this.onEngineerCommentChanged,
    this.onLeadCommentChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (engineerComments != null || canEdit) ...[
          _buildCommentCard(
            context,
            'Engineer Comments',
            engineerComments,
            Icons.engineering,
            Colors.blue,
            canEdit && onEngineerCommentChanged != null,
            onEngineerCommentChanged,
          ),
          const SizedBox(height: 12),
        ],
        if (leadComments != null || (canEdit && onLeadCommentChanged != null)) ...[
          _buildCommentCard(
            context,
            'Lead Comments',
            leadComments,
            Icons.person,
            Colors.purple,
            canEdit && onLeadCommentChanged != null,
            onLeadCommentChanged,
          ),
          const SizedBox(height: 12),
        ],
        if (approvalComments != null) ...[
          _buildCommentCard(
            context,
            'Approver Comments',
            approvalComments,
            Icons.verified_user,
            Colors.green,
            false,
            null,
          ),
        ],
      ],
    );
  }

  Widget _buildCommentCard(
    BuildContext context,
    String title,
    String? comment,
    IconData icon,
    Color color,
    bool editable,
    Function(String)? onChanged,
  ) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (editable && onChanged != null)
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Enter comment...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
                onChanged: onChanged,
                controller: comment != null 
                    ? TextEditingController(text: comment)
                    : TextEditingController(),
              )
            else
              Text(
                comment ?? 'No comments',
                style: TextStyle(
                  color: comment != null ? Colors.black87 : Colors.grey,
                  fontStyle: comment != null ? FontStyle.normal : FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

