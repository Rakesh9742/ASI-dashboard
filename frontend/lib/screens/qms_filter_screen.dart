import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/qms_service.dart';
import 'qms_dashboard_screen.dart';

class QmsFilterScreen extends ConsumerStatefulWidget {
  const QmsFilterScreen({super.key});

  @override
  ConsumerState<QmsFilterScreen> createState() => _QmsFilterScreenState();
}

class _QmsFilterScreenState extends ConsumerState<QmsFilterScreen> {
  final QmsService _qmsService = QmsService();
  bool _isLoading = true;
  bool _isLoadingFilters = false;

  // Filter data
  List<dynamic> _projects = [];
  List<dynamic> _milestones = [];
  List<dynamic> _blocks = [];

  // Selected values
  int? _selectedProjectId;
  int? _selectedDomainId;
  int? _selectedMilestoneId;
  int? _selectedBlockId;

  // Filtered lists based on selections
  List<dynamic> _filteredMilestones = [];
  List<dynamic> _filteredBlocks = [];

  @override
  void initState() {
    super.initState();
    _loadFilterOptions();
  }

  Future<void> _loadFilterOptions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authState = ref.read(authProvider);
      final token = authState.token;

      if (token == null) {
        throw Exception('Not authenticated');
      }

      final filters = await _qmsService.getFilterOptions(token: token);

      setState(() {
        _projects = filters['projects'] ?? [];
        _milestones = filters['milestones'] ?? [];
        _blocks = filters['blocks'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading filter options: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onProjectChanged(int? projectId) {
    setState(() {
      _selectedProjectId = projectId;
      _selectedDomainId = null;
      _selectedMilestoneId = null;
      _selectedBlockId = null;
      _filteredMilestones = [];
      _filteredBlocks = [];

      if (projectId != null) {
        // Filter milestones for selected project
        _filteredMilestones = _milestones
            .where((m) => m['project_id'] == projectId)
            .toList();
        
        // Filter blocks for selected project
        _filteredBlocks = _blocks
            .where((b) => b['project_id'] == projectId)
            .toList();
      }
    });
  }

  void _onMilestoneChanged(int? milestoneId) {
    setState(() {
      _selectedMilestoneId = milestoneId;
      _selectedBlockId = null;
    });
  }

  void _onBlockChanged(int? blockId) {
    setState(() {
      _selectedBlockId = blockId;
    });
  }

  void _navigateToDashboard() {
    if (_selectedBlockId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a block'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QmsDashboardScreen(blockId: _selectedBlockId!),
      ),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('QMS - Filter Selection'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Select Filters',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select Project → Domain → Milestone → Block to view QMS dashboard',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 32),
            
            // Project dropdown
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'Project *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.folder),
              ),
              value: _selectedProjectId,
              items: _projects.map((project) {
                return DropdownMenuItem<int>(
                  value: project['id'],
                  child: Text(project['name'] ?? 'Unknown'),
                );
              }).toList(),
              onChanged: _onProjectChanged,
            ),
            const SizedBox(height: 24),

            // Domain dropdown (optional, shown if project has domains)
            if (_selectedProjectId != null)
              Builder(
                builder: (context) {
                  final project = _projects.firstWhere(
                    (p) => p['id'] == _selectedProjectId,
                    orElse: () => null,
                  );
                  final domains = project?['domains'] ?? [];
                  
                  if (domains.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Domain',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category),
                        ),
                        value: _selectedDomainId,
                        items: domains.map<DropdownMenuItem<int>>((domain) {
                          return DropdownMenuItem<int>(
                            value: domain['id'],
                            child: Text(domain['name'] ?? 'Unknown'),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedDomainId = value;
                          });
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                  );
                },
              ),

            // Milestone dropdown
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'Milestone',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.flag),
              ),
              value: _selectedMilestoneId,
              items: _filteredMilestones.map((milestone) {
                return DropdownMenuItem<int>(
                  value: milestone['id'],
                  child: Text(milestone['name'] ?? 'Unknown'),
                );
              }).toList(),
              onChanged: _filteredMilestones.isEmpty ? null : _onMilestoneChanged,
            ),
            const SizedBox(height: 24),

            // Block dropdown
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'Block *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.view_module),
              ),
              value: _selectedBlockId,
              items: _filteredBlocks.map((block) {
                return DropdownMenuItem<int>(
                  value: block['id'],
                  child: Text(block['block_name'] ?? 'Unknown'),
                );
              }).toList(),
              onChanged: _filteredBlocks.isEmpty ? null : _onBlockChanged,
            ),
            const SizedBox(height: 32),

            // Navigate button
            ElevatedButton.icon(
              onPressed: _selectedBlockId != null ? _navigateToDashboard : null,
              icon: const Icon(Icons.dashboard),
              label: const Text('View QMS Dashboard'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

