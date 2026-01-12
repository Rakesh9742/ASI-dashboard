import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/qms_service.dart';
import '../services/api_service.dart';
import '../widgets/qms_status_badge.dart';
import '../widgets/qms_comment_section.dart';
import '../widgets/qms_audit_timeline.dart';

class QmsCheckItemDetailScreen extends ConsumerStatefulWidget {
  final int checkItemId;

  const QmsCheckItemDetailScreen({super.key, required this.checkItemId});

  @override
  ConsumerState<QmsCheckItemDetailScreen> createState() => _QmsCheckItemDetailScreenState();
}

class _QmsCheckItemDetailScreenState extends ConsumerState<QmsCheckItemDetailScreen> {
  final QmsService _qmsService = QmsService();
  final ApiService _apiService = ApiService();
  final TextEditingController _reportPathController = TextEditingController();
  final TextEditingController _fixDetailsController = TextEditingController();
  final TextEditingController _engineerCommentsController = TextEditingController();
  final TextEditingController _approverCommentsController = TextEditingController();

  bool _isLoading = true;
  bool _isExecutingFillAction = false;
  bool _isSubmitting = false;
  bool _isApproving = false;
  Map<String, dynamic>? _checkItem;
  List<dynamic> _history = [];
  String? _engineerCommentText;
  String? _approverCommentText;

  @override
  void initState() {
    super.initState();
    _loadCheckItem();
    _loadHistory();
  }

  @override
  void dispose() {
    _reportPathController.dispose();
    _fixDetailsController.dispose();
    _engineerCommentsController.dispose();
    _approverCommentsController.dispose();
    super.dispose();
  }

  Future<void> _loadCheckItem() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authState = ref.read(authProvider);
      final token = authState.token;

      if (token == null) {
        throw Exception('Not authenticated');
      }

      final checkItem = await _qmsService.getCheckItem(
        widget.checkItemId,
        token: token,
      );

      setState(() {
        _checkItem = checkItem;
        final reportData = checkItem['report_data'];
        if (reportData != null) {
          _reportPathController.text = reportData['report_path'] ?? '';
          _fixDetailsController.text = reportData['fix_details'] ?? '';
          _engineerCommentsController.text = reportData['engineer_comments'] ?? '';
        }
        final approval = checkItem['approval'];
        if (approval != null) {
          _approverCommentsController.text = approval['comments'] ?? '';
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading check item: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadHistory() async {
    try {
      final authState = ref.read(authProvider);
      final token = authState.token;

      if (token == null) return;

      final history = await _qmsService.getCheckItemHistory(
        widget.checkItemId,
        token: token,
      );

      setState(() {
        _history = history;
      });
    } catch (e) {
      // Silently fail for history
    }
  }

  Future<void> _executeFillAction() async {
    final reportPath = _reportPathController.text.trim();
    if (reportPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a report path'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isExecutingFillAction = true;
    });

    try {
      final authState = ref.read(authProvider);
      final token = authState.token;

      if (token == null) {
        throw Exception('Not authenticated');
      }

      await _qmsService.executeFillAction(
        widget.checkItemId,
        reportPath,
        token: token,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fill action executed successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadCheckItem();
        _loadHistory();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error executing fill action: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExecutingFillAction = false;
        });
      }
    }
  }

  Future<void> _saveChanges() async {
    try {
      final authState = ref.read(authProvider);
      final token = authState.token;

      if (token == null) {
        throw Exception('Not authenticated');
      }

      await _qmsService.updateCheckItem(
        widget.checkItemId,
        fixDetails: _fixDetailsController.text.trim().isEmpty
            ? null
            : _fixDetailsController.text.trim(),
        engineerComments: _engineerCommentsController.text.trim().isEmpty
            ? null
            : _engineerCommentsController.text.trim(),
        token: token,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Changes saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadCheckItem();
        _loadHistory();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving changes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _submitForApproval() async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      final authState = ref.read(authProvider);
      final token = authState.token;

      if (token == null) {
        throw Exception('Not authenticated');
      }

      await _qmsService.submitCheckItemForApproval(
        widget.checkItemId,
        token: token,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Check item submitted for approval'),
            backgroundColor: Colors.green,
          ),
        );
        _loadCheckItem();
        _loadHistory();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _approveReject(bool approved) async {
    setState(() {
      _isApproving = true;
    });

    try {
      final authState = ref.read(authProvider);
      final token = authState.token;

      if (token == null) {
        throw Exception('Not authenticated');
      }

      await _qmsService.approveCheckItem(
        widget.checkItemId,
        approved,
        comments: _approverCommentsController.text.trim().isEmpty
            ? null
            : _approverCommentsController.text.trim(),
        token: token,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approved ? 'Check item approved' : 'Check item rejected'),
            backgroundColor: approved ? Colors.green : Colors.orange,
          ),
        );
        _loadCheckItem();
        _loadHistory();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isApproving = false;
        });
      }
    }
  }

  bool _isEngineer() {
    final authState = ref.read(authProvider);
    final user = authState.user;
    final role = user?['role'];
    return role == 'engineer' || role == 'admin' || role == 'lead';
  }

  bool _isApprover() {
    final authState = ref.read(authProvider);
    final user = authState.user;
    final role = user?['role'];
    return role == 'admin' || role == 'project_manager' || role == 'lead';
  }

  bool _canEdit() {
    if (_checkItem == null) return false;
    final reportData = _checkItem!['report_data'];
    if (reportData == null) return true; // Can edit if no report data yet
    final status = reportData['status'] ?? 'pending';
    // Can edit if pending, in_review, or not_approved
    return status == 'pending' || status == 'in_review' || status == 'not_approved';
  }

  bool _canSubmit() {
    if (_checkItem == null) return false;
    
    // Don't allow individual check item submission if parent checklist is submitted for approval
    final checklistStatus = _checkItem!['checklist_status'] ?? 'draft';
    if (checklistStatus == 'submitted_for_approval' || checklistStatus == 'submitted') {
      return false;
    }
    
    final reportData = _checkItem!['report_data'];
    if (reportData == null) return false;
    final status = reportData['status'] ?? 'pending';
    // Can submit if in_review or fixed
    return (status == 'in_review' || status == 'fixed' || status == 'not_approved') &&
        _isEngineer();
  }

  bool _canApprove() {
    if (_checkItem == null) return false;
    final reportData = _checkItem!['report_data'];
    if (reportData == null) return false;
    final status = reportData['status'] ?? 'pending';
    return status == 'submitted' && _isApprover();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    if (!authState.isAuthenticated) {
      return const Center(child: Text('Please log in to access QMS'));
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_checkItem == null) {
      return const Center(child: Text('Check item not found'));
    }

    final reportData = _checkItem!['report_data'];
    final approval = _checkItem!['approval'];
    final status = reportData?['status'] ?? 'pending';
    final csvData = reportData?['csv_data'];

    return Scaffold(
      appBar: AppBar(
        title: Text(_checkItem!['name'] ?? 'Check Item'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadCheckItem();
              _loadHistory();
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Check item header
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _checkItem!['name'] ?? 'Unnamed Check Item',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        QmsStatusBadge(status: status),
                      ],
                    ),
                    if (_checkItem!['description'] != null) ...[
                      const SizedBox(height: 8),
                      Text(_checkItem!['description']),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Fill Action section
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Fill Action',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _reportPathController,
                      decoration: const InputDecoration(
                        labelText: 'Report Path',
                        hintText: 'Enter path to CSV report file',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.file_present),
                      ),
                      enabled: _canEdit() && _isEngineer(),
                    ),
                    const SizedBox(height: 12),
                    if (_isEngineer() && _canEdit())
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isExecutingFillAction ? null : _executeFillAction,
                          icon: _isExecutingFillAction
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.upload_file),
                          label: Text(_isExecutingFillAction
                              ? 'Executing...'
                              : 'Execute Fill Action'),
                        ),
                      ),
                    if (csvData != null) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        'CSV Data',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${csvData.length} rows loaded',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Fix Details section (Engineer)
            if (_isEngineer() && _canEdit())
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Fix Details',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _fixDetailsController,
                        decoration: const InputDecoration(
                          labelText: 'Fix Details',
                          hintText: 'Describe the fixes applied...',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 5,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saveChanges,
                          child: const Text('Save Changes'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_isEngineer() && _canEdit()) const SizedBox(height: 16),

            // Comments section
            QmsCommentSection(
              engineerComments: reportData?['engineer_comments'],
              leadComments: reportData?['lead_comments'],
              approvalComments: approval?['comments'],
              canEdit: _isEngineer() && _canEdit(),
              onEngineerCommentChanged: (value) {
                _engineerCommentText = value;
                _engineerCommentsController.text = value;
              },
              onLeadCommentChanged: (value) {
                // Lead comments handled separately
              },
            ),
            const SizedBox(height: 16),

            // Approval section (Approver)
            if (_isApprover() && _canApprove())
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Approval',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _approverCommentsController,
                        decoration: const InputDecoration(
                          labelText: 'Comments',
                          hintText: 'Enter approval comments...',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isApproving ? null : () => _approveReject(true),
                              icon: const Icon(Icons.check),
                              label: const Text('Approve'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isApproving ? null : () => _approveReject(false),
                              icon: const Icon(Icons.close),
                              label: const Text('Reject'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (_isApprover() && _canApprove()) const SizedBox(height: 16),

            // Show message if checklist is submitted for approval
            if (_checkItem != null) ...[
              Builder(
                builder: (context) {
                  final checklistStatus = _checkItem!['checklist_status'] ?? 'draft';
                  if (checklistStatus == 'submitted_for_approval' || checklistStatus == 'submitted') {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This checklist has been submitted for approval. Individual check item submission is disabled.',
                              style: TextStyle(color: Colors.orange.shade700),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],

            // Submit button (Engineer)
            if (_isEngineer() && _canSubmit())
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submitForApproval,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(_isSubmitting ? 'Submitting...' : 'Submit for Approval'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            if (_isEngineer() && _canSubmit()) const SizedBox(height: 16),

            // Audit trail
            QmsAuditTimeline(history: _history),
          ],
        ),
      ),
    );
  }
}

