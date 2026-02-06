import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/auth_provider.dart';
import '../services/qms_service.dart';
import '../widgets/qms_status_badge.dart';
import '../widgets/qms_history_dialog.dart';
import 'qms_checklist_detail_screen.dart';

// ASI Brand colors to match projects theme
const Color _kBrandPrimary = Color(0xFF6366F1); // Indigo
const Color _kBrandSecondary = Color(0xFF4F46E5); // Darker indigo
const Color _kBrandAccent = Color(0xFF14B8A6); // Teal accent
const Color _kSuccessGreen = Color(0xFF10B981);
const Color _kDangerRed = Color(0xFFEF4444);
const Color _kWarningOrange = Color(0xFFF59E0B);

class QmsDashboardScreen extends ConsumerStatefulWidget {
  final int blockId;
  final bool isStandalone;

  const QmsDashboardScreen({
    super.key,
    required this.blockId,
    this.isStandalone = false,
  });

  @override
  ConsumerState<QmsDashboardScreen> createState() => QmsDashboardScreenState();
}

class QmsDashboardScreenState extends ConsumerState<QmsDashboardScreen> {
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
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void refreshData() {
    _refreshData();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
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

  void _showHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => QmsHistoryDialog(blockId: widget.blockId),
    );
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
                    backgroundColor: _kBrandPrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
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
      appBar: widget.isStandalone
          ? null
          : AppBar(
              title: const Text('QMS Dashboard'),
              elevation: 0,
              actions: [
                // Template Settings (Admin only)
                if (ref.read(authProvider).user?['role'] == 'admin')
                  IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: _showTemplateSettings,
                    tooltip: 'Template Settings',
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: refreshData,
                  tooltip: 'Refresh',
                ),
              ],
            ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Section (New)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'QMS Management',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Monitor and approve quality checklists',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                            ),
                      ),
                    ],
                  ),
                  // Upload button and Block History button
                  Row(
                    children: [
                      // Block History button (always visible)
                      OutlinedButton.icon(
                        onPressed: () {
                          _showHistoryDialog();
                        },
                        icon: const Icon(Icons.history, size: 18),
                        label: const Text('Block History'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kBrandPrimary,
                          side: BorderSide(color: _kBrandPrimary.withOpacity(0.5)),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Upload Template button (only for admin, project_manager, lead)
                      Builder(
                        builder: (context) {
                          final authState = ref.read(authProvider);
                          final userRole = authState.user?['role'];
                          final canUpload = userRole == 'admin' || userRole == 'project_manager' || userRole == 'lead';
                          
                          if (canUpload) {
                            return ElevatedButton.icon(
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
                                backgroundColor: _kBrandPrimary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                                shadowColor: _kBrandPrimary.withOpacity(0.3),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),
              // Block status summary
              if (_blockStatus != null) ...[
                Container(
                  padding: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (_blockStatus!['all_checklists_approved'] == true
                                  ? _kSuccessGreen
                                  : (_blockStatus!['all_checklists_submitted'] == true
                                      ? _kBrandPrimary
                                      : _kWarningOrange))
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _blockStatus!['all_checklists_approved'] == true
                              ? Icons.check_circle_rounded
                              : (_blockStatus!['all_checklists_submitted'] == true
                                  ? Icons.pending_actions_rounded
                                  : Icons.info_rounded),
                          color: _blockStatus!['all_checklists_approved'] == true
                              ? _kSuccessGreen
                              : (_blockStatus!['all_checklists_submitted'] == true
                                  ? _kBrandPrimary
                                  : _kWarningOrange),
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Block Status',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _blockStatus!['all_checklists_approved'] == true
                                  ? 'All Checklists Completed'
                                  : (_blockStatus!['all_checklists_submitted'] == true
                                      ? 'All Checklists Submitted'
                                      : 'Checklists In Progress'),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],

              // Checklists table
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _kBrandPrimary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.checklist_rounded, color: _kBrandPrimary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Quality Checklists',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: _kBrandPrimary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${_checklists.length}',
                      style: TextStyle(
                        color: _kBrandPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              if (_checklists.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.folder_open_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No checklists found for this block',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                )
               else
                 Container(
                   decoration: BoxDecoration(
                     color: Theme.of(context).cardColor,
                     borderRadius: BorderRadius.circular(16),
                     border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
                     boxShadow: [
                       BoxShadow(
                         color: Colors.black.withOpacity(0.04),
                         blurRadius: 10,
                         offset: const Offset(0, 2),
                       ),
                     ],
                   ),
                  child: SizedBox(
                    height: 56 + (5 * 64), // Header height + 5 rows height
                    child: LayoutBuilder(
                      builder: (context, outerConstraints) {
                        // Define explicit column widths to ensure perfect alignment
                        const double colSNo = 60;
                        const double colName = 250;
                        const double colStatus = 260;
                        const double colMilestone = 150;
                        const double colCount = 150;
                        const double colApproverName = 180;
                        const double colApproverRole = 140;
                        const double colEngineerComments = 200;
                        // const double colReviewerComments = 200; // Commented out for now
                        const double colDate = 200;
                        const double colActions = 80;
                        const double totalWidth = colSNo + colName + colStatus + colMilestone + colCount + colApproverName + colApproverRole + colEngineerComments + /* colReviewerComments + */ colDate + colActions;

                        final columnWidths = {
                          0: const FixedColumnWidth(colSNo),
                          1: const FixedColumnWidth(colName),
                          2: const FixedColumnWidth(colStatus),
                          3: const FixedColumnWidth(colMilestone),
                          4: const FixedColumnWidth(colCount),
                          5: const FixedColumnWidth(colApproverName),
                          6: const FixedColumnWidth(colApproverRole),
                          7: const FixedColumnWidth(colEngineerComments),
                          // 8: const FixedColumnWidth(colReviewerComments), // Commented out for now
                          8: const FixedColumnWidth(colDate),
                          9: const FixedColumnWidth(colActions),
                        };

                        Widget buildHeaderCell(String label) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
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
                                  // Sticky Header
                                  Container(
                                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    child: Table(
                                      columnWidths: columnWidths,
                                      children: [
                                        TableRow(
                                          children: [
                                            buildHeaderCell('S.No'),
                                            buildHeaderCell('Name'),
                                            buildHeaderCell('Status'),
                                            buildHeaderCell('Milestone'),
                                            buildHeaderCell('CheckItems Count'),
                                            buildHeaderCell('Approver Name'),
                                            buildHeaderCell('Approver Role'),
                                            buildHeaderCell('Engineer Comments'),
                                            // buildHeaderCell('Reviewer Comments'), // Commented out for now
                                            buildHeaderCell('Submitted Date'),
                                            buildHeaderCell('Actions'),
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
                                          children: _checklists.asMap().entries.map((entry) {
                                            final index = entry.key;
                                            final checklist = entry.value;
                                            final totalItems = checklist['total_items'] ?? 0;
                                            final approverName = checklist['approver_name'];
                                            final approverRole = (checklist['approver_role'] ?? 'N/A').toString();
                                            final submittedAt = checklist['submitted_at'];
                                            
                                            const baseTextStyle = TextStyle(
                                              fontSize: 13,
                                              color: Colors.black87,
                                              fontWeight: FontWeight.w400,
                                            );

                                            Widget buildBodyCell(Widget child, {Alignment alignment = Alignment.centerLeft}) {
                                              return Container(
                                                height: 64,
                                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                                alignment: alignment,
                                                decoration: BoxDecoration(
                                                  border: Border(
                                                    bottom: BorderSide(color: Colors.grey.shade100),
                                                  ),
                                                ),
                                                child: child,
                                              );
                                            }

                                            return TableRow(
                                              children: [
                                                buildBodyCell(Text('${index + 1}', style: baseTextStyle.copyWith(color: Colors.grey.shade600))),
                                                buildBodyCell(
                                                  InkWell(
                                                    onTap: () {
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (context) => QmsChecklistDetailScreen(
                                                            checklistId: checklist['id'],
                                                          ),
                                                        ),
                                                      ).then((_) => _refreshData());
                                                    },
                                                    child: Text(
                                                      checklist['name'] ?? 'Unnamed Checklist',
                                                      style: baseTextStyle.copyWith(
                                                        fontWeight: FontWeight.w600,
                                                        color: _kBrandPrimary,
                                                        decoration: TextDecoration.underline,
                                                        decorationColor: _kBrandPrimary.withOpacity(0.4),
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ),
                                                buildBodyCell(QmsStatusBadge(status: checklist['status'] ?? 'draft')),
                                                buildBodyCell(Text(checklist['milestone_name'] ?? 'N/A', style: baseTextStyle, overflow: TextOverflow.ellipsis)),
                                                buildBodyCell(Text('$totalItems', style: baseTextStyle)),
                                                buildBodyCell(
                                                  Text(
                                                    approverName ?? 'Not assigned',
                                                    style: baseTextStyle.copyWith(
                                                      color: approverName != null ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                                                      fontStyle: approverName != null ? FontStyle.normal : FontStyle.italic,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                buildBodyCell(_buildRoleChip(approverRole)),
                                                buildBodyCell(
                                                  Text(
                                                    checklist['engineer_comments'] ?? 'N/A',
                                                    style: baseTextStyle.copyWith(
                                                      color: checklist['engineer_comments'] != null ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                                                      fontStyle: checklist['engineer_comments'] != null ? FontStyle.normal : FontStyle.italic,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                    maxLines: 2,
                                                  ),
                                                ),
                                                // buildBodyCell(
                                                //   Text(
                                                //     checklist['reviewer_comments'] ?? 'N/A',
                                                //     style: baseTextStyle.copyWith(
                                                //       color: checklist['reviewer_comments'] != null ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                                                //       fontStyle: checklist['reviewer_comments'] != null ? FontStyle.normal : FontStyle.italic,
                                                //     ),
                                                //     overflow: TextOverflow.ellipsis,
                                                //     maxLines: 2,
                                                //   ),
                                                // ), // Commented out for now
                                                buildBodyCell(
                                                  Text(
                                                    submittedAt != null ? _formatDate(submittedAt) : 'N/A',
                                                    style: baseTextStyle.copyWith(
                                                      color: submittedAt != null ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                buildBodyCell(
                                                  PopupMenuButton<String>(
                                                    icon: Icon(Icons.more_vert, size: 20, color: Colors.grey.shade700),
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
                                                      } else if (value == 'assign') {
                                                        _showAssignApproverDialog(checklist);
                                                      } else if (value == 'edit') {
                                                        _showEditChecklistDialog(checklist);
                                                      } else if (value == 'delete') {
                                                        _showDeleteChecklistDialog(checklist);
                                                      }
                                                    },
                                                    itemBuilder: (context) {
                                                      final authState = ref.read(authProvider);
                                                      final userRole = authState.user?['role'];
                                                      final rawStatus = (checklist['status'] ?? 'draft').toString().toLowerCase();
                                                      final isDraft = rawStatus == 'draft';
                                                      final isSubmittedForApproval = rawStatus == 'submitted_for_approval' || rawStatus == 'submitted for approval';
                                                      final isEngineerOrAdmin = userRole == 'engineer' || userRole == 'admin';
                                                      final isBlockOwner = checklist['is_block_owner'] == true;
                                                      final hasReportData = checklist['has_report_data'] == true;
                                                      final isApprover = _isApprover(checklist);
                                                      final canAssignApprover = (userRole == 'lead' || userRole == 'admin') && isSubmittedForApproval;
                                                      final canEditOrDelete = userRole == 'admin' || userRole == 'lead';
                                                      
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
                                                      
                                                      if (isEngineerOrAdmin && isDraft && isBlockOwner && hasReportData) {
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
                                                      } else if (isEngineerOrAdmin && isDraft && isBlockOwner && !hasReportData) {
                                                        items.add(
                                                          const PopupMenuItem<String>(
                                                            enabled: false,
                                                            child: Row(
                                                              children: [
                                                                Icon(Icons.info_outline, size: 18),
                                                                SizedBox(width: 8),
                                                                Text('Report is not uploaded yet'),
                                                              ],
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                      
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
                                                      
                                                      // Removed approve/reject checklist action - checklist auto-approves when all items are approved
                        
                                                      if (canEditOrDelete) {
                                                        items.addAll([
                                                          const PopupMenuItem<String>(
                                                            value: 'edit',
                                                            child: Row(
                                                              children: [
                                                                Icon(Icons.edit, size: 18),
                                                                SizedBox(width: 8),
                                                                Text('Edit Checklist'),
                                                              ],
                                                            ),
                                                          ),
                                                          const PopupMenuItem<String>(
                                                            value: 'delete',
                                                            child: Row(
                                                              children: [
                                                                Icon(Icons.delete, size: 18, color: Colors.red),
                                                                SizedBox(width: 8),
                                                                Text('Delete Checklist'),
                                                              ],
                                                            ),
                                                          ),
                                                        ]);
                                                      }
                                                      
                                                      return items;
                                                    },
                                                  ),
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
            ],
          ),
        ),
      ),
    );
  }

   Widget _buildRoleChip(String role) {
    if (role == 'N/A' || role.isEmpty) {
      return Text('-', style: TextStyle(fontSize: 14, color: Colors.grey.shade500));
    }

    final lower = role.toLowerCase();
    Color bg;
    Color fg;
    Color border;
    String label;

    switch (lower) {
      case 'admin':
        bg = Colors.red.shade50;
        fg = Colors.red.shade700;
        border = Colors.red.shade200;
        label = 'Admin';
        break;
      case 'lead':
        bg = _kBrandPrimary.withOpacity(0.1);
        fg = _kBrandPrimary;
        border = _kBrandPrimary.withOpacity(0.3);
        label = 'Lead';
        break;
      case 'project_manager':
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade700;
        border = Colors.orange.shade200;
        label = 'Project Manager';
        break;
      case 'engineer':
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade700;
        border = Colors.blue.shade200;
        label = 'Engineer';
        break;
      default:
        bg = Colors.grey.shade50;
        fg = Colors.grey.shade700;
        border = Colors.grey.shade200;
        label = role;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  void _showEditChecklistDialog(Map<String, dynamic> checklist) {
    final nameController = TextEditingController(text: checklist['name'] ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Checklist'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Checklist Name',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newName = nameController.text.trim();
                if (newName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Name cannot be empty'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                Navigator.pop(context);
                final authState = ref.read(authProvider);
                final token = authState.token;
                try {
                  await _qmsService.updateChecklist(
                    checklist['id'],
                    newName,
                    token: token,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Checklist updated successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    _refreshData();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error updating checklist: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteChecklistDialog(Map<String, dynamic> checklist) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Checklist'),
          content: Text(
            'Are you sure you want to delete checklist "${checklist['name'] ?? ''}"? '
            'This will remove all its check items and related data.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kDangerRed,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              onPressed: () async {
                Navigator.pop(context);
                final authState = ref.read(authProvider);
                final token = authState.token;
                try {
                  await _qmsService.deleteChecklist(checklist['id'], token: token);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Checklist deleted successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    _refreshData();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error deleting checklist: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
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
                    backgroundColor: approved == true ? _kSuccessGreen : _kWarningOrange,
                    foregroundColor: Colors.white,
                    elevation: 0,
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

    // Rejection should be done per item, not bulk
    if (!approved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bulk rejection is not allowed. Please reject individual check items from the checklist detail page.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    setState(() {
      _isApproving = true;
    });

    try {
      // Get checklist with items to find all pending items
      final checklist = await _qmsService.getChecklistWithItems(checklistId, token: token);
      if (checklist == null || checklist['check_items'] == null) {
        throw Exception('Checklist not found or has no items');
      }

      // Find all pending/submitted check item IDs
      final checkItems = checklist['check_items'] as List;
      final pendingItemIds = <int>[];
      
      for (var item in checkItems) {
        final approval = item['approval'];
        if (approval != null) {
          final status = approval['status'] ?? 'pending';
          if (status == 'pending' || status == 'submitted') {
            pendingItemIds.add(item['id'] as int);
          }
        }
      }

      if (pendingItemIds.isEmpty) {
        throw Exception('No pending check items found to approve');
      }

      // Batch approve all pending items
      await _qmsService.batchApproveRejectCheckItems(
        pendingItemIds,
        true, // approve
        comments: comments,
        token: token,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${pendingItemIds.length} check item(s) approved successfully. Checklist is now approved.'),
            backgroundColor: Colors.green,
          ),
        );
        _refreshData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error approving all items: $e'),
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

  // Show template settings dialog (Admin only)
  void _showTemplateSettings() {
    showDialog(
      context: context,
      builder: (context) => _TemplateSettingsDialog(
        qmsService: _qmsService,
        onTemplateUploaded: () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Default template uploaded successfully! New checklists will use this template.'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 4),
              ),
            );
          }
        },
      ),
    );
  }
}

// Template Settings Dialog Widget
class _TemplateSettingsDialog extends ConsumerStatefulWidget {
  final QmsService qmsService;
  final VoidCallback onTemplateUploaded;

  const _TemplateSettingsDialog({
    required this.qmsService,
    required this.onTemplateUploaded,
  });

  @override
  ConsumerState<_TemplateSettingsDialog> createState() => _TemplateSettingsDialogState();
}

class _TemplateSettingsDialogState extends ConsumerState<_TemplateSettingsDialog> {
  bool _isUploading = false;
  bool _isLoadingBackups = false;
  List<dynamic> _backups = [];

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() => _isLoadingBackups = true);
    try {
      final token = ref.read(authProvider).token;
      final backups = await widget.qmsService.getTemplateBackups(token: token);
      if (mounted) {
        setState(() {
          _backups = backups;
          _isLoadingBackups = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingBackups = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading backups: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _uploadTemplate() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.first;
      if (file.bytes == null) {
        throw Exception('Unable to read file data');
      }

      // Confirm replacement
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace Default Template?'),
          content: Text(
            'Are you sure you want to replace the default QMS template with "${file.name}"?\n\n'
            'The current template will be backed up automatically.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBrandPrimary,
              ),
              child: const Text('Replace'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      setState(() => _isUploading = true);

      final token = ref.read(authProvider).token;
      await widget.qmsService.uploadDefaultTemplate(
        file.bytes!,
        file.name,
        token: token,
      );

      if (mounted) {
        widget.onTemplateUploaded();
        await _loadBackups(); // Refresh backups list
        setState(() => _isUploading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading template: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.5,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _kBrandPrimary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.description, color: _kBrandPrimary, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'QMS Template Settings',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Upload section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kBrandPrimary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBrandPrimary.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.upload_file, color: _kBrandPrimary, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Upload New Default Template',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This will replace the default template used for creating new checklists. The current template will be backed up automatically.',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isUploading ? null : _uploadTemplate,
                      icon: _isUploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.cloud_upload),
                      label: Text(_isUploading ? 'Uploading...' : 'Choose & Upload Template'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBrandPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Backups section
            const Row(
              children: [
                Icon(Icons.history, color: _kBrandPrimary, size: 20),
                SizedBox(width: 8),
                Text(
                  'Template Backups',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Backups list
            Expanded(
              child: _isLoadingBackups
                  ? const Center(child: CircularProgressIndicator())
                  : _backups.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Text(
                              'No backups available',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _backups.length,
                          itemBuilder: (context, index) {
                            final backup = _backups[index];
                            final createdAt = DateTime.parse(backup['created_at']);
                            final size = (backup['size'] / 1024).toStringAsFixed(1);
                            
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.file_copy, color: _kBrandAccent),
                                title: Text(
                                  backup['filename'],
                                  style: const TextStyle(fontSize: 13),
                                ),
                                subtitle: Text(
                                  '${DateFormat('MMM dd, yyyy hh:mm a').format(createdAt)} • $size KB',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
