import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/qms_service.dart';
import '../providers/auth_provider.dart';

import '../widgets/qms_status_badge.dart';

class QmsHistoryDialog extends ConsumerStatefulWidget {
  final int blockId;

  const QmsHistoryDialog({Key? key, required this.blockId}) : super(key: key);

  @override
  ConsumerState<QmsHistoryDialog> createState() => _QmsHistoryDialogState();
}

class _QmsHistoryDialogState extends ConsumerState<QmsHistoryDialog> {
  final QmsService _qmsService = QmsService();
  bool _isLoading = true;
  List<dynamic> _checklists = [];
  Map<int, List<dynamic>> _historyMap = {};

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final token = ref.read(authProvider).token;
      // 1. Get all checklists for the block
      final checklists = await _qmsService.getChecklistsForBlock(widget.blockId, token: token);
      
      // 2. For each checklist, fetch its history
      final Map<int, List<dynamic>> historyMap = {};
      for (var cl in checklists) {
        final history = await _qmsService.getChecklistHistory(cl['id'], token: token);
        if (history.isNotEmpty) {
          historyMap[cl['id']] = history;
        }
      }

      if (mounted) {
        setState(() {
          _checklists = checklists;
          _historyMap = historyMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading history: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.7,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.history, size: 28, color: Color(0xFF14B8A6)),
                    SizedBox(width: 12),
                    Text(
                      'QMS Revision History',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Track historical rejections and snapshots for all checklists in this block.',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _historyMap.isEmpty
                      ? _buildEmptyState()
                      : _buildHistoryList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off, size: 64, color: Colors.grey.withOpacity(0.3)),
          const SizedBox(height: 16),
          const Text(
            'No revision history found for this block\'s checklists.',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            'History snapshots are created automatically when a checklist is rejected.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    // Filter checklists that actually have history
    final checklistsWithHistory = _checklists.where((cl) => _historyMap.containsKey(cl['id'])).toList();

    return ListView.builder(
      itemCount: checklistsWithHistory.length,
      itemBuilder: (context, index) {
        final checklist = checklistsWithHistory[index];
        final history = _historyMap[checklist['id']]!;

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.withOpacity(0.2)),
          ),
          child: ExpansionTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFF14B8A6),
              child: Icon(Icons.assignment, color: Colors.white, size: 20),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    checklist['name'] ?? 'Untitled Checklist',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                QmsStatusBadge(status: checklist['status'] ?? 'draft'),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        'Approver: ${checklist['approver_name'] ?? 'Not Assigned'}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.badge_outlined, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        'Role: ${checklist['approver_role'] ?? 'N/A'}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total Revisions: ${history.length}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            children: history.map((version) => _buildVersionItem(version)).toList(),
          ),
        );
      },
    );
  }

  Widget _buildVersionItem(dynamic version) {
    final date = DateTime.parse(version['created_at']);
    final formattedDate = DateFormat('MMM dd, yyyy HH:mm').format(date);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'v${version['version_number']}',
              style: const TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  version['rejection_comments'] ?? 'No comments provided',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'Rejected by ${version['rejected_by_name'] ?? 'System'} on $formattedDate',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => _viewVersionSnapshot(version['id']),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF14B8A6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: const Text('View Snapshot'),
          ),
        ],
      ),
    );
  }

  Future<void> _viewVersionSnapshot(int versionId) async {
    try {
      final token = ref.read(authProvider).token;
      final version = await _qmsService.getChecklistVersion(versionId, token: token);
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => _SnapshotDetailDialog(version: version),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading snapshot: $e')),
      );
    }
  }
}

class _SnapshotDetailDialog extends StatefulWidget {
  final Map<String, dynamic> version;

  const _SnapshotDetailDialog({Key? key, required this.version}) : super(key: key);

  @override
  State<_SnapshotDetailDialog> createState() => _SnapshotDetailDialogState();
}

class _SnapshotDetailDialogState extends State<_SnapshotDetailDialog> {
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  int _currentPage = 0;
  int _itemsPerPage = 10;
  
  // Filters
  String? _selectedCategory;
  String? _selectedSubCategory;
  String? _selectedSeverity;
  String? _selectedStatus;
  bool _showOnlyRejected = false;

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.version['checklist_snapshot'];
    final allItems = snapshot['check_items'] as List<dynamic>? ?? [];

    // Apply Filters
    final filteredItems = allItems.where((item) {
      if (_showOnlyRejected) {
        final status = item['approval_status'] ?? 'pending';
        if (status != 'not_approved' && status != 'rejected') return false;
      }
      if (_selectedCategory != null && item['category'] != _selectedCategory) return false;
      if (_selectedSubCategory != null && item['sub_category'] != _selectedSubCategory) return false;
      if (_selectedSeverity != null && item['severity'] != _selectedSeverity) return false;
      if (_selectedStatus != null) {
        final status = (item['approval_status'] ?? 'pending').toString().toLowerCase();
        if (status != _selectedStatus!.toLowerCase()) return false;
      }
      return true;
    }).toList();

    final totalFiltered = filteredItems.length;
    final startIndex = _currentPage * _itemsPerPage;
    final paginatedItems = filteredItems.sublist(
      startIndex,
      (startIndex + _itemsPerPage) > totalFiltered ? totalFiltered : (startIndex + _itemsPerPage),
    );

    // Prepare filter options
    final categories = allItems.map((e) => e['category']?.toString()).whereType<String>().toSet().toList()..sort();
    final subCategories = allItems.map((e) => e['sub_category']?.toString()).whereType<String>().toSet().toList()..sort();
    final severities = allItems.map((e) => e['severity']?.toString()).whereType<String>().toSet().toList()..sort();
    final statuses = ['pending', 'approved', 'rejected'];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.95,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(snapshot),
            const Divider(height: 32),
            _buildRejectionInfo(),
            const SizedBox(height: 16),
            _buildFilterBar(),
            const SizedBox(height: 16),
            Expanded(child: _buildTable(paginatedItems, startIndex)),
            _buildPaginationControls(totalFiltered),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(dynamic snapshot) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Historical Snapshot: ${snapshot['name']}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'Version ${widget.version['version_number']} • ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.parse(widget.version['created_at']))}',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                _buildDot(),
                Text('Approver: ${snapshot['approver_name'] ?? 'N/A'}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                _buildDot(),
                Text('Stage: ${snapshot['stage'] ?? 'N/A'}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                if (snapshot['milestone_name'] != null) ...[
                  _buildDot(),
                  Text('Milestone: ${snapshot['milestone_name']}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                ],
              ],
            ),
          ],
        ),
        Row(
          children: [
            QmsStatusBadge(status: snapshot['status'] ?? 'rejected'),
            const SizedBox(width: 16),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ],
        ),
      ],
    );
  }

  Widget _buildDot() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle)),
  );

  Widget _buildRejectionInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, size: 18, color: Color(0xFFEF4444)),
              const SizedBox(width: 8),
              const Text('Rejection Reason:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFEF4444))),
            ],
          ),
          const SizedBox(height: 8),
          Text(widget.version['rejection_comments'] ?? 'No comments provided', style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Row(
      children: [
        const Text('Filters:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 16),
        FilterChip(
          label: const Text('Show Rejected Only'),
          selected: _showOnlyRejected,
          onSelected: (v) => setState(() { _showOnlyRejected = v; _currentPage = 0; }),
          selectedColor: const Color(0xFFEF4444).withOpacity(0.2),
          checkmarkColor: const Color(0xFFEF4444),
        ),
        const Spacer(),
        if (_hasAnyFilter()) 
          TextButton.icon(
            onPressed: _clearFilters,
            icon: const Icon(Icons.clear_all, size: 18),
            label: const Text('Clear All Filters'),
          ),
      ],
    );
  }

  bool _hasAnyFilter() => _showOnlyRejected || _selectedCategory != null || _selectedSubCategory != null || _selectedSeverity != null || _selectedStatus != null;

  void _clearFilters() => setState(() {
    _showOnlyRejected = false;
    _selectedCategory = null;
    _selectedSubCategory = null;
    _selectedSeverity = null;
    _selectedStatus = null;
    _currentPage = 0;
  });

  Widget _buildTable(List<dynamic> items, int startIndex) {
    const double colId = 120;
    const double colCat = 150;
    const double colSub = 150;
    const double colDesc = 250;
    const double colSev = 100;
    const double colBronze = 100;
    const double colSilver = 100;
    const double colGold = 100;
    const double colInfo = 200;
    const double colEvidence = 200;
    const double colReport = 200;
    const double colResult = 150;
    const double colStatus = 120;
    const double colComments = 200;
    const double colRevComments = 200;
    const double colSignoff = 150;
    final totalWidth = colId + colCat + colSub + colDesc + colSev + colBronze + colSilver + colGold + colInfo + colEvidence + colReport + colResult + colStatus + colComments + colRevComments + colSignoff;

    final columnWidths = {
      0: const FixedColumnWidth(colId),
      1: const FixedColumnWidth(colCat),
      2: const FixedColumnWidth(colSub),
      3: const FixedColumnWidth(colDesc),
      4: const FixedColumnWidth(colSev),
      5: const FixedColumnWidth(colBronze),
      6: const FixedColumnWidth(colSilver),
      7: const FixedColumnWidth(colGold),
      8: const FixedColumnWidth(colInfo),
      9: const FixedColumnWidth(colEvidence),
      10: const FixedColumnWidth(colReport),
      11: const FixedColumnWidth(colResult),
      12: const FixedColumnWidth(colStatus),
      13: const FixedColumnWidth(colComments),
      14: const FixedColumnWidth(colRevComments),
      15: const FixedColumnWidth(colSignoff),
    };

    // Get filter options for headers
    final snapshot = widget.version['checklist_snapshot'];
    final allItems = snapshot['check_items'] as List<dynamic>? ?? [];
    final categories = allItems.map((e) => e['category']?.toString()).whereType<String>().toSet().toList()..sort();
    final subCats = allItems.map((e) => e['sub_category']?.toString()).whereType<String>().toSet().toList()..sort();
    final severities = allItems.map((e) => e['severity']?.toString()).whereType<String>().toSet().toList()..sort();

    return LayoutBuilder(builder: (context, constraints) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Scrollbar(
            controller: _horizontalScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth < constraints.maxWidth ? constraints.maxWidth : totalWidth,
                child: Column(
                  children: [
                    // Header
                    Container(
                      color: Colors.grey.shade50,
                      child: Table(
                        columnWidths: columnWidths,
                        children: [
                          TableRow(children: [
                            _buildHeaderCell('Check ID'),
                            _buildFilterHeaderCell('Category', _selectedCategory, categories, (v) => setState(() { _selectedCategory = v; _currentPage = 0; })),
                            _buildFilterHeaderCell('Sub-Category', _selectedSubCategory, subCats, (v) => setState(() { _selectedSubCategory = v; _currentPage = 0; })),
                            _buildHeaderCell('Check Description'),
                            _buildFilterHeaderCell('Severity', _selectedSeverity, severities, (v) => setState(() { _selectedSeverity = v; _currentPage = 0; })),
                            _buildHeaderCell('Bronze'),
                            _buildHeaderCell('Silver'),
                            _buildHeaderCell('Gold'),
                            _buildHeaderCell('Info'),
                            _buildHeaderCell('Evidence'),
                            _buildHeaderCell('Report Path'),
                            _buildHeaderCell('Result/Value'),
                            _buildFilterHeaderCell('Status', _selectedStatus, ['pending', 'approved', 'rejected'], (v) => setState(() { _selectedStatus = v; _currentPage = 0; })),
                            _buildHeaderCell('Comments'),
                            _buildHeaderCell('Reviewer Comments'),
                            _buildHeaderCell('Signoff'),
                          ]),
                        ],
                      ),
                    ),
                    // Body
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _verticalScrollController,
                        child: Table(
                          columnWidths: columnWidths,
                          children: items.map((item) {
                            final status = item['approval_status'] ?? 'pending';
                            return TableRow(
                              decoration: BoxDecoration(
                                color: (status == 'not_approved' || status == 'rejected') ? Colors.red.withOpacity(0.02) : null,
                                border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                              ),
                              children: [
                                _buildBodyCell(Text(item['name'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF14B8A6)))),
                                _buildBodyCell(Text(item['category'] ?? 'N/A')),
                                _buildBodyCell(Text(item['sub_category'] ?? 'N/A')),
                                _buildBodyCell(Text(item['description'] ?? 'N/A', maxLines: 2, overflow: TextOverflow.ellipsis)),
                                _buildBodyCell(Text(item['severity'] ?? 'N/A')),
                                _buildBodyCell(Text(item['bronze'] ?? 'N/A')),
                                _buildBodyCell(Text(item['silver'] ?? 'N/A')),
                                _buildBodyCell(Text(item['gold'] ?? 'N/A')),
                                _buildBodyCell(Text(item['info'] ?? 'N/A', maxLines: 2, overflow: TextOverflow.ellipsis)),
                                _buildBodyCell(Text(item['evidence'] ?? 'N/A', maxLines: 2, overflow: TextOverflow.ellipsis)),
                                _buildBodyCell(Text(item['report_path'] ?? 'N/A', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.blue))),
                                _buildBodyCell(Text(item['result_value'] ?? 'N/A')),
                                _buildBodyCell(_buildSmallStatusBadge(status)),
                                _buildBodyCell(Text(item['engineer_comments'] ?? 'No comments', maxLines: 2, overflow: TextOverflow.ellipsis)),
                                _buildBodyCell(Text(item['approval_comments'] ?? 'No comments', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontStyle: FontStyle.italic))),
                                _buildBodyCell(Text(item['signoff_status'] ?? 'N/A')),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildHeaderCell(String text) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  Widget _buildFilterHeaderCell(String title, String? current, List<String> options, ValueChanged<String?> onChanged) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)),
          PopupMenuButton<String>(
            icon: Icon(Icons.filter_list, size: 16, color: current != null ? const Color(0xFF14B8A6) : Colors.grey),
            onSelected: (v) => onChanged(v == '_clear_' ? null : v),
            itemBuilder: (ctx) => [
              if (current != null) const PopupMenuItem(value: '_clear_', child: Text('Clear Filter')),
              ...options.map((o) => PopupMenuItem(value: o, child: Text(o))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBodyCell(Widget child) {
    return Container(
      padding: const EdgeInsets.all(12),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }

  Widget _buildSmallStatusBadge(String status) {
    Color color;
    String text = status.toUpperCase();
    if (status == 'not_approved' || status == 'rejected') {
      color = Colors.red;
      text = 'REJECTED';
    } else if (status == 'approved') {
      color = Colors.green;
    } else {
      color = Colors.orange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildTargetBadge(String label, String value, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text('$label: $value', style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildPaginationControls(int totalItems) {
    final pageCount = (totalItems / _itemsPerPage).ceil();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Showing ${totalItems == 0 ? 0 : (_currentPage * _itemsPerPage + 1)} to ${(_currentPage + 1) * _itemsPerPage > totalItems ? totalItems : (_currentPage + 1) * _itemsPerPage} of $totalItems items'),
          Row(
            children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null),
              Text('Page ${_currentPage + 1} of ${pageCount == 0 ? 1 : pageCount}'),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: _currentPage < pageCount - 1 ? () => setState(() => _currentPage++) : null),
              const SizedBox(width: 16),
              DropdownButton<int>(
                value: _itemsPerPage,
                items: [10, 20, 50, 100].map((i) => DropdownMenuItem(value: i, child: Text('$i / page'))).toList(),
                onChanged: (v) => setState(() { _itemsPerPage = v!; _currentPage = 0; }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommentBox(String title, String comment) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Text(
              comment,
              style: TextStyle(fontSize: 12, color: Colors.grey[800], fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }
}
