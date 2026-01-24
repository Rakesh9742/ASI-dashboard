import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../services/qms_service.dart';
import '../widgets/qms_status_badge.dart';

class QmsChecklistDetailScreen extends ConsumerStatefulWidget {
  final int checklistId;

  const QmsChecklistDetailScreen({super.key, required this.checklistId});

  @override
  ConsumerState<QmsChecklistDetailScreen> createState() => _QmsChecklistDetailScreenState();
}

class _QmsChecklistDetailScreenState extends ConsumerState<QmsChecklistDetailScreen> {
  final QmsService _qmsService = QmsService();
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isApproving = false;
  bool _isAssigningApprover = false;
  Map<String, dynamic>? _checklist;
  List<dynamic> _availableApprovers = [];
  int? _selectedApproverId;
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  int _currentPage = 0;
  int _itemsPerPage = 10;
  final TextEditingController _approvalCommentsController = TextEditingController();

  // Filters for check items table
  String? _selectedCheckId;
  String? _selectedCategory;
  String? _selectedSubCategory;
  String? _selectedSeverity;
  String? _selectedBronze;
  String? _selectedSilver;
  String? _selectedGold;
  String? _selectedEvidence;
  
  // Track expanded report path rows
  final Map<int, bool> _expandedReportPaths = {};
  
  // Track selected check items for batch approval/rejection
  final Set<int> _selectedCheckItemIds = {};

  @override
  void initState() {
    super.initState();
    _loadChecklist();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    _approvalCommentsController.dispose();
    super.dispose();
  }

  Future<void> _loadChecklist() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authState = ref.read(authProvider);
      final token = authState.token;

      if (token == null) {
        throw Exception('Not authenticated');
      }

      final checklist = await _qmsService.getChecklistWithItems(
        widget.checklistId,
        token: token,
      );

      setState(() {
        _checklist = checklist;
        _isLoading = false;
      });

      // Load approvers if checklist is submitted for approval
      final status = checklist['status'] ?? 'draft';
      if (status == 'submitted_for_approval' && _isLead()) {
        _loadApprovers();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading checklist: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _submitChecklist() async {
    final authState = ref.read(authProvider);
    final token = authState.token;

    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not authenticated'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await _qmsService.submitChecklist(widget.checklistId, token: token);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Checklist submitted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadChecklist();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting checklist: $e'),
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

  bool _canSubmitChecklist() {
    if (_checklist == null) return false;
    final status = _checklist!['status'] ?? 'draft';
    // Can submit if status is draft (engineer can submit for approval)
    return status == 'draft';
  }

  bool _isEngineer() {
    final authState = ref.read(authProvider);
    final user = authState.user;
    final role = user?['role'];
    return role == 'engineer' || role == 'admin';
  }

  bool _isLead() {
    final authState = ref.read(authProvider);
    final user = authState.user;
    return user?['role'] == 'lead' || user?['role'] == 'admin';
  }

  bool _isApprover() {
    final authState = ref.read(authProvider);
    final user = authState.user;
    final role = user?['role'];
    final userId = user?['id'];

    if (_checklist == null || userId == null) return false;

    // Admins, project managers, and leads are always allowed (backend will still enforce assignee rules)
    if (role == 'admin' || role == 'project_manager' || role == 'lead') {
      return true;
    }

    // Engineers can be approvers only if they are assigned/default approver on at least one item
    if (role == 'engineer') {
      final items = _checklist!['check_items'] as List?;
      if (items == null) return false;

      for (final item in items) {
        final approval = item['approval'];
        if (approval != null) {
          final approverId =
              approval['assigned_approver_id'] ?? approval['default_approver_id'];
          if (approverId == userId) {
            return true;
          }
        }
      }
    }

    return false;
  }

  bool _canApproveCheckItem(Map<String, dynamic> item) {
    if (_checklist == null) return false;
    
    final checklistStatus = _checklist!['status'] ?? 'draft';
    if (checklistStatus != 'submitted_for_approval') return false;

    final authState = ref.read(authProvider);
    final user = authState.user;
    final role = user?['role'];
    final userId = user?['id'];

    if (userId == null) return false;

      final approval = item['approval'];
      if (approval == null) return false;

    final approvalStatus = approval['status'] ?? 'pending';
    // Only pending/submitted items can be approved/rejected
    if (!(approvalStatus == 'pending' || approvalStatus == 'submitted')) {
      return false;
    }

    // Admin / PM / Lead can act on any item (backend still enforces rules)
    if (role == 'admin' || role == 'project_manager' || role == 'lead') {
      return true;
    }

    // Engineer can act only if they are the assigned/default approver for this item
    if (role == 'engineer') {
      final approverId =
          approval['assigned_approver_id'] ?? approval['default_approver_id'];
      return approverId == userId;
    }

    return false;
  }

  Future<void> _loadApprovers() async {
    if (_isAssigningApprover) return;
    try {
      final authState = ref.read(authProvider);
      final token = authState.token;
      if (token == null) return;

      final approvers = await _qmsService.getApproversForChecklist(
        widget.checklistId,
        token: token,
      );

      setState(() {
        _availableApprovers = approvers;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading approvers: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _assignApprover({int? approverId}) async {
    final targetApproverId = approverId ?? _selectedApproverId;
    if (targetApproverId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an approver'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final authState = ref.read(authProvider);
    final token = authState.token;
    if (token == null) return;

    setState(() {
      _isAssigningApprover = true;
    });

    try {
      await _qmsService.assignApproverToChecklist(
        widget.checklistId,
        targetApproverId,
        token: token,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Approver assigned successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadChecklist();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error assigning approver: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAssigningApprover = false;
        });
      }
    }
  }

  void _showAssignApproverDialog() {
    _selectedApproverId = null;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Change Approver'),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<int>(
                      value: _selectedApproverId,
                      decoration: const InputDecoration(
                        labelText: 'Select Approver',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.verified_user),
                      ),
                      items: _availableApprovers
                          .map(
                            (approver) => DropdownMenuItem<int>(
                              value: approver['id'],
                              child: Text(
                                '${approver['full_name'] ?? approver['username']} (${approver['role']})',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          _selectedApproverId = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: _selectedApproverId == null || _isAssigningApprover
                      ? null
                      : () async {
                          await _assignApprover(approverId: _selectedApproverId);
                          if (context.mounted) Navigator.pop(context);
                        },
                  child: _isAssigningApprover
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _approveCheckItem(int checkItemId, bool approved, {String? comments}) async {
    final authState = ref.read(authProvider);
    final token = authState.token;
    if (token == null) return;

    try {
      await _qmsService.approveCheckItem(
        checkItemId,
        approved,
        comments: comments,
        token: token,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Check item ${approved ? 'approved' : 'rejected'} successfully'),
            backgroundColor: approved ? Colors.green : Colors.orange,
          ),
        );
        _loadChecklist(); // Reload to update statuses
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error ${approved ? 'approving' : 'rejecting'} check item: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _selectAllCheckItems() {
    final checklistStatus = _checklist?['status'] ?? 'draft';
    if (checklistStatus != 'submitted_for_approval') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checklist must be in submitted_for_approval status to select items'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final checkItems = _checklist?['check_items'] as List?;
    if (checkItems == null || checkItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No check items found'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Select all pending/submitted items (not already approved/rejected)
    setState(() {
      _selectedCheckItemIds.clear();
      for (var item in checkItems) {
        final itemId = item['id'] as int;
        final approval = item['approval'];
        if (approval != null) {
          final status = approval['status'] ?? 'pending';
          // Only select items that can still be approved/rejected
          if (status == 'pending' || status == 'submitted') {
            _selectedCheckItemIds.add(itemId);
          }
        }
      }
    });

    if (_selectedCheckItemIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pending check items to select'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _approveSelectedCheckItems() async {
    if (_selectedCheckItemIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select check items to approve'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final TextEditingController commentsController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Approve ${_selectedCheckItemIds.length} Check Item(s)'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Are you sure you want to approve ${_selectedCheckItemIds.length} selected check item(s)?',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: commentsController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Comments (optional)',
                    hintText: 'Enter approval comments',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Approve'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await _batchApproveRejectCheckItems(true, commentsController.text.isNotEmpty ? commentsController.text : null);
  }

  Future<void> _rejectSelectedCheckItems() async {
    if (_selectedCheckItemIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select check items to reject'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final TextEditingController commentsController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Reject ${_selectedCheckItemIds.length} Check Item(s)'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Are you sure you want to reject ${_selectedCheckItemIds.length} selected check item(s)?',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: commentsController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Comments (optional)',
                    hintText: 'Enter rejection reason',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await _batchApproveRejectCheckItems(false, commentsController.text.isNotEmpty ? commentsController.text : null);
  }

  Future<void> _batchApproveRejectCheckItems(bool approve, String? comments) async {
    final authState = ref.read(authProvider);
    final token = authState.token;
    if (token == null) return;

    setState(() {
      _isApproving = true;
    });

    try {
      await _qmsService.batchApproveRejectCheckItems(
        List.from(_selectedCheckItemIds),
        approve,
        comments: comments,
        token: token,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_selectedCheckItemIds.length} check item(s) ${approve ? 'approved' : 'rejected'} successfully'),
            backgroundColor: approve ? Colors.green : Colors.orange,
          ),
        );
        setState(() {
          _selectedCheckItemIds.clear();
        });
        _loadChecklist(); // Reload to update statuses
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error ${approve ? 'approving' : 'rejecting'} check items: $e'),
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

  Widget _buildProgressTimeline() {
    if (_checklist == null) return SizedBox.shrink();

    final status = _checklist!['status'] ?? 'draft';
    final createdAt = _checklist!['created_at'];
    final submittedAt = _checklist!['submitted_at'];
    final updatedAt = _checklist!['updated_at'];
    final submittedByName = _checklist!['submitted_by_name'];
    
    // Get current user for engineer name if not submitted yet
    final authState = ref.read(authProvider);
    final currentUserName = authState.user?['full_name'] ?? authState.user?['username'] ?? 'Engineer';
    final engineerName = submittedByName ?? currentUserName;
    
    // Parse dates
    DateTime? createdDate;
    DateTime? submittedDate;
    DateTime? updatedDate;
    
    try {
      if (createdAt != null) {
        createdDate = createdAt is DateTime ? createdAt : DateTime.parse(createdAt.toString());
      }
      if (submittedAt != null) {
        submittedDate = submittedAt is DateTime ? submittedAt : DateTime.parse(submittedAt.toString());
      }
      if (updatedAt != null) {
        updatedDate = updatedAt is DateTime ? updatedAt : DateTime.parse(updatedAt.toString());
      }
    } catch (e) {
      // Date parsing failed, use null
    }

    // Define timeline stages
    final stages = [
      {'title': 'Checklist', 'date': createdDate},
      {'title': engineerName, 'date': createdDate},
      {'title': 'Submitted for Approval', 'date': submittedDate},
      {'title': 'Project Lead', 'date': submittedDate},
      {'title': status == 'rejected' ? 'Rejected' : 'Approved', 'date': updatedDate},
    ];

    // Determine progress based on status
    int completedStages = 0;
    bool isRejected = false;
    
    if (status == 'draft') {
      completedStages = 2; // "Checklist" and "Engineer" stages (both active when created)
    } else if (status == 'submitted_for_approval') {
      completedStages = 3; // Up to "Submitted for Approval"
    } else if (status == 'approved') {
      completedStages = 5; // All stages completed
    } else if (status == 'rejected') {
      completedStages = 5; // All stages (but red color)
      isRejected = true;
    }

    // SemiconOS theme colors
    final activeColor = isRejected ? Colors.red.shade700 : const Color(0xFF14B8A6);
    final inactiveColor = Colors.grey.shade300;
    final activeTextColor = isRejected ? Colors.red.shade900 : const Color(0xFF14B8A6);
    final inactiveTextColor = Colors.grey.shade600;

    return Column(
      children: [
        // Block name and Checklist name in a Card
        Card(
          elevation: 2,
          margin: const EdgeInsets.all(16.0),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                if (_checklist!['block_name'] != null) ...[
                  Text(
                    'Block: ${_checklist!['block_name']}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(width: 20),
                ],
                Text(
                  'Checklist: ${_checklist!['name'] ?? 'Unnamed Checklist'}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Progress Timeline in a Card
        Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 55.0, vertical: 30.0),
            child: Row(
              children: List.generate(stages.length, (index) {
                final stage = stages[index];
                final isActive = index < completedStages;
                final stageColor = isActive ? activeColor : inactiveColor;
                final textColor = isActive ? activeTextColor : inactiveTextColor;
                
                // Format date with time
                String dateText = '';
                if (stage['date'] != null && stage['date'] is DateTime) {
                  final date = stage['date'] as DateTime;
                  dateText = DateFormat('MMM dd, HH:mm').format(date);
                }

                return Expanded(
                  flex: index == stages.length - 1 ? 0 : 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date + Time above timeline - aligned to circle center
                      SizedBox(
                        height: 24,
                        width: 30,
                        child: dateText.isNotEmpty
                            ? OverflowBox(
                                maxWidth: 120,
                                child: Text(
                                  index < completedStages ? dateText : '',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                                    color: isActive ? textColor : inactiveTextColor,
                                  ),
                                ),
                              )
                            : const SizedBox(),
                      ),
                      const SizedBox(height: 8),
                      // Stage circle and connecting line
                      Row(
                        children: [
                          // Circle indicator - 30px
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: isActive ? stageColor : Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: stageColor,
                                width: isActive ? 0 : 2,
                              ),
                              boxShadow: isActive
                                  ? [
                                      BoxShadow(
                                        color: stageColor.withOpacity(0.3),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Center(
                              child: isActive
                                  ? Icon(
                                      index == 0
                                          ? Icons.rocket_launch
                                          : index == stages.length - 1 && isRejected
                                              ? Icons.close
                                              : Icons.check,
                                      color: Colors.white,
                                      size: 16,
                                    )
                                  : Icon(
                                      Icons.circle_outlined,
                                      color: inactiveColor,
                                      size: 16,
                                    ),
                            ),
                          ),
                          // Connecting line (except last stage)
                          if (index < stages.length - 1)
                            Expanded(
                              child: Container(
                                height: 10,
                                decoration: BoxDecoration(
                                  color: index < completedStages - 1 ? activeColor : inactiveColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Stage name below timeline - aligned to circle center
                      SizedBox(
                        height: 60,
                        width: 30,
                        child: OverflowBox(
                          maxWidth: 200,
                          maxHeight: 60,
                          child: Text(
                            stage['title'].toString(),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                              color: textColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Future<void> _showApproveRejectDialog(int checkItemId, String checkItemName, {bool? initialAction}) async {
    final TextEditingController commentsController = TextEditingController();
    final bool isApprove = initialAction ?? true; // Default to approve if not specified
    
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isApprove ? 'Approve Check Item' : 'Reject Check Item'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  checkItemName,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: commentsController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Comments (optional)',
                    hintText: isApprove ? 'Enter approval comments' : 'Enter rejection reason',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            if (!isApprove)
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _approveCheckItem(checkItemId, false, comments: commentsController.text.isNotEmpty ? commentsController.text : null);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: Text('Reject'),
              ),
            if (isApprove)
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _approveCheckItem(checkItemId, true, comments: commentsController.text.isNotEmpty ? commentsController.text : null);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: Text('Approve'),
              ),
          ],
        );
      },
    );
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

    if (_checklist == null) {
      return const Center(child: Text('Checklist not found'));
    }

    final checkItems = _checklist!['check_items'] as List? ?? [];
    final checklistStatus = _checklist!['status'] ?? 'draft';
    final canSubmit = _canSubmitChecklist() && checklistStatus != 'submitted';

    // Build filter option lists from available check items
    List<String> _buildOptions(String key) {
      final values = checkItems
          .map((item) => (item[key] ?? '').toString().trim())
          .where((value) => value.isNotEmpty && value != 'null')
          .toSet()
          .toList();
      values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return values;
    }

    final checkIdOptions = checkItems
        .map((item) => (item['name'] ?? item['id'] ?? '').toString().trim())
        .where((value) => value.isNotEmpty && value != 'null')
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final categoryOptions = _buildOptions('category');
    final subCategoryOptions = _buildOptions('sub_category');
    final severityOptions = _buildOptions('severity');
    final bronzeOptions = _buildOptions('bronze');
    final silverOptions = _buildOptions('silver');
    final goldOptions = _buildOptions('gold');
    final evidenceOptions = _buildOptions('evidence');

    // Apply filters
    final filteredItems = checkItems.where((item) {
      bool match = true;

      if (_selectedCheckId != null && _selectedCheckId!.isNotEmpty) {
        final checkIdValue =
            (item['name'] ?? item['id'] ?? '').toString().trim();
        match = match && checkIdValue == _selectedCheckId;
      }
      if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
        match =
            match && (item['category'] ?? '').toString().trim() == _selectedCategory;
      }
      if (_selectedSubCategory != null && _selectedSubCategory!.isNotEmpty) {
        match = match &&
            (item['sub_category'] ?? '').toString().trim() ==
                _selectedSubCategory;
      }
      if (_selectedSeverity != null && _selectedSeverity!.isNotEmpty) {
        match = match &&
            (item['severity'] ?? '').toString().trim() == _selectedSeverity;
      }
      if (_selectedBronze != null && _selectedBronze!.isNotEmpty) {
        match =
            match && (item['bronze'] ?? '').toString().trim() == _selectedBronze;
      }
      if (_selectedSilver != null && _selectedSilver!.isNotEmpty) {
        match =
            match && (item['silver'] ?? '').toString().trim() == _selectedSilver;
      }
      if (_selectedGold != null && _selectedGold!.isNotEmpty) {
        match = match && (item['gold'] ?? '').toString().trim() == _selectedGold;
      }
      if (_selectedEvidence != null && _selectedEvidence!.isNotEmpty) {
        match = match &&
            (item['evidence'] ?? '').toString().trim() == _selectedEvidence;
      }

      return match;
    }).toList();

    final paginatedItems = _getPaginatedItems(filteredItems);
    final startIndex = _currentPage * _itemsPerPage;
    final totalItems = filteredItems.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_checklist!['name'] ?? 'Checklist'),
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'submit') {
                _submitChecklist();
              } else if (value == 'assign') {
                _loadApprovers().then((_) => _showAssignApproverDialog());
              } else if (value == 'approve_all') {
                _selectAllCheckItems();
              } else if (value == 'refresh') {
                _loadChecklist();
              }
            },
            itemBuilder: (context) {
              final items = <PopupMenuEntry<String>>[];
              if (_isEngineer() && checklistStatus == 'draft') {
                items.add(
                  const PopupMenuItem(
                    value: 'submit',
                    child: Row(
                      children: [
                        Icon(Icons.send, size: 18),
                        SizedBox(width: 8),
                        Text('Submit for Approval'),
                      ],
                    ),
                  ),
                );
              }
              if (_isLead() && checklistStatus == 'submitted_for_approval') {
                items.add(
                  const PopupMenuItem(
                    value: 'assign',
                    child: Row(
                      children: [
                        Icon(Icons.swap_horiz, size: 18),
                        SizedBox(width: 8),
                        Text('Change Approver'),
                      ],
                    ),
                  ),
                );
              }
              if (_isApprover() && checklistStatus == 'submitted_for_approval') {
                items.add(
                  const PopupMenuItem(
                    value: 'approve_all',
                    child: Row(
                      children: [
                        Icon(Icons.select_all, size: 18),
                        SizedBox(width: 8),
                        Text('Select All Items'),
                      ],
                    ),
                  ),
                );
              }
              items.add(
                const PopupMenuItem(
                  value: 'refresh',
                  child: Row(
                    children: [
                      Icon(Icons.refresh, size: 18),
                      SizedBox(width: 8),
                      Text('Refresh'),
                    ],
                  ),
                ),
              );
              return items;
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress Timeline
          _buildProgressTimeline(),

          // Check items table
          Expanded(
            child: checkItems.isEmpty
                ? const Center(
                    child: Text(
                      'No check items found',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : Card(
                    elevation: 2,
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                    children: [
                      // Clear filters button - appears above table when filters are active
                      if (_hasActiveFilters())
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF6A1B9A),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _selectedCheckId = null;
                                    _selectedCategory = null;
                                    _selectedSubCategory = null;
                                    _selectedSeverity = null;
                                    _selectedBronze = null;
                                    _selectedSilver = null;
                                    _selectedGold = null;
                                    _selectedEvidence = null;
                                    _currentPage = 0;
                                  });
                                },
                                icon: const Icon(Icons.clear, size: 18),
                                label: const Text('Clear filters'),
                              ),
                            ],
                          ),
                        ),

                      Expanded(
                        child: Container(
                          child: LayoutBuilder(
                            builder: (context, outerConstraints) {
                              // Define explicit column widths to ensure perfect alignment
                              const double colCheckbox = 50;
                              const double colCheckId = 120;
                              const double colCategory = 150;
                              const double colSubCategory = 150;
                              const double colDescription = 300;
                              const double colSeverity = 100;
                              const double colBronze = 100;
                              const double colSilver = 100;
                              const double colGold = 100;
                              const double colInfo = 150;
                              const double colEvidence = 150;
                              const double colReportPath = 250;
                              const double colResult = 150;
                              const double colStatus = 260;
                              const double colComments = 200;
                              const double colReviewerComments = 200;
                              const double colSignoff = 120;
                              const double colAuto = 80;

                              const double totalWidth = colCheckbox + colCheckId + colCategory + colSubCategory + colDescription + colSeverity + colBronze + colSilver + colGold + colInfo + colEvidence + colReportPath + colResult + colStatus + colComments + colReviewerComments + colSignoff + colAuto;

                              final columnWidths = {
                                0: const FixedColumnWidth(colCheckbox),
                                1: const FixedColumnWidth(colCheckId),
                                2: const FixedColumnWidth(colCategory),
                                3: const FixedColumnWidth(colSubCategory),
                                4: const FixedColumnWidth(colDescription),
                                5: const FixedColumnWidth(colSeverity),
                                6: const FixedColumnWidth(colBronze),
                                7: const FixedColumnWidth(colSilver),
                                8: const FixedColumnWidth(colGold),
                                9: const FixedColumnWidth(colInfo),
                                10: const FixedColumnWidth(colEvidence),
                                11: const FixedColumnWidth(colReportPath),
                                12: const FixedColumnWidth(colResult),
                                13: const FixedColumnWidth(colStatus),
                                14: const FixedColumnWidth(colComments),
                                15: const FixedColumnWidth(colReviewerComments),
                                16: const FixedColumnWidth(colSignoff),
                                17: const FixedColumnWidth(colAuto),
                              };

                              Widget buildHeaderCell(Widget child) {
                                return Container(
                                  height: 56,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  alignment: Alignment.centerLeft,
                                  child: child,
                                );
                              }

                              return Scrollbar(
                                controller: _horizontalScrollController,
                                thumbVisibility: true,
                                thickness: 8,
                                radius: const Radius.circular(4),
                                child: SingleChildScrollView(
                                  controller: _horizontalScrollController,
                                  scrollDirection: Axis.horizontal,
                                  child: Container(
                                    width: totalWidth < outerConstraints.maxWidth ? outerConstraints.maxWidth : totalWidth,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Sticky Header (Sticky within the vertical scroll context, but moves with horizontal scroll)
                                        Container(
                                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                          child: Table(
                                            columnWidths: columnWidths,
                                            children: [
                                              TableRow(
                                                children: [
                                                  buildHeaderCell(
                                                    Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Checkbox(
                                                          value: paginatedItems.isNotEmpty && 
                                                                 paginatedItems.where((item) {
                                                            final approval = item['approval'];
                                                            final status = approval?['status'] ?? 'pending';
                                                            return status == 'pending' || status == 'submitted';
                                                          }).isNotEmpty &&
                                                                 paginatedItems.where((item) {
                                                            final approval = item['approval'];
                                                            final status = approval?['status'] ?? 'pending';
                                                            final itemId = item['id'] as int;
                                                            return (status == 'pending' || status == 'submitted') && 
                                                                   _selectedCheckItemIds.contains(itemId);
                                                          }).length == paginatedItems.where((item) {
                                                            final approval = item['approval'];
                                                            final status = approval?['status'] ?? 'pending';
                                                            return status == 'pending' || status == 'submitted';
                                                          }).length,
                                                          onChanged: (bool? value) {
                                                            setState(() {
                                                              // Select/deselect all selectable items on current page
                                                              for (var item in paginatedItems) {
                                                                final itemId = item['id'] as int;
                                                                final approval = item['approval'];
                                                                final status = approval?['status'] ?? 'pending';
                                                                if (status == 'pending' || status == 'submitted') {
                                                                  if (value == true) {
                                                                    _selectedCheckItemIds.add(itemId);
                                                                  } else {
                                                                    _selectedCheckItemIds.remove(itemId);
                                                                  }
                                                                }
                                                              }
                                                            });
                                                          },
                                                          activeColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                                          checkColor: Theme.of(context).colorScheme.onSurface,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  buildHeaderCell(_buildHeaderFilter(title: 'Check ID', value: _selectedCheckId, options: checkIdOptions, onChanged: (v) => setState(() { _selectedCheckId = v; _currentPage = 0; }))),
                                                  buildHeaderCell(_buildHeaderFilter(title: 'Category', value: _selectedCategory, options: categoryOptions, onChanged: (v) => setState(() { _selectedCategory = v; _currentPage = 0; }))),
                                                  buildHeaderCell(_buildHeaderFilter(title: 'Sub-Category', value: _selectedSubCategory, options: subCategoryOptions, onChanged: (v) => setState(() { _selectedSubCategory = v; _currentPage = 0; }))),
                                                  buildHeaderCell(Text('Check Description', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 13))),
                                                  buildHeaderCell(_buildHeaderFilter(title: 'Severity', value: _selectedSeverity, options: severityOptions, onChanged: (v) => setState(() { _selectedSeverity = v; _currentPage = 0; }))),
                                                  buildHeaderCell(_buildHeaderFilter(title: 'Bronze', value: _selectedBronze, options: bronzeOptions, onChanged: (v) => setState(() { _selectedBronze = v; _currentPage = 0; }))),
                                                  buildHeaderCell(_buildHeaderFilter(title: 'Silver', value: _selectedSilver, options: silverOptions, onChanged: (v) => setState(() { _selectedSilver = v; _currentPage = 0; }))),
                                                  buildHeaderCell(_buildHeaderFilter(title: 'Gold', value: _selectedGold, options: goldOptions, onChanged: (v) => setState(() { _selectedGold = v; _currentPage = 0; }))),
                                                  buildHeaderCell(Text('Info', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 13))),
                                                  buildHeaderCell(_buildHeaderFilter(title: 'Evidence', value: _selectedEvidence, options: evidenceOptions, onChanged: (v) => setState(() { _selectedEvidence = v; _currentPage = 0; }))),
                                                  buildHeaderCell(Text('Report Path', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 13))),
                                                  buildHeaderCell(Text('Result/Value', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 13))),
                                                  buildHeaderCell(Text('Status', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 13))),
                                                  buildHeaderCell(Text('Comments', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 13))),
                                                  buildHeaderCell(Text('Reviewer Comments', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 13))),
                                                  buildHeaderCell(Text('Signoff', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 13))),
                                                  buildHeaderCell(Text('Auto', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 13))),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Scrollable Body
                                        Expanded(
                                          child: Scrollbar(
                                            controller: _verticalScrollController,
                                            thumbVisibility: true,
                                            thickness: 8,
                                            radius: const Radius.circular(4),
                                            child: SingleChildScrollView(
                                              controller: _verticalScrollController,
                                              physics: const AlwaysScrollableScrollPhysics(),
                                              child: Table(
                                                columnWidths: columnWidths,
                                                children: paginatedItems.asMap().entries.map((entry) {
                                                  final innerIndex = entry.key;
                                                  final rowIndex = startIndex + innerIndex + 1;
                                                  final item = entry.value;
                                                  final reportData = item['report_data'];
                                                  final approval = item['approval'];
                                                  final status = reportData?['status'] ?? 'pending';
                                                  final signoffStatus = reportData?['signoff_status'] ?? 'N/A';
                                                  final autoApprove = item['auto_approve'] ?? false;

                                                  const baseTextStyle = TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.black87,
                                                    fontWeight: FontWeight.w400,
                                                  );

                                                  Widget buildBodyCell(Widget child, {Alignment alignment = Alignment.centerLeft, VoidCallback? onTap}) {
                                                    return TableCell(
                                                        child: Container(
                                                          height: 80,
                                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                          alignment: alignment,
                                                          decoration: BoxDecoration(
                                                            border: Border(
                                                              bottom: BorderSide(color: Colors.grey.shade100),
                                                            ),
                                                          ),
                                                          child: child,
                                                      ),
                                                    );
                                                  }

                                                  final approvalStatus = approval?['status'] ?? 'pending';
                                                  final canSelect = checklistStatus == 'submitted_for_approval' && 
                                                                   (approvalStatus == 'pending' || approvalStatus == 'submitted');
                                                  final isSelected = _selectedCheckItemIds.contains(item['id'] as int);
                                                  
                                                  // Build checkbox/status indicator cell
                                                  Widget statusIndicator;
                                                  if (approvalStatus == 'approved') {
                                                    // Show checkbox filled with green checkmark for approved
                                                    statusIndicator = Checkbox(
                                                      value: true,
                                                      onChanged: null, // Disabled
                                                      activeColor: Colors.green,
                                                      checkColor: Colors.white,
                                                      fillColor: MaterialStateProperty.all(Colors.green),
                                                    );
                                                  } else if (approvalStatus == 'not_approved') {
                                                    // Show checkbox filled with red X for rejected - use custom styled checkbox
                                                    statusIndicator = Container(
                                                      width: 24,
                                                      height: 24,
                                                      decoration: BoxDecoration(
                                                        color: Colors.red.shade700,
                                                        border: Border.all(color: Colors.red.shade900, width: 1.5),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Center(
                                                        child: Icon(
                                                          Icons.close,
                                                          color: Colors.white,
                                                          size: 16,
                                                        ),
                                                      ),
                                                    );
                                                  } else {
                                                    // Show checkbox for pending/submitted items
                                                    // Use blue for selected (not green, as green means approved)
                                                    statusIndicator = Checkbox(
                                                      value: isSelected,
                                                      onChanged: canSelect ? (bool? value) {
                                                        setState(() {
                                                          final itemId = item['id'] as int;
                                                          if (value == true) {
                                                            _selectedCheckItemIds.add(itemId);
                                                          } else {
                                                            _selectedCheckItemIds.remove(itemId);
                                                          }
                                                        });
                                                      } : null,
                                                      activeColor: const Color(0xFF14B8A6), // Teal for selected, green is reserved for approved
                                                    );
                                                  }

                                                  return TableRow(
                                                    children: [
                                                      buildBodyCell(
                                                        statusIndicator,
                                                        alignment: Alignment.center,
                                                      ),
                                                      buildBodyCell(
                                                        Text(
                                                          item['name']?.toString() ?? item['id']?.toString() ?? 'N/A',
                                                          style: baseTextStyle.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFF14B8A6)),
                                                        ),
                                                      ),
                                                      buildBodyCell(Text(item['category'] ?? 'N/A', style: baseTextStyle, overflow: TextOverflow.ellipsis)),
                                                      buildBodyCell(Text(item['sub_category'] ?? 'N/A', style: baseTextStyle, overflow: TextOverflow.ellipsis)),
                                                      buildBodyCell(
                                                        Text(
                                                          item['description'] ?? 'N/A',
                                                          maxLines: 3,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: baseTextStyle,
                                                        ),
                                                      ),
                                                      buildBodyCell(Text(item['severity'] ?? 'N/A', style: baseTextStyle)),
                                                      buildBodyCell(Text(item['bronze'] ?? 'N/A', style: baseTextStyle)),
                                                      buildBodyCell(Text(item['silver'] ?? 'N/A', style: baseTextStyle)),
                                                      buildBodyCell(Text(item['gold'] ?? 'N/A', style: baseTextStyle)),
                                                      buildBodyCell(
                                                        Text(
                                                          item['info'] ?? 'N/A',
                                                          maxLines: 3,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: baseTextStyle,
                                                        ),
                                                      ),
                                                      buildBodyCell(
                                                        Text(
                                                          item['evidence'] ?? 'N/A',
                                                          maxLines: 3,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: baseTextStyle,
                                                        ),
                                                      ),
                                                      buildBodyCell(_buildReportPathCell(reportData?['report_path'], rowIndex)),
                                                      buildBodyCell(
                                                        Text(
                                                          reportData?['result_value'] ?? 'N/A',
                                                          maxLines: 3,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: baseTextStyle,
                                                        ),
                                                      ),
                                                      buildBodyCell(QmsStatusBadge(status: status), alignment: Alignment.center),
                                                      buildBodyCell(
                                                        Text(
                                                          reportData?['engineer_comments'] ?? 'N/A',
                                                          maxLines: 3,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: baseTextStyle,
                                                        ),
                                                      ),
                                                      buildBodyCell(
                                                        Text(
                                                          reportData?['lead_comments'] ?? approval?['comments'] ?? 'N/A',
                                                          maxLines: 3,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: baseTextStyle,
                                                        ),
                                                      ),
                                                      buildBodyCell(
                                                        Text(
                                                          signoffStatus,
                                                          style: baseTextStyle.copyWith(
                                                            color: signoffStatus != 'N/A' ? Colors.green : Colors.grey,
                                                            fontWeight: signoffStatus != 'N/A' ? FontWeight.w500 : FontWeight.normal,
                                                          ),
                                                        ),
                                                      ),
                                                      buildBodyCell(
                                                        Icon(
                                                          autoApprove ? Icons.check_circle : Icons.cancel,
                                                          color: autoApprove ? Colors.green : Colors.grey,
                                                          size: 20,
                                                        ),
                                                        alignment: Alignment.center,
                                                      ),
                                                    ],
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      // Pagination controls
                      if (checkItems.length > _itemsPerPage)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              top: BorderSide(color: Colors.grey.shade200),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                totalItems == 0
                                    ? 'No items to display'
                                    : 'Showing ${_currentPage * _itemsPerPage + 1} to ${(_currentPage + 1) * _itemsPerPage > totalItems ? totalItems : (_currentPage + 1) * _itemsPerPage} of $totalItems items',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 14,
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.first_page),
                                    onPressed: _currentPage == 0
                                        ? null
                                        : () {
                                            setState(() {
                                              _currentPage = 0;
                                            });
                                          },
                                    tooltip: 'First page',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.chevron_left),
                                    onPressed: _currentPage == 0
                                        ? null
                                        : () {
                                            setState(() {
                                              _currentPage--;
                                            });
                                          },
                                    tooltip: 'Previous page',
                                  ),
                                  Text(
                                    totalItems == 0
                                        ? 'Page 0 of 0'
                                        : 'Page ${_currentPage + 1} of ${(totalItems / _itemsPerPage).ceil()}',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.chevron_right),
                                    onPressed: totalItems == 0 || _currentPage >= (totalItems / _itemsPerPage).ceil() - 1
                                        ? null
                                        : () {
                                            setState(() {
                                              _currentPage++;
                                            });
                                          },
                                    tooltip: 'Next page',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.last_page),
                                    onPressed: totalItems == 0 || _currentPage >= (totalItems / _itemsPerPage).ceil() - 1
                                        ? null
                                        : () {
                                            setState(() {
                                              _currentPage = (totalItems / _itemsPerPage).ceil() - 1;
                                            });
                                          },
                                    tooltip: 'Last page',
                                  ),
                                  const SizedBox(width: 16),
                                  DropdownButton<int>(
                                    value: _itemsPerPage,
                                    items: [5, 10, 20, 50, 100].map((int value) {
                                      return DropdownMenuItem<int>(
                                        value: value,
                                        child: Text('$value per page'),
                                      );
                                    }).toList(),
                                    onChanged: (int? newValue) {
                                      if (newValue != null) {
                                        setState(() {
                                          _itemsPerPage = newValue;
                                          _currentPage = 0; // Reset to first page
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      // Approve/Reject Selected Items buttons (only show when items are selected)
                      if (_selectedCheckItemIds.isNotEmpty && checklistStatus == 'submitted_for_approval')
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            border: Border(
                              top: BorderSide(color: Theme.of(context).dividerColor),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${_selectedCheckItemIds.length} item(s) selected',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                              const SizedBox(width: 24),
                              ElevatedButton.icon(
                                onPressed: _isApproving ? null : _approveSelectedCheckItems,
                                icon: const Icon(Icons.check_circle, size: 20),
                                label: const Text('Approve Selected Items'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                ),
                              ),
                              const SizedBox(width: 16),
                              ElevatedButton.icon(
                                onPressed: _isApproving ? null : _rejectSelectedCheckItems,
                                icon: const Icon(Icons.cancel, size: 20),
                                label: const Text('Reject Selected Items'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                        ),
                    ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),

          // Removed inline approver assignment and review sections; actions now live in the AppBar menu
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'submitted':
        return const Color(0xFF14B8A6);
      case 'not_approved':
      case 'rejected':
        return Colors.red;
      case 'in_review':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Icons.check_circle;
      case 'submitted':
        return Icons.send;
      case 'not_approved':
      case 'rejected':
        return Icons.cancel;
      case 'in_review':
        return Icons.visibility;
      default:
        return Icons.pending;
    }
  }

  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return 'N/A';
    try {
      final date = dateValue is String ? DateTime.parse(dateValue) : dateValue as DateTime;
      return DateFormat('MMM dd, yyyy HH:mm').format(date);
    } catch (e) {
      return dateValue.toString();
    }
  }

  List<dynamic> _getPaginatedItems(List<dynamic> items) {
    final startIndex = _currentPage * _itemsPerPage;
    final endIndex = startIndex + _itemsPerPage;
    if (startIndex >= items.length) {
      return [];
    }
    return items.sublist(
      startIndex,
      endIndex > items.length ? items.length : endIndex,
    );
  }

  bool _hasActiveFilters() {
    return _selectedCheckId != null ||
        _selectedCategory != null ||
        _selectedSubCategory != null ||
        _selectedSeverity != null ||
        _selectedBronze != null ||
        _selectedSilver != null ||
        _selectedGold != null ||
        _selectedEvidence != null;
  }

  // Build report path cell with view/copy functionality
  Widget _buildReportPathCell(String? reportPath, int rowIndex) {
    if (reportPath == null || reportPath.isEmpty || reportPath == 'N/A') {
      return Text(
        'N/A',
        style: TextStyle(color: Colors.grey.shade400),
      );
    }

    final isExpanded = _expandedReportPaths[rowIndex] ?? false;
    final displayPath = isExpanded 
        ? reportPath 
        : (reportPath.length > 20 ? '${reportPath.substring(0, 20)}...' : reportPath);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: isExpanded
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    reportPath,
                    style: TextStyle(
                      color: const Color(0xFF14B8A6),
                      fontSize: 13,
                    ),
                  ),
                )
              : Text(
                  displayPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF14B8A6),
                    fontSize: 13,
                  ),
                ),
        ),
        const SizedBox(width: 8),
        // View/Expand button
        IconButton(
          icon: Icon(
            isExpanded ? Icons.visibility_off : Icons.visibility,
            size: 18,
            color: const Color(0xFF14B8A6),
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: 24,
            minHeight: 24,
          ),
          tooltip: isExpanded ? 'Hide full path' : 'View full path',
          onPressed: () {
            setState(() {
              _expandedReportPaths[rowIndex] = !isExpanded;
            });
          },
        ),
        const SizedBox(width: 4),
        // Copy button
        IconButton(
          icon: const Icon(
            Icons.copy,
            size: 18,
            color: Color(0xFF14B8A6),
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: 24,
            minHeight: 24,
          ),
          tooltip: 'Copy path to clipboard',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: reportPath));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Report path copied to clipboard'),
                duration: Duration(seconds: 2),
                backgroundColor: Colors.green,
              ),
            );
          },
        ),
      ],
    );
  }


  // Reusable header filter for DataTable columns
  Widget _buildHeaderFilter({
    required String title,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          padding: EdgeInsets.zero,
          tooltip: 'Filter $title',
          icon: Icon(
            Icons.arrow_drop_down,
            color: Theme.of(context).colorScheme.onSurface,
            size: 18,
          ),
          onSelected: (selected) {
            if (selected == '_clear_') {
              onChanged(null);
            } else {
              onChanged(selected);
            }
          },
          itemBuilder: (context) {
            final items = <PopupMenuEntry<String>>[];

            // Only show clear option if a filter is currently applied
            if (value != null && value.isNotEmpty) {
              items.add(
                const PopupMenuItem<String>(
                  value: '_clear_',
                  child: Text('Clear filter'),
                ),
              );
              items.add(const PopupMenuDivider());
            }

            for (final opt in options) {
              items.add(
                PopupMenuItem<String>(
                  value: opt,
                  child: Text(opt),
                ),
              );
            }

            if (items.isEmpty) {
              items.add(
                const PopupMenuItem<String>(
                  value: '_noop_',
                  enabled: false,
                  child: Text('No values'),
                ),
              );
            }

            return items;
          },
        ),
      ],
    );
  }
}

