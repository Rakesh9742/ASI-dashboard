import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/qms_service.dart';
import '../widgets/qms_status_badge.dart';

class CheckItemDetailDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> checkItem;
  final VoidCallback? onRefresh;

  const CheckItemDetailDialog({
    super.key,
    required this.checkItem,
    this.onRefresh,
  });

  @override
  ConsumerState<CheckItemDetailDialog> createState() => _CheckItemDetailDialogState();
}

class _CheckItemDetailDialogState extends ConsumerState<CheckItemDetailDialog> {
  final QmsService _qmsService = QmsService();
  late Map<String, dynamic> _checkItem;
  bool _isLoading = false;
  final TextEditingController _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkItem = widget.checkItem;
    final reportData = _checkItem['report_data'];
    _commentController.text = reportData?['engineer_comments'] ?? '';
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.initState();
  }

  Future<void> _refreshItem() async {
    setState(() => _isLoading = true);
    try {
      final authState = ref.read(authProvider);
      final newItem = await _qmsService.getCheckItem(_checkItem['id'], token: authState.token);
      setState(() {
        _checkItem = newItem;
        final reportData = _checkItem['report_data'];
        _commentController.text = reportData?['engineer_comments'] ?? '';
      });
      widget.onRefresh?.call();
    } catch (e) {
      _showError('Error refreshing item: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Future<void> _fillAction() async {
    final reportPath = _checkItem['metadata']?['report_path']?.toString();
    if (reportPath == null || reportPath.isEmpty) {
      _showError('Report path is missing in metadata');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authState = ref.read(authProvider);
      await _qmsService.executeFillAction(_checkItem['id'], reportPath, token: authState.token);
      _showSuccess('Fill action completed successfully');
      await _refreshItem();
    } catch (e) {
      _showError('Error executing fill action: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitForApproval() async {
    setState(() => _isLoading = true);
    try {
      final authState = ref.read(authProvider);
      await _qmsService.submitCheckItemForApproval(
        _checkItem['id'],
        engineerComments: _commentController.text,
        token: authState.token,
      );
      _showSuccess('Submitted for approval');
      await _refreshItem();
    } catch (e) {
      _showError('Error submitting: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _approveReject(bool approved) async {
    setState(() => _isLoading = true);
    try {
      final authState = ref.read(authProvider);
      await _qmsService.approveCheckItem(
        _checkItem['id'],
        approved,
        comments: _commentController.text,
        token: authState.token,
      );
      _showSuccess(approved ? 'Approved successfully' : 'Marked as Check Again');
      await _refreshItem();
    } catch (e) {
      _showError('Error updating status: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final userRole = authState.user?['role'] as String?;
    final reportData = _checkItem['report_data'];
    final status = reportData?['status'] ?? 'pending';
    final metadata = _checkItem['metadata'] ?? {};

    // Freeze logic
    final bool isEngineer = userRole == 'engineer';
    final bool isLeadOrAdmin = userRole == 'lead' || userRole == 'admin' || userRole == 'project_manager';
    
    final bool isFrozen = status == 'submitted' || status == 'approved';
    final bool canEditComments = (isEngineer && (status == 'pending' || status == 'in_review' || status == 'not_approved')) ||
                                (isLeadOrAdmin && status == 'submitted');

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Check Item Details',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                if (_isLoading) 
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.red),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Content Scrollable
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldSection('Check ID', _checkItem['name'] ?? ''),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _buildFieldSection('Category', _checkItem['check_item_type'] ?? '')),
                        const SizedBox(width: 16),
                        Expanded(child: _buildFieldSection('Sub-Category', _checkItem['sub_category'] ?? '')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildFieldSection('Check Description', _checkItem['description'] ?? '', maxLines: 3),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _buildFieldSection('Severity', _checkItem['severity'] ?? '')),
                        const SizedBox(width: 16),
                        Expanded(child: _buildFieldLabel('Status', QmsStatusBadge(status: status))),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    const Text('Requirements & Evidence', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _buildGridField('Bronze', metadata['bronze']),
                        _buildGridField('Silver', metadata['silver']),
                        _buildGridField('Gold', metadata['gold']),
                        _buildGridField('Info', metadata['info']),
                        _buildGridField('Evidence', metadata['evidence']),
                        _buildGridField('Auto', metadata['auto']),
                        _buildGridField('Limit', metadata['limit']),
                      ],
                    ),
                    const SizedBox(height: 16),
                     _buildFieldSection('Report Path', metadata['report_path']?.toString() ?? ''),

                    const SizedBox(height: 24),
                    const Text('Results & Feedback', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _buildFieldSection('Result/Value', metadata['result_value']?.toString() ?? '')),
                        const SizedBox(width: 16),
                        Expanded(child: _buildFieldSection('Signoff', metadata['signoff']?.toString() ?? '')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Comments Section (Editable or Frozen)
                    Text(isLeadOrAdmin ? 'Reviewer Feedback' : 'Engineer Comments', 
                         style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _commentController,
                      enabled: canEditComments && !_isLoading,
                      maxLines: 3,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: canEditComments ? Colors.white : Colors.grey.shade200,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        hintText: 'Enter your comments here...',
                      ),
                    ),
                    
                    if (reportData?['lead_comments'] != null && isEngineer) ...[
                      const SizedBox(height: 16),
                      _buildFieldSection('Lead Feedback', reportData['lead_comments']),
                    ],

                    // CSV Data Preview (if exists)
                    if (reportData?['csv_data'] != null) ...[
                      const SizedBox(height: 24),
                      const Text('Parsed Report Data', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      _buildCsvPreview(reportData['csv_data']),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Footer Buttons - Workflow Driven
            _buildActionButtons(status, userRole),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(String status, String? role) {
    List<Widget> buttons = [];
    
    // Default Close button
    buttons.add(Expanded(
      child: OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFF4A148C)),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
        child: const Text('Close', style: TextStyle(fontSize: 16, color: Color(0xFF4A148C))),
      ),
    ));

    final bool isEngineer = role == 'engineer';
    final bool isLead = role == 'lead' || role == 'admin' || role == 'project_manager';

    // Engineer Actions
    if (isEngineer) {
      if (status == 'pending' || status == 'not_approved' || status == 'in_review') {
        buttons.add(const SizedBox(width: 16));
        buttons.add(Expanded(
          child: ElevatedButton(
            onPressed: _isLoading ? null : _fillAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A148C),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            child: const Text('Fill Action', style: TextStyle(fontSize: 16, color: Colors.white)),
          ),
        ));
      }

      if (status == 'in_review') {
        buttons.add(const SizedBox(width: 16));
        buttons.add(Expanded(
          child: ElevatedButton(
            onPressed: _isLoading ? null : _submitForApproval,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            child: const Text('Submit', style: TextStyle(fontSize: 16, color: Colors.white)),
          ),
        ));
      }
    }

    // Lead Actions
    if (isLead && status == 'submitted') {
      buttons.add(const SizedBox(width: 16));
      buttons.add(Expanded(
        child: ElevatedButton(
          onPressed: _isLoading ? null : () => _approveReject(false),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange.shade800,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          child: const Text('Check Again', style: TextStyle(fontSize: 16, color: Colors.white)),
        ),
      ));
      
      buttons.add(const SizedBox(width: 16));
      buttons.add(Expanded(
        child: ElevatedButton(
          onPressed: _isLoading ? null : () => _approveReject(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          child: const Text('Approve', style: TextStyle(fontSize: 16, color: Colors.white)),
        ),
      ));
    }

    return Row(children: buttons);
  }

  Widget _buildCsvPreview(dynamic csvData) {
    if (csvData is! List || csvData.isEmpty) return const Text('No data parsed');
    
    final List<dynamic> rows = csvData;
    final Map<String, dynamic> firstRow = rows.first;
    final List<String> columns = firstRow.keys.toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: MaterialStateProperty.all(Colors.grey.shade100),
        columns: columns.map((col) => DataColumn(label: Text(col, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
        rows: rows.take(5).map((row) {
          return DataRow(cells: columns.map((col) => DataCell(Text(row[col]?.toString() ?? '-'))).toList());
        }).toList(),
      ),
    );
  }

  Widget _buildFieldSection(String label, String value, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            (value.isEmpty || value == 'null') ? '-' : value,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 8),
        Container(
           width: double.infinity,
           height: 45, 
           alignment: Alignment.centerLeft,
           child: child,
        ),
      ],
    );
  }

  Widget _buildGridField(String label, dynamic value) {
    return SizedBox(
      width: 180, 
      child: _buildFieldSection(label, value?.toString() ?? ''),
    );
  }
}
