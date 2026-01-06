import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/auth_provider.dart';
import '../services/qms_service.dart';
import '../widgets/qms_status_badge.dart';
import 'qms_checklist_detail_screen.dart';

class QmsDashboardScreen extends ConsumerStatefulWidget {
  final int blockId;

  const QmsDashboardScreen({super.key, required this.blockId});

  @override
  ConsumerState<QmsDashboardScreen> createState() => _QmsDashboardScreenState();
}

class _QmsDashboardScreenState extends ConsumerState<QmsDashboardScreen> {
  final QmsService _qmsService = QmsService();
  bool _isLoading = true;
  bool _isUploading = false;
  bool _isSubmitting = false;
  bool _isAssigningApprover = false;
  bool _isApproving = false;
  List<dynamic> _checklists = [];
  Map<String, dynamic>? _blockStatus;
  List<dynamic> _availableApprovers = [];
  int? _selectedApproverId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authState = ref.read(authProvider);
      final token = authState.token;

      if (token == null) {
        throw Exception('Not authenticated');
      }

      final checklists = await _qmsService.getChecklistsForBlock(
        widget.blockId,
        token: token,
      );
      final status = await _qmsService.getBlockStatus(
        widget.blockId,
        token: token,
      );

      setState(() {
        _checklists = checklists;
        _blockStatus = status;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _refreshData() {
    _loadData();
  }

  Future<void> _loadApproversForChecklist(int checklistId) async {
    try {
      final authState = ref.read(authProvider);
      final token = authState.token;
      if (token == null) return;

      final approvers = await _qmsService.getApproversForChecklist(
        checklistId,
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

  void _showUploadDialog() {
    final checklistNameController = TextEditingController();
    final fileNameController = TextEditingController();
    String? selectedFileName;
    List<int>? fileBytes;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Upload Template'),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                  ),
                ],
              ),
              contentPadding: const EdgeInsets.fromLTRB(34, 30, 34, 34),
              content: SizedBox(
                width: 410,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: checklistNameController,
                        decoration: const InputDecoration(
                          labelText: 'Checklist Name *',
                          hintText: 'Enter checklist name',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.list_alt),
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        readOnly: true,
                        controller: fileNameController,
                        decoration: InputDecoration(
                          labelText: 'Select File *',
                          hintText: 'No file selected',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.attach_file),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          suffixIcon: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                FilePickerResult? result = await FilePicker.platform.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: ['xlsx', 'xls'],
                                  withData: true,
                                );

                                if (result != null && result.files.isNotEmpty) {
                                  final file = result.files.first;
                                  if (file.bytes != null) {
                                    setDialogState(() {
                                      selectedFileName = file.name;
                                      fileBytes = file.bytes;
                                      fileNameController.text = file.name;
                                    });
                                  }
                                }
                              },
                              icon: const Icon(Icons.browse_gallery, size: 18),
                              label: const Text('Browse'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (selectedFileName != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                selectedFileName!,
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: (checklistNameController.text.trim().isEmpty || fileBytes == null)
                      ? null
                      : () async {
                          Navigator.pop(context);
                          await _uploadTemplate(
                            checklistNameController.text.trim(),
                            fileBytes!,
                            selectedFileName!,
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade600,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAssignApproverDialog(Map<String, dynamic> checklist) {
    _selectedApproverId = null;
    _availableApprovers = [];
    bool hasRequested = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (!hasRequested) {
              hasRequested = true;
              _loadApproversForChecklist(checklist['id']).then((_) {
                if (mounted) setDialogState(() {});
              });
            }

            return AlertDialog(
              title: const Text('Assign Approver'),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      checklist['name'] ?? 'Checklist',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
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
                  onPressed: (_selectedApproverId == null || _isAssigningApprover)
                      ? null
                      : () async {
                          setState(() {
                            _isAssigningApprover = true;
                          });
                          try {
                            final authState = ref.read(authProvider);
                            final token = authState.token;
                            if (token == null) throw Exception('Not authenticated');

                            await _qmsService.assignApproverToChecklist(
                              checklist['id'],
                              _selectedApproverId!,
                              token: token,
                            );

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Approver updated successfully'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                            _refreshData();
                            if (context.mounted) Navigator.pop(context);
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

  Future<void> _uploadTemplate(String checklistName, List<int> fileBytes, String fileName) async {
    try {
      setState(() {
        _isUploading = true;
      });

      final authState = ref.read(authProvider);
      final token = authState.token;

      if (token == null) {
        throw Exception('Not authenticated');
      }

      // Upload file
      await _qmsService.uploadTemplate(
        widget.blockId,
        fileBytes,
        fileName,
        checklistName: checklistName,
        token: token,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Template uploaded successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading template: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('QMS Dashboard'),
        elevation: 0,
        actions: [
          // Only show upload button for admin, project_manager, and lead
          Builder(
            builder: (context) {
              final authState = ref.read(authProvider);
              final userRole = authState.user?['role'];
              final canUpload = userRole == 'admin' || userRole == 'project_manager' || userRole == 'lead';
              
              if (canUpload) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: ElevatedButton.icon(
                    onPressed: _isUploading ? null : _showUploadDialog,
                    icon: _isUploading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.upload_file, size: 18),
                    label: Text(_isUploading ? 'Uploading...' : 'Upload Template'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(0, 36),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          const SizedBox(width: 5),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Block status summary
              if (_blockStatus != null) ...[
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _blockStatus!['all_checklists_submitted'] == true
                                  ? Icons.check_circle
                                  : Icons.info,
                              color: _blockStatus!['all_checklists_submitted'] == true
                                  ? Colors.green
                                  : Colors.blue,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Block Status',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _blockStatus!['all_checklists_submitted'] == true
                              ? 'Block Submitted'
                              : 'Some checklists pending',
                          style: TextStyle(
                            color: _blockStatus!['all_checklists_submitted'] == true
                                ? Colors.green
                                : Colors.orange,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Checklists table
              Text(
                'Checklists (${_checklists.length})',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              
              if (_checklists.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(
                      child: Text(
                        'No checklists found for this block',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                )
              else
                Card(
                  elevation: 4,
                  color: Colors.grey.shade100,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      showCheckboxColumn: false,
                      headingRowColor: MaterialStateProperty.all(const Color(0xFF4A148C)),
                      headingTextStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      dataRowMinHeight: 52,
                      dataRowMaxHeight: 60,
                      columnSpacing: 28,
                      columns: const [
                        DataColumn(label: Text('S.No')),
                        DataColumn(label: Text('Name')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Stage')),
                        DataColumn(label: Text('Milestone')),
                        DataColumn(label: Text('CheckItems Count')),
                        DataColumn(label: Text('Approver Name')),
                        DataColumn(label: Text('Submitted Date')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: _checklists.asMap().entries.map((entry) {
                        final index = entry.key;
                        final checklist = entry.value;
                        final totalItems = checklist['total_items'] ?? 0;
                        final approverName = checklist['approver_name'];
                        final submittedAt = checklist['submitted_at'];
                        final isStriped = index.isEven;
                        final baseTextStyle = TextStyle(fontSize: 15, color: Colors.grey.shade900);
                        
                        return DataRow(
                          color: MaterialStateProperty.all(isStriped ? Colors.grey.shade50 : Colors.white),
                          cells: [
                            DataCell(Text('${index + 1}', style: baseTextStyle)),
                            DataCell(
                              Text(
                                checklist['name'] ?? 'Unnamed Checklist',
                                style: baseTextStyle.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            DataCell(
                              QmsStatusBadge(status: checklist['status'] ?? 'draft'),
                            ),
                            DataCell(
                              Text(checklist['stage'] ?? 'N/A', style: baseTextStyle),
                            ),
                            DataCell(
                              Text(checklist['milestone_name'] ?? 'N/A', style: baseTextStyle),
                            ),
                            DataCell(
                              Text('$totalItems', style: baseTextStyle),
                            ),
                            DataCell(
                              Text(
                                approverName ?? 'Not assigned',
                                style: baseTextStyle.copyWith(
                                  color: approverName != null ? Colors.black87 : Colors.grey,
                                  fontStyle: approverName != null ? FontStyle.normal : FontStyle.italic,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                submittedAt != null
                                    ? _formatDate(submittedAt)
                                    : 'N/A',
                                style: baseTextStyle.copyWith(
                                  color: submittedAt != null ? Colors.black87 : Colors.grey,
                                ),
                              ),
                            ),
                            DataCell(
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, size: 20),
                                onSelected: (value) {
                                  if (value == 'view') {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => QmsChecklistDetailScreen(
                                          checklistId: checklist['id'],
                                        ),
                                      ),
                                    ).then((_) => _refreshData());
                                  } else if (value == 'submit') {
                                    _showSubmitDialog(checklist);
                                  } else if (value == 'approve') {
                                    _showApproveDialog(checklist);
                                  } else if (value == 'assign') {
                                    _showAssignApproverDialog(checklist);
                                  }
                                },
                                itemBuilder: (context) {
                                  final authState = ref.read(authProvider);
                                  final userRole = authState.user?['role'];
                                  final rawStatus = (checklist['status'] ?? 'draft').toString().toLowerCase();
                                  final isDraft = rawStatus == 'draft';
                                  final isSubmittedForApproval = rawStatus == 'submitted_for_approval' || rawStatus == 'submitted for approval';
                                  final isEngineerOrAdmin = userRole == 'engineer' || userRole == 'admin';
                                  final isApprover = _isApprover(checklist);
                                  final canAssignApprover = (userRole == 'lead' || userRole == 'admin') && isSubmittedForApproval;
                                  
                                  final items = <PopupMenuEntry<String>>[];
                                  
                                  items.add(
                                    const PopupMenuItem<String>(
                                      value: 'view',
                                      child: Row(
                                        children: [
                                          Icon(Icons.visibility, size: 18),
                                          SizedBox(width: 8),
                                          Text('View'),
                                        ],
                                      ),
                                    ),
                                  );
                                  
                                  // Draft: allow submit
                                  if (isEngineerOrAdmin && isDraft) {
                                    items.add(
                                      const PopupMenuItem<String>(
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
                                  
                                  // Submitted for approval: allow approver change
                                  if (canAssignApprover) {
                                    items.add(
                                      const PopupMenuItem<String>(
                                        value: 'assign',
                                        child: Row(
                                          children: [
                                            Icon(Icons.swap_horiz, size: 18),
                                            SizedBox(width: 8),
                                            Text('Assign Approver'),
                                          ],
                                        ),
                                      ),
                                    );
                                  }
                                  
                                  // Submitted for approval: approver can approve/reject
                                  if (isApprover && isSubmittedForApproval) {
                                    items.add(
                                      const PopupMenuItem<String>(
                                        value: 'approve',
                                        child: Row(
                                          children: [
                                            Icon(Icons.rate_review, size: 18),
                                            SizedBox(width: 8),
                                            Text('Approve/Reject'),
                                          ],
                                        ),
                                      ),
                                    );
                                  }
                                  
                                  return items;
                                },
                              ),
                            ),
                          ],
                          onSelectChanged: (selected) {
                            if (selected == true) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => QmsChecklistDetailScreen(
                                    checklistId: checklist['id'],
                                  ),
                                ),
                              ).then((_) => _refreshData());
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitChecklist(int checklistId, {String? engineerComments}) async {
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
      await _qmsService.submitChecklist(
        checklistId,
        engineerComments: engineerComments,
        token: token,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Checklist submitted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _refreshData();
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

  void _showSubmitDialog(Map<String, dynamic> checklist) {
    final commentsController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Submit Checklist for Approval'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Checklist: ${checklist['name'] ?? 'Unnamed'}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: commentsController,
                      decoration: const InputDecoration(
                        labelText: 'Comments (optional)',
                        hintText: 'Add your engineer comments...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.comment),
                      ),
                      maxLines: 3,
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
                  onPressed: _isSubmitting
                      ? null
                      : () async {
                          Navigator.pop(context);
                          await _submitChecklist(
                            checklist['id'],
                            engineerComments: commentsController.text.trim().isEmpty
                                ? null
                                : commentsController.text.trim(),
                          );
                        },
                  child: Text(_isSubmitting ? 'Submitting...' : 'Submit for Approval'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'submitted':
        return Colors.green;
      case 'approved':
        return Colors.blue;
      case 'draft':
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'submitted':
        return Icons.check_circle;
      case 'approved':
        return Icons.verified;
      case 'draft':
      default:
        return Icons.edit;
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

  bool _isApprover(Map<String, dynamic> checklist) {
    final authState = ref.read(authProvider);
    final user = authState.user;
    final role = user?['role'];
    
    // Admins can always approve
    if (role == 'admin') return true;
    
    final userId = user?['id'];
    if (userId == null) return false;
    
    // Check if user is the assigned approver
    final assignedApproverId = checklist['assigned_approver_id'];
    if (assignedApproverId != null && assignedApproverId == userId) {
      return true;
    }
    
    // Leads and project managers can also approve
    return role == 'lead' || role == 'project_manager';
  }

  void _showApproveDialog(Map<String, dynamic> checklist) {
    final commentsController = TextEditingController();
    bool? approved;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Approve/Reject Checklist'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Checklist: ${checklist['name'] ?? 'Unnamed'}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: commentsController,
                      decoration: const InputDecoration(
                        labelText: 'Comments (optional)',
                        hintText: 'Add your review comments...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.comment),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Decision:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<bool>(
                            title: const Text('Approve'),
                            value: true,
                            groupValue: approved,
                            onChanged: (value) {
                              setDialogState(() {
                                approved = value;
                              });
                            },
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<bool>(
                            title: const Text('Reject'),
                            value: false,
                            groupValue: approved,
                            onChanged: (value) {
                              setDialogState(() {
                                approved = value;
                              });
                            },
                          ),
                        ),
                      ],
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
                  onPressed: approved == null
                      ? null
                      : () async {
                          Navigator.pop(context);
                          await _approveChecklist(
                            checklist['id'],
                            approved!,
                            commentsController.text.trim().isEmpty
                                ? null
                                : commentsController.text.trim(),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: approved == true ? Colors.green : Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(approved == true ? 'Approve' : approved == false ? 'Reject' : 'Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _approveChecklist(int checklistId, bool approved, String? comments) async {
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
      _isApproving = true;
    });

    try {
      await _qmsService.approveChecklist(
        checklistId,
        approved,
        comments: comments,
        token: token,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Checklist ${approved ? 'approved' : 'rejected'} successfully'),
            backgroundColor: approved ? Colors.green : Colors.orange,
          ),
        );
        _refreshData();
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
}

