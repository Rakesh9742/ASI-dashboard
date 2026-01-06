import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../services/qms_service.dart';
import '../widgets/qms_status_badge.dart';
import 'qms_check_item_detail_screen.dart';

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
    if (_checklist == null) return false;
    final authState = ref.read(authProvider);
    final user = authState.user;
    final role = user?['role'];
    
    // Admins can always approve
    if (role == 'admin') return true;
    
    final userId = user?['id'];
    if (userId == null) return false;

    final checkItems = _checklist!['check_items'] as List?;
    if (checkItems == null || checkItems.isEmpty) return false;

    // Check if user is assigned approver for all items
    return checkItems.every((item) {
      final approval = item['approval'];
      if (approval == null) return false;
      final assignedApproverId = approval['assigned_approver_id'];
      final defaultApproverId = approval['default_approver_id'];
      return assignedApproverId == userId || defaultApproverId == userId;
    });
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

  Future<void> _approveChecklist(bool approved) async {
    final authState = ref.read(authProvider);
    final token = authState.token;
    if (token == null) return;

    setState(() {
      _isApproving = true;
    });

    try {
      await _qmsService.approveChecklist(
        widget.checklistId,
        approved,
        comments: _approvalCommentsController.text.isNotEmpty
            ? _approvalCommentsController.text
            : null,
        token: token,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Checklist ${approved ? 'approved' : 'rejected'} successfully'),
            backgroundColor: approved ? Colors.green : Colors.orange,
          ),
        );
        _approvalCommentsController.clear();
        _loadChecklist();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error ${approved ? 'approving' : 'rejecting'} checklist: $e'),
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
    final paginatedItems = _getPaginatedItems(checkItems);
    final startIndex = _currentPage * _itemsPerPage;

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
              } else if (value == 'approve') {
                _approveChecklist(true);
              } else if (value == 'reject') {
                _approveChecklist(false);
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
                items.addAll([
                  const PopupMenuItem(
                    value: 'approve',
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, size: 18),
                        SizedBox(width: 8),
                        Text('Approve'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'reject',
                    child: Row(
                      children: [
                        Icon(Icons.cancel, size: 18),
                        SizedBox(width: 8),
                        Text('Reject'),
                      ],
                    ),
                  ),
                ]);
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
          // Checklist header
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.grey.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _checklist!['name'] ?? 'Unnamed Checklist',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    QmsStatusBadge(status: checklistStatus),
                  ],
                ),
                if (_checklist!['stage'] != null) ...[
                  const SizedBox(height: 8),
                  Text('Stage: ${_checklist!['stage']}'),
                ],
                if (_checklist!['milestone_name'] != null) ...[
                  const SizedBox(height: 4),
                  Text('Milestone: ${_checklist!['milestone_name']}'),
                ],
                // Show submission info
                if (_checklist!['submitted_by'] != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.person, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        'Submitted by: ${_checklist!['submitted_by_name'] ?? 'User ID ${_checklist!['submitted_by']}'}',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                      ),
                    ],
                  ),
                ],
                if (_checklist!['submitted_at'] != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        'Submitted at: ${_formatDate(_checklist!['submitted_at'])}',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                      ),
                    ],
                  ),
                ],
                // Show current approver
                if (checklistStatus == 'submitted_for_approval') ...[
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final checkItems = _checklist!['check_items'] as List? ?? [];
                      String approverName = 'Not assigned';
                      if (checkItems.isNotEmpty) {
                        final firstItem = checkItems[0];
                        final approval = firstItem['approval'];
                        if (approval != null) {
                          approverName = approval['assigned_approver_name'] ?? 
                                        approval['default_approver_name'] ?? 
                                        'Not assigned';
                        }
                      }
                      return Row(
                        children: [
                          Icon(Icons.verified_user, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            'Approver: $approverName',
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),

          // Check items table
          Expanded(
            child: checkItems.isEmpty
                ? const Center(
                    child: Text(
                      'No check items found',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Scrollbar(
                            controller: _verticalScrollController,
                            thumbVisibility: true,
                            thickness: 8,
                            radius: const Radius.circular(4),
                            child: Scrollbar(
                              controller: _horizontalScrollController,
                              thumbVisibility: true,
                              thickness: 8,
                              radius: const Radius.circular(4),
                              notificationPredicate: (notification) => notification.depth == 1,
                              child: SingleChildScrollView(
                                controller: _horizontalScrollController,
                                scrollDirection: Axis.horizontal,
                                child: SingleChildScrollView(
                                  controller: _verticalScrollController,
                                  child: DataTable(
                                    showCheckboxColumn: false,
                                    headingRowColor: MaterialStateProperty.all(const Color(0xFF6A1B9A)), // Royal purple
                                    headingRowHeight: 56,
                                    dataRowMinHeight: 64,
                                    dataRowMaxHeight: 80,
                                    columnSpacing: 24,
                                    headingTextStyle: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    columns: const [
                                      DataColumn(label: Text('S.No', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
                                      DataColumn(label: Text('Check ID', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
                                      DataColumn(label: Text('Category', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
                                      DataColumn(label: Text('Sub-Category', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
                                      DataColumn(label: Text('Check Description', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
                                      DataColumn(label: Text('Severity', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
                                      DataColumn(label: Text('Bronze', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
                                      DataColumn(label: Text('Silver', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
                                      DataColumn(label: Text('Gold', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
                                      DataColumn(label: Text('Info', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
                                      DataColumn(label: Text('Evidence', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
                                      DataColumn(label: Text('Report Path', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
                                      DataColumn(label: Text('Result/Value', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
                                      DataColumn(label: Text('Status', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
                                      DataColumn(label: Text('Comments', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
                                      DataColumn(label: Text('Reviewer Comments', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
                                      DataColumn(label: Text('Signoff', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
                                      DataColumn(label: Text('Auto', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
                                    ],
                                    rows: paginatedItems.asMap().entries.map((entry) {
                          final rowIndex = startIndex + entry.key + 1;
                          final item = entry.value;
                          final reportData = item['report_data'];
                          final approval = item['approval'];
                          final status = reportData?['status'] ?? 'pending';
                          final signoffStatus = reportData?['signoff_status'] ?? 'N/A';
                          final autoApprove = item['auto_approve'] ?? false;
                          
                          // Get approver name from approval object
                          String approverName = 'Not assigned';
                          if (approval != null) {
                            if (approval['assigned_approver_name'] != null) {
                              approverName = approval['assigned_approver_name'];
                            } else if (approval['default_approver_name'] != null) {
                              approverName = approval['default_approver_name'];
                            } else if (approval['assigned_approver_id'] != null) {
                              approverName = 'Assigned';
                            } else if (approval['default_approver_id'] != null) {
                              approverName = 'Default';
                            }
                          }
                          
                          final submittedAt = approval?['submitted_at'];

                          return DataRow(
                            cells: [
                              // Serial number
                              DataCell(
                                Text('$rowIndex'),
                              ),
                              // Check ID - show the name field which contains the Excel Check ID
                              DataCell(
                                Text(
                                  item['name']?.toString() ?? item['id']?.toString() ?? 'N/A',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ),
                              // Category
                              DataCell(
                                Text(item['category'] ?? 'N/A'),
                              ),
                              // Sub-Category
                              DataCell(
                                Text(item['sub_category'] ?? 'N/A'),
                              ),
                              // Check Description
                              DataCell(
                                Text(
                                  item['description'] ?? 'N/A',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // Severity
                              DataCell(
                                Text(item['severity'] ?? 'N/A'),
                              ),
                              // Bronze
                              DataCell(
                                Text(item['bronze'] ?? 'N/A'),
                              ),
                              // Silver
                              DataCell(
                                Text(item['silver'] ?? 'N/A'),
                              ),
                              // Gold
                              DataCell(
                                Text(item['gold'] ?? 'N/A'),
                              ),
                              // Info
                              DataCell(
                                Text(
                                  item['info'] ?? 'N/A',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // Evidence
                              DataCell(
                                Text(
                                  item['evidence'] ?? 'N/A',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // Report Path
                              DataCell(
                                Text(
                                  reportData?['report_path'] ?? 'N/A',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: reportData?['report_path'] != null 
                                        ? Colors.blue 
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                              // Result/Value
                              DataCell(
                                Text(
                                  reportData?['result_value'] ?? 'N/A',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // Status
                              DataCell(
                                QmsStatusBadge(status: status),
                              ),
                              // Comments (Engineer Comments)
                              DataCell(
                                Text(
                                  reportData?['engineer_comments'] ?? 'N/A',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // Reviewer Comments
                              DataCell(
                                Text(
                                  reportData?['lead_comments'] ?? approval?['comments'] ?? 'N/A',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // Signoff
                              DataCell(
                                Text(
                                  signoffStatus,
                                  style: TextStyle(
                                    color: signoffStatus != 'N/A' ? Colors.green : Colors.grey,
                                    fontWeight: signoffStatus != 'N/A' ? FontWeight.w500 : FontWeight.normal,
                                  ),
                                ),
                              ),
                              // Auto
                              DataCell(
                                Icon(
                                  autoApprove ? Icons.check_circle : Icons.cancel,
                                  color: autoApprove ? Colors.green : Colors.grey,
                                  size: 20,
                                ),
                              ),
                            ],
                            onSelectChanged: (selected) {
                              if (selected == true) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => QmsCheckItemDetailScreen(
                                      checkItemId: item['id'],
                                    ),
                                  ),
                                ).then((_) => _loadChecklist());
                              }
                            },
                          );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),
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
                                'Showing ${_currentPage * _itemsPerPage + 1} to ${(_currentPage + 1) * _itemsPerPage > checkItems.length ? checkItems.length : (_currentPage + 1) * _itemsPerPage} of ${checkItems.length} items',
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
                                    'Page ${_currentPage + 1} of ${(checkItems.length / _itemsPerPage).ceil()}',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.chevron_right),
                                    onPressed: _currentPage >= (checkItems.length / _itemsPerPage).ceil() - 1
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
                                    onPressed: _currentPage >= (checkItems.length / _itemsPerPage).ceil() - 1
                                        ? null
                                        : () {
                                            setState(() {
                                              _currentPage = (checkItems.length / _itemsPerPage).ceil() - 1;
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
                    ],
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
        return Colors.blue;
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
}

