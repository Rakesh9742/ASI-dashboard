import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: LayoutBuilder(
                            builder: (context, outerConstraints) {
                              // Define explicit column widths to ensure perfect alignment
                              const double colSNo = 60;
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
                              const double colStatus = 200;
                              const double colComments = 200;
                              const double colReviewerComments = 200;
                              const double colSignoff = 120;
                              const double colAuto = 80;

                              const double totalWidth = colSNo + colCheckId + colCategory + colSubCategory + colDescription + colSeverity + colBronze + colSilver + colGold + colInfo + colEvidence + colReportPath + colResult + colStatus + colComments + colReviewerComments + colSignoff + colAuto;

                              final columnWidths = {
                                0: const FixedColumnWidth(colSNo),
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
                                          color: Colors.grey.shade900,
                                          child: Table(
                                            columnWidths: columnWidths,
                                            children: [
                                              TableRow(
                                                children: [
                                                  buildHeaderCell(const Text('S.No', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                                                  buildHeaderCell(_buildHeaderFilter(title: 'Check ID', value: _selectedCheckId, options: checkIdOptions, onChanged: (v) => setState(() { _selectedCheckId = v; _currentPage = 0; }))),
                                                  buildHeaderCell(_buildHeaderFilter(title: 'Category', value: _selectedCategory, options: categoryOptions, onChanged: (v) => setState(() { _selectedCategory = v; _currentPage = 0; }))),
                                                  buildHeaderCell(_buildHeaderFilter(title: 'Sub-Category', value: _selectedSubCategory, options: subCategoryOptions, onChanged: (v) => setState(() { _selectedSubCategory = v; _currentPage = 0; }))),
                                                  buildHeaderCell(const Text('Check Description', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                                                  buildHeaderCell(_buildHeaderFilter(title: 'Severity', value: _selectedSeverity, options: severityOptions, onChanged: (v) => setState(() { _selectedSeverity = v; _currentPage = 0; }))),
                                                  buildHeaderCell(_buildHeaderFilter(title: 'Bronze', value: _selectedBronze, options: bronzeOptions, onChanged: (v) => setState(() { _selectedBronze = v; _currentPage = 0; }))),
                                                  buildHeaderCell(_buildHeaderFilter(title: 'Silver', value: _selectedSilver, options: silverOptions, onChanged: (v) => setState(() { _selectedSilver = v; _currentPage = 0; }))),
                                                  buildHeaderCell(_buildHeaderFilter(title: 'Gold', value: _selectedGold, options: goldOptions, onChanged: (v) => setState(() { _selectedGold = v; _currentPage = 0; }))),
                                                  buildHeaderCell(const Text('Info', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                                                  buildHeaderCell(_buildHeaderFilter(title: 'Evidence', value: _selectedEvidence, options: evidenceOptions, onChanged: (v) => setState(() { _selectedEvidence = v; _currentPage = 0; }))),
                                                  buildHeaderCell(const Text('Report Path', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                                                  buildHeaderCell(const Text('Result/Value', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                                                  buildHeaderCell(const Text('Status', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                                                  buildHeaderCell(const Text('Comments', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                                                  buildHeaderCell(const Text('Reviewer Comments', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                                                  buildHeaderCell(const Text('Signoff', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                                                  buildHeaderCell(const Text('Auto', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
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
                                                      child: InkWell(
                                                        onTap: onTap ?? () {
                                                          Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                              builder: (context) => QmsCheckItemDetailScreen(
                                                                checkItemId: item['id'],
                                                              ),
                                                            ),
                                                          ).then((_) => _loadChecklist());
                                                        },
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
                                                      ),
                                                    );
                                                  }

                                                  return TableRow(
                                                    children: [
                                                      buildBodyCell(Text('$rowIndex', style: baseTextStyle.copyWith(color: Colors.grey.shade600))),
                                                      buildBodyCell(
                                                        Text(
                                                          item['name']?.toString() ?? item['id']?.toString() ?? 'N/A',
                                                          style: baseTextStyle.copyWith(fontWeight: FontWeight.w600, color: Colors.purple.shade900),
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
                      color: Colors.blue.shade700,
                      fontSize: 13,
                    ),
                  ),
                )
              : Text(
                  displayPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.blue.shade700,
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
            color: Colors.blue.shade700,
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
            color: Colors.blue,
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
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          padding: EdgeInsets.zero,
          tooltip: 'Filter $title',
          icon: const Icon(
            Icons.arrow_drop_down,
            color: Colors.white,
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

