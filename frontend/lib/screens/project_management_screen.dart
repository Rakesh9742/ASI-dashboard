import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import 'domain_plan_screen.dart';

class ProjectManagementScreen extends ConsumerStatefulWidget {
  const ProjectManagementScreen({super.key});

  @override
  ConsumerState<ProjectManagementScreen> createState() => _ProjectManagementScreenState();
}

class _ProjectManagementScreenState extends ConsumerState<ProjectManagementScreen> {
  final ApiService _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _clientController = TextEditingController();
  final TextEditingController _technologyNodeController = TextEditingController();
  final TextEditingController _planController = TextEditingController();

  DateTime? _startDate;
  DateTime? _targetDate;
  int _currentStep = 0;
  bool _isLoading = true;
  bool _isSubmitting = false;

  List<dynamic> _domains = [];
  List<int> _selectedDomainIds = [];
  List<dynamic> _projects = [];

  @override
  void initState() {
    super.initState();
    _loadDomainsAndProjects();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _clientController.dispose();
    _technologyNodeController.dispose();
    _planController.dispose();
    super.dispose();
  }

  Future<void> _loadDomainsAndProjects() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authState = ref.read(authProvider);
      final token = authState.token;

      final domains = await _apiService.getDomains(token: token);
      final projects = await _apiService.getProjects(token: token);

      setState(() {
        _domains = domains;
        _projects = projects;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading project data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickDate({
    required bool isStartDate,
  }) async {
    final now = DateTime.now();
    final initialDate = isStartDate
        ? (_startDate ?? now)
        : (_targetDate ?? _startDate ?? now.add(const Duration(days: 30)));
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );

    if (selected != null) {
      setState(() {
        if (isStartDate) {
          _startDate = selected;
        } else {
          _targetDate = selected;
        }
      });
    }
  }

  String? _formatDate(DateTime? date) {
    if (date == null) return null;
    return date.toIso8601String().split('T').first;
  }

  Future<void> _submitProject() async {
    if (!_formKey.currentState!.validate()) {
      setState(() {
        _currentStep = 0;
      });
      return;
    }

    if (_selectedDomainIds.isEmpty) {
      setState(() {
        _currentStep = 1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one domain'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final authState = ref.read(authProvider);
      final token = authState.token;

      final project = await _apiService.createProject(
        name: _nameController.text.trim(),
        client: _clientController.text.trim().isEmpty ? null : _clientController.text.trim(),
        technologyNode: _technologyNodeController.text.trim(),
        startDate: _formatDate(_startDate),
        targetDate: _formatDate(_targetDate),
        plan: _planController.text.trim().isEmpty ? null : _planController.text.trim(),
        domainIds: _selectedDomainIds,
        token: token,
      );

        setState(() {
        _projects = [project, ..._projects];
        _nameController.clear();
        _clientController.clear();
        _technologyNodeController.clear();
        _planController.clear();
        _startDate = null;
        _targetDate = null;
        _selectedDomainIds = [];
        _currentStep = 0;
      });

      if (mounted) {
        Navigator.of(context).pop(); // Close the dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Project created successfully'),
            backgroundColor: Colors.green,
      ),
    );
  }
    } catch (e) {
      if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create project: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showCreateProjectDialog() {
    setState(() {
      _currentStep = 0;
      _nameController.clear();
      _clientController.clear();
      _technologyNodeController.clear();
      _planController.clear();
      _startDate = null;
      _targetDate = null;
      _selectedDomainIds = [];
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.purple.shade600,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
          children: [
                    const Icon(Icons.add_circle_outline, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Create New Project',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: _isSubmitting ? null : () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                ),
              ),
              // Form Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Stepper(
                    physics: const NeverScrollableScrollPhysics(),
                    type: StepperType.vertical,
                    currentStep: _currentStep,
                    controlsBuilder: (context, details) {
                        return const SizedBox.shrink();
                    },
                    steps: [
                      Step(
                          title: const Text(
                            'Basic Information',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        isActive: _currentStep == 0,
                        state: _currentStep > 0 ? StepState.complete : StepState.indexed,
                        content: Column(
                          children: [
                            TextFormField(
                              controller: _nameController,
                                decoration: InputDecoration(
                                  labelText: 'Project Name *',
                                  prefixIcon: const Icon(Icons.work_outline),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Project name is required';
                                }
                                return null;
                              },
                            ),
                              const SizedBox(height: 16),
                            TextFormField(
                              controller: _clientController,
                                decoration: InputDecoration(
                                labelText: 'Client',
                                  prefixIcon: const Icon(Icons.business_outlined),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                ),
                              ),
                              const SizedBox(height: 16),
                            TextFormField(
                              controller: _technologyNodeController,
                                decoration: InputDecoration(
                                  labelText: 'Technology Node *',
                                  prefixIcon: const Icon(Icons.memory_outlined),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Technology node is required';
                                }
                                return null;
                              },
                            ),
                              const SizedBox(height: 16),
                            Row(
                children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _isSubmitting ? null : () => _pickDate(isStartDate: true),
                                    icon: const Icon(Icons.calendar_today),
                                    label: Text(
                                      _startDate == null
                                          ? 'Start Date'
                                            : _formatDate(_startDate) ?? 'Start Date',
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _isSubmitting ? null : () => _pickDate(isStartDate: false),
                                    icon: const Icon(Icons.event_available),
                                    label: Text(
                                      _targetDate == null
                                          ? 'Target Date'
                                            : _formatDate(_targetDate) ?? 'Target Date',
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                  ),
                ),
              ),
                              ],
                            ),
                              const SizedBox(height: 16),
                            TextFormField(
                              controller: _planController,
                                decoration: InputDecoration(
                                labelText: 'Project Plan / Notes',
                                alignLabelWithHint: true,
                                  prefixIcon: const Icon(Icons.notes_outlined),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                              ),
                              maxLines: 4,
                            ),
                          ],
                        ),
                      ),
                      Step(
                          title: const Text(
                            'Domain Selection',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        isActive: _currentStep == 1,
                        state: _currentStep == 1 && _selectedDomainIds.isEmpty
                            ? StepState.editing
                            : StepState.complete,
                        content: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                              Text(
                              'Select the verticals involved (multi-select):',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                            ),
                              const SizedBox(height: 16),
                            Wrap(
                                spacing: 10,
                                runSpacing: 10,
                              children: _domains.map<Widget>((domain) {
                                final id = domain['id'] as int;
                                final isSelected = _selectedDomainIds.contains(id);
                                return FilterChip(
                                  label: Text(domain['name'] ?? domain['code'] ?? 'Domain'),
                                  selected: isSelected,
                                    selectedColor: Colors.purple.shade100,
                                    checkmarkColor: Colors.purple.shade700,
                                    labelStyle: TextStyle(
                                      color: isSelected ? Colors.purple.shade900 : Colors.grey.shade700,
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                    avatar: isSelected
                                        ? Icon(Icons.check_circle, size: 18, color: Colors.purple.shade700)
                                        : null,
                                  onSelected: _isSubmitting
                                      ? null
                                      : (selected) {
                                          setState(() {
                                            if (selected) {
                                              _selectedDomainIds.add(id);
                                            } else {
                                              _selectedDomainIds.remove(id);
                                            }
                                          });
                                          setDialogState(() {});
                                        },
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                );
                              }).toList(),
                            ),
                            if (_selectedDomainIds.isEmpty)
                              Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.red.shade200),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.info_outline, color: Colors.red.shade700, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                child: Text(
                                            'Please select at least one domain (RTL, DV, PD, etc.)',
                                            style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                                          ),
                                        ),
                                      ],
                                    ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
              // Footer Actions
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_currentStep > 0)
                      TextButton.icon(
                        onPressed: _isSubmitting
                            ? null
                            : () {
                                setState(() => _currentStep -= 1);
                                setDialogState(() {});
                              },
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Back'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                    if (_currentStep > 0) const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _isSubmitting
                          ? null
                          : () async {
                              if (_currentStep == 0) {
                                if (_formKey.currentState!.validate()) {
                                  setState(() => _currentStep = 1);
                                  setDialogState(() {});
                                }
                              } else {
                                await _submitProject();
                              }
                            },
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(_currentStep == 0 ? Icons.arrow_forward : Icons.check),
                      label: Text(_currentStep == 0 ? 'Next' : 'Create Project'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isAuthenticated = authState.isAuthenticated;

    if (!isAuthenticated) {
      return const Center(child: Text('Please log in to manage projects.'));
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadDomainsAndProjects,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Project Management',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage and track your projects',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _showCreateProjectDialog,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Create Project'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            // Projects List Section
            Row(
              children: [
                Icon(Icons.folder_open, color: Colors.purple.shade600, size: 24),
                const SizedBox(width: 8),
            Text(
              'Projects',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_projects.length}',
                    style: TextStyle(
                      color: Colors.purple.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_projects.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Icon(Icons.folder_open_outlined, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'No projects yet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Click "Create Project" to get started',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth > 1200
                      ? 4
                      : constraints.maxWidth > 800
                          ? 3
                          : constraints.maxWidth > 600
                              ? 2
                              : 1;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: _projects.length,
                    itemBuilder: (context, index) {
                      return _buildProjectCard(_projects[index]);
                    },
                  );
                },
              ),
          ],
        ),
        ),
      );
    }

  Widget _buildProjectCard(dynamic project) {
    final domains = (project['domains'] as List<dynamic>? ?? []);
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      child: InkWell(
        onTap: () {
          // Can add project details navigation here later
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                Colors.purple.shade50.withOpacity(0.3),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top Section - Icon and Title
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.purple.shade600,
                            Colors.purple.shade400,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.purple.shade200,
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.folder_open, color: Colors.white, size: 32),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      project['name'] ?? 'Project',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (project['client'] != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.business, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              project['client'],
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                // Middle Section - Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (project['technology_node'] != null) ...[
                        Row(
                          children: [
                            Icon(Icons.memory, size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                project['technology_node'],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (project['start_date'] != null || project['target_date'] != null) ...[
                        Row(
                          children: [
                            Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                project['start_date'] ?? 'N/A',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Bottom Section - Domains
                if (domains.isNotEmpty) ...[
                  Divider(color: Colors.grey.shade200, height: 20),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: domains.take(3).map<Widget>((domain) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.purple.shade200, width: 1),
                        ),
                        child: Text(
                          domain['code'] ?? domain['name'] ?? 'Domain',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.purple.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (domains.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '+${domains.length - 3} more',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.purple.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
                // Create Domain Plan Button
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _handleCreateDomainPlan(project),
                    icon: const Icon(Icons.add_task, size: 18),
                    label: const Text(
                      'Create Domain Plan',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleCreateDomainPlan(dynamic project) {
    final domains = (project['domains'] as List<dynamic>? ?? []);
    
    if (domains.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This project has no domains assigned'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (domains.length == 1) {
      // Directly open domain plan page with the single domain
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => DomainPlanScreen(
            projectId: project['id'],
            projectName: project['name'] ?? 'Project',
            domain: domains[0],
          ),
        ),
      );
    } else {
      // Show domain selection dialog
      _showDomainSelectionDialog(project, domains);
    }
  }

  void _showDomainSelectionDialog(dynamic project, List<dynamic> domains) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.select_all, color: Colors.purple.shade600),
            const SizedBox(width: 12),
            const Text('Select Domain'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select a domain to create a plan for:',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              ...domains.map((domain) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.purple.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          (domain['code'] ?? domain['name'] ?? 'D')[0],
                          style: TextStyle(
                            color: Colors.purple.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      domain['name'] ?? 'Domain',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      domain['code'] ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => DomainPlanScreen(
                            projectId: project['id'],
                            projectName: project['name'] ?? 'Project',
                            domain: domain,
                          ),
                        ),
                      );
                    },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              }).toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

}

