import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import 'package:fl_chart/fl_chart.dart';

class ViewScreen extends ConsumerStatefulWidget {
  const ViewScreen({super.key});

  @override
  ConsumerState<ViewScreen> createState() => _ViewScreenState();
}

class _ViewScreenState extends ConsumerState<ViewScreen> {
  final ApiService _apiService = ApiService();
  
  // Data structure: project -> block -> rtl_tag -> experiment -> stages
  Map<String, dynamic> _groupedData = {};
  
  // Selection state
  String? _selectedProject;
  String? _selectedDomain;
  String? _selectedBlock;
  String? _selectedTag;
  String? _selectedExperiment;
  String _stageFilter = 'all';
  String _viewType = 'engineer'; // 'engineer', 'lead', 'manager'
  
  // Data
  bool _isLoading = false;
  bool _isLoadingDomains = false;
  List<dynamic> _projects = [];
  List<String> _availableDomainsForProject = [];
  
  // Graph Selection State - Multiple selections
  Set<String> _selectedMetricGroups = {'INTERNAL (R2R)'};
  Set<String> _selectedMetricTypes = {'WNS'};
  
  // Visualization type: 'graph' or 'heatmap'
  String _visualizationType = 'graph';

  // Scroll controllers for table
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadProjectsAndDomains();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadProjectsAndDomains() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authState = ref.read(authProvider);
      final token = authState.token;
      
      // Load projects
      final projects = await _apiService.getProjects(token: token);
      
      setState(() {
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
            content: Text('Error loading projects and domains: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadInitialData() async {
    if (_selectedProject == null || _selectedDomain == null) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authState = ref.read(authProvider);
      final token = authState.token;
      
      // Load EDA files and group them
      final filesResponse = await _apiService.getEdaFiles(
        token: token,
        limit: 1000,
      );
      
      final files = filesResponse['files'] ?? [];
      
      // Filter files by selected project and domain
      final filteredFiles = files.where((file) {
        final projectName = file['project_name'] ?? 'Unknown';
        final domainName = file['domain_name'] ?? '';
        return projectName == _selectedProject && domainName == _selectedDomain;
      }).toList();
      
      // Group files by project -> block -> rtl_tag -> experiment -> stages
      final Map<String, dynamic> grouped = {};
      
      for (var file in filteredFiles) {
        final projectName = file['project_name'] ?? 'Unknown';
        final blockName = file['block_name'] ?? 'Unknown';
        final rtlTag = file['rtl_tag'] ?? 'Unknown';
        final experiment = file['experiment'] ?? 'Unknown';
        
        if (!grouped.containsKey(projectName)) {
          grouped[projectName] = {};
        }
        if (!grouped[projectName].containsKey(blockName)) {
          grouped[projectName][blockName] = {};
        }
        if (!grouped[projectName][blockName].containsKey(rtlTag)) {
          grouped[projectName][blockName][rtlTag] = {};
        }
        if (!grouped[projectName][blockName][rtlTag].containsKey(experiment)) {
          grouped[projectName][blockName][rtlTag][experiment] = {
            'run_directory': file['run_directory'],
            'last_updated': file['run_end_time']?.toString() ?? file['created_at']?.toString(),
            'stages': {},
          };
        }
        
        // Add stage data
        final stage = file['stage'] ?? 'unknown';
        final run = grouped[projectName][blockName][rtlTag][experiment];
        run['stages'][stage] = {
          'stage': stage,
          'timestamp': file['timestamp']?.toString() ?? file['run_end_time']?.toString() ?? file['created_at']?.toString(),
          'user_name': file['user_name'],
          // Timing metrics
          'internal_timing_r2r_wns': _parseNumeric(file['internal_timing_r2r_wns']),
          'internal_timing_r2r_tns': _parseNumeric(file['internal_timing_r2r_tns']),
          'internal_timing_r2r_nvp': _parseNumeric(file['internal_timing_r2r_nvp']),
          'interface_timing_i2r_wns': _parseNumeric(file['interface_timing_i2r_wns']),
          'interface_timing_i2r_tns': _parseNumeric(file['interface_timing_i2r_tns']),
          'interface_timing_i2r_nvp': _parseNumeric(file['interface_timing_i2r_nvp']),
          'interface_timing_r2o_wns': _parseNumeric(file['interface_timing_r2o_wns']),
          'interface_timing_r2o_tns': _parseNumeric(file['interface_timing_r2o_tns']),
          'interface_timing_r2o_nvp': _parseNumeric(file['interface_timing_r2o_nvp']),
          'interface_timing_i2o_wns': _parseNumeric(file['interface_timing_i2o_wns']),
          'interface_timing_i2o_tns': _parseNumeric(file['interface_timing_i2o_tns']),
          'interface_timing_i2o_nvp': _parseNumeric(file['interface_timing_i2o_nvp']),
          'hold_wns': _parseNumeric(file['hold_wns']),
          'hold_tns': _parseNumeric(file['hold_tns']),
          'hold_nvp': _parseNumeric(file['hold_nvp']),
          // Constraint metrics
          'max_tran_wns': _parseNumeric(file['max_tran_wns']),
          'max_tran_nvp': _parseNumeric(file['max_tran_nvp']),
          'max_cap_wns': _parseNumeric(file['max_cap_wns']),
          'max_cap_nvp': _parseNumeric(file['max_cap_nvp']),
          'max_fanout_wns': _parseNumeric(file['max_fanout_wns']),
          'max_fanout_nvp': _parseNumeric(file['max_fanout_nvp']),
          'drc_violations': _parseNumeric(file['drc_violations']),
          'congestion_hotspot': file['congestion_hotspot']?.toString(),
          'noise_violations': file['noise_violations']?.toString(),
          // Power/IR/EM
          'ir_static': file['ir_static']?.toString(),
          'ir_dynamic': file['ir_dynamic']?.toString(),
          'em_power': file['em_power']?.toString(),
          'em_signal': file['em_signal']?.toString(),
          // Physical verification
          'pv_drc_base': file['pv_drc_base']?.toString(),
          'pv_drc_metal': file['pv_drc_metal']?.toString(),
          'pv_drc_antenna': file['pv_drc_antenna']?.toString(),
          'lvs': file['lvs']?.toString(),
          'erc': file['erc']?.toString(),
          'r2g_lec': file['r2g_lec']?.toString(),
          'g2g_lec': file['g2g_lec']?.toString(),
          // Stage metrics
          'area': _parseNumeric(file['area']),
          'inst_count': _parseNumeric(file['inst_count']),
          'utilization': _parseNumeric(file['utilization']),
          'min_pulse_width': file['min_pulse_width']?.toString(),
          'min_period': file['min_period']?.toString(),
          'double_switching': file['double_switching']?.toString(),
          'log_errors': _parseNumeric(file['log_errors']) ?? 0,
          'log_warnings': _parseNumeric(file['log_warnings']) ?? 0,
          'log_critical': _parseNumeric(file['log_critical']) ?? 0,
          'run_status': file['run_status'] ?? 'unknown',
          'runtime': file['runtime']?.toString() ?? '00:00:00',
          'memory_usage': file['memory_usage']?.toString(),
          'ai_summary': file['ai_summary']?.toString() ?? file['ai_based_overall_summary']?.toString(),
        };
      }

      setState(() {
        _groupedData = grouped;
        
        // Debug: Print grouped data structure
        print('Grouped data keys (projects): ${grouped.keys.toList()}');
        if (grouped.isNotEmpty) {
          final firstProject = grouped.keys.first;
          print('First project: $firstProject');
          final projectData = grouped[firstProject];
          if (projectData is Map) {
            print('Project blocks: ${projectData.keys.toList()}');
          }
        }
        
        // Don't auto-select - user must select project manually
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

  dynamic _parseNumeric(dynamic value) {
    if (value == null || value == 'N/A' || value == 'NA') return null;
    if (value is num) return value;
    if (value is String) {
      if (value.toUpperCase() == 'N/A' || value.toUpperCase() == 'NA') return null;
      final parsed = double.tryParse(value);
      return parsed;
    }
    return null;
  }

  Map<String, dynamic>? _getActiveRun() {
    if (_selectedProject == null || _selectedBlock == null || 
        _selectedTag == null || _selectedExperiment == null) {
      return null;
    }
    try {
      final projectValue = _groupedData[_selectedProject];
      if (projectValue is! Map) return null;
      final projectData = Map<String, dynamic>.from(projectValue);
      
      final blockValue = projectData[_selectedBlock];
      if (blockValue is! Map) return null;
      final blockData = Map<String, dynamic>.from(blockValue);
      
      final tagValue = blockData[_selectedTag];
      if (tagValue is! Map) return null;
      final tagData = Map<String, dynamic>.from(tagValue);
      
      final experimentValue = tagData[_selectedExperiment];
      if (experimentValue is! Map) return null;
      final experimentData = Map<String, dynamic>.from(experimentValue);
      
      return experimentData;
    } catch (e) {
      print('Error getting active run: $e');
      return null;
    }
  }

  List<Map<String, dynamic>> _getActiveStages() {
    final run = _getActiveRun();
    if (run == null) return [];
    final stagesValue = run['stages'];
    final stages = (stagesValue is Map) 
        ? Map<String, dynamic>.from(stagesValue) 
        : <String, dynamic>{};
    
    // Safely convert stages values to List<Map<String, dynamic>>
    final stagesList = <Map<String, dynamic>>[];
    for (var value in stages.values) {
      if (value is Map<String, dynamic>) {
        stagesList.add(value);
      } else if (value is Map) {
        // Convert dynamic Map to Map<String, dynamic>
        stagesList.add(Map<String, dynamic>.from(value));
      }
    }
    
    stagesList.sort((a, b) {
      final order = ['syn', 'init', 'floorplan', 'place', 'cts', 'postcts', 'route', 'postroute'];
      final aIdx = order.indexOf(a['stage']?.toString().toLowerCase() ?? '');
      final bIdx = order.indexOf(b['stage']?.toString().toLowerCase() ?? '');
      if (aIdx == -1 && bIdx == -1) return 0;
      if (aIdx == -1) return 1;
      if (bIdx == -1) return -1;
      return aIdx.compareTo(bIdx);
    });
    
    if (_stageFilter == 'all') return stagesList;
    return stagesList.where((s) => s['stage']?.toString().toLowerCase() == _stageFilter.toLowerCase()).toList();
  }


  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    if (!authState.isAuthenticated) {
      return const Center(child: Text('Please log in to view files.'));
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Show project and domain selection if not selected
    if (_selectedProject == null || _selectedDomain == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 48),
                  _buildProjectDomainSelection(),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_groupedData.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildProjectDomainSelection(),
                  const SizedBox(height: 48),
                  Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No data available for selected project and domain',
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final activeRun = _getActiveRun();
    final activeStages = _getActiveStages();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildViewTypeSelector(),
                const SizedBox(height: 24),
                _buildProjectDomainSelection(),
                const SizedBox(height: 24),
                if (_viewType == 'engineer') ...[
                  _buildFilterBar(),
                  const SizedBox(height: 24),
                  _buildSummarySection(activeRun, activeStages),
                  const SizedBox(height: 24),
                  _buildComparisonMatrix(activeStages),
                  const SizedBox(height: 24),
                  _buildMetricsGraphSection(activeStages),
                ] else if (_viewType == 'lead') ...[
                  _buildFilterBar(),
                  const SizedBox(height: 24),
                  _buildLeadView(activeStages),
                ] else if (_viewType == 'manager') ...[
                  _buildManagerView(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }



  Widget _buildViewTypeSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Text(
            'VIEW TYPE:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF94A3B8),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 16),
          _buildViewTypeChip('Engineer View', 'engineer'),
          const SizedBox(width: 8),
          _buildViewTypeChip('Lead View', 'lead'),
          const SizedBox(width: 8),
          _buildViewTypeChip('Manager View', 'manager'),
        ],
      ),
    );
  }

  Widget _buildViewTypeChip(String label, String value) {
    final isSelected = _viewType == value;
    return GestureDetector(
      onTap: () => setState(() => _viewType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedProject != null || _selectedBlock != null || _selectedTag != null || _selectedExperiment != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_selectedProject != null)
                  Text(
                    _selectedProject!.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                      letterSpacing: 1.5,
                    ),
                  ),
                if (_selectedBlock != null) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Icon(Icons.chevron_right, size: 10, color: Color(0xFF94A3B8)),
                  ),
                  Text(
                    _selectedBlock!.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
                if (_selectedTag != null) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Icon(Icons.chevron_right, size: 10, color: Color(0xFF94A3B8)),
                  ),
                  Text(
                    _selectedTag!.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
                if (_selectedExperiment != null) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Icon(Icons.chevron_right, size: 10, color: Color(0xFF94A3B8)),
                  ),
                  Text(
                    _selectedExperiment!.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF1E293B),
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.memory, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PD Flow Dashboard',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E293B),
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'FULL FLOW COMPARISON REPORT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF94A3B8),
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  void _updateProject(String? projectName) async {
    if (projectName == null || projectName.isEmpty) {
      setState(() {
        _selectedProject = null;
        _selectedDomain = null;
        _availableDomainsForProject = [];
        _groupedData = {};
        _selectedBlock = null;
        _selectedTag = null;
        _selectedExperiment = null;
      });
      return;
    }

    setState(() {
      _selectedProject = projectName;
      _selectedDomain = null;
      _availableDomainsForProject = [];
      _isLoadingDomains = true;
      _groupedData = {};
      _selectedBlock = null;
      _selectedTag = null;
      _selectedExperiment = null;
    });

    // Get domains for this project
    try {
      final authState = ref.read(authProvider);
      final token = authState.token;
      
      // Load EDA files to find domains for this project
      final filesResponse = await _apiService.getEdaFiles(
        token: token,
        limit: 1000,
      );
      
      final files = filesResponse['files'] ?? [];
      final domainSet = <String>{};
      
      for (var file in files) {
        final projectNameFromFile = file['project_name'] ?? 'Unknown';
        final domainName = file['domain_name'] ?? '';
        if (projectNameFromFile == projectName && domainName.isNotEmpty) {
          domainSet.add(domainName);
        }
      }
      
      final availableDomains = domainSet.toList()..sort();
      
      setState(() {
        _availableDomainsForProject = availableDomains;
        _isLoadingDomains = false;
        // Auto-select if only one domain
        if (availableDomains.length == 1) {
          _selectedDomain = availableDomains.first;
          _loadInitialData();
        }
      });
    } catch (e) {
      setState(() {
        _isLoadingDomains = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading domains: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _updateDomain(String? domainName) {
    setState(() {
      _selectedDomain = domainName;
      _groupedData = {};
      _selectedBlock = null;
      _selectedTag = null;
      _selectedExperiment = null;
    });
    
    if (domainName != null && domainName.isNotEmpty) {
      _loadInitialData();
    }
  }

  void _updateCascadingFilters({String? p, String? b, String? t, String? e}) {
    setState(() {
      if (p != null) {
        _selectedProject = p;
        final projectValue = _groupedData[p];
        if (projectValue is Map && projectValue.isNotEmpty) {
          _selectedBlock = projectValue.keys.first;
          final blockValue = projectValue[_selectedBlock];
          if (blockValue is Map && blockValue.isNotEmpty) {
            _selectedTag = blockValue.keys.first;
            final tagValue = blockValue[_selectedTag];
            if (tagValue is Map && tagValue.isNotEmpty) {
              _selectedExperiment = tagValue.keys.first;
            }
          }
        }
      } else if (b != null) {
        _selectedBlock = b;
        final projectValue = _groupedData[_selectedProject];
        if (projectValue is Map) {
          final blockValue = projectValue[b];
          if (blockValue is Map && blockValue.isNotEmpty) {
            _selectedTag = blockValue.keys.first;
            final tagValue = blockValue[_selectedTag];
            if (tagValue is Map && tagValue.isNotEmpty) {
              _selectedExperiment = tagValue.keys.first;
            }
          }
        }
      } else if (t != null) {
        _selectedTag = t;
        final projectValue = _groupedData[_selectedProject];
        if (projectValue is Map) {
          final blockValue = projectValue[_selectedBlock];
          if (blockValue is Map) {
            final tagValue = blockValue[t];
            if (tagValue is Map && tagValue.isNotEmpty) {
              _selectedExperiment = tagValue.keys.first;
            }
          }
        }
      } else if (e != null) {
        _selectedExperiment = e;
      }
    });
  }

  Widget _buildProjectDomainSelection() {
    // Safely get project names
    final projectNames = <String>[];
    try {
      if (_projects.isNotEmpty) {
        projectNames.addAll(
          _projects.map((p) => p['name']?.toString() ?? 'Unknown').toList().cast<String>()
        );
      }
    } catch (e) {
      print('Error getting project names: $e');
    }
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _buildDropdown(
            'Project',
            projectNames,
            _selectedProject,
            (v) => _updateProject(v),
            width: 300,
            placeholder: 'Select Project',
          ),
          if (_selectedProject != null) ...[
            if (_isLoadingDomains)
              Container(
                padding: const EdgeInsets.all(12),
                width: 300,
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Loading domains...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              )
            else
              _buildDropdown(
                'Domain',
                _availableDomainsForProject,
                _selectedDomain,
                (v) => _updateDomain(v),
                width: 300,
                placeholder: 'Select Domain',
              ),
            if (_selectedProject != null && _availableDomainsForProject.isEmpty && !_isLoadingDomains)
              Container(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'No domains found for this project',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    List<String> availableBlocks = [];
    List<String> availableTags = [];
    List<String> availableExperiments = [];
    
    if (_selectedProject != null && _selectedDomain != null) {
      final projectValue = _groupedData[_selectedProject];
      if (projectValue is Map) {
        final projectData = Map<String, dynamic>.from(projectValue);
        availableBlocks = projectData.keys.toList().cast<String>();
        
        if (_selectedBlock != null) {
          final blockValue = projectData[_selectedBlock];
          if (blockValue is Map) {
            final blockData = Map<String, dynamic>.from(blockValue);
            availableTags = blockData.keys.toList().cast<String>();
            
            if (_selectedTag != null) {
              final tagValue = blockData[_selectedTag];
              if (tagValue is Map) {
                final tagData = Map<String, dynamic>.from(tagValue);
                availableExperiments = tagData.keys.toList().cast<String>();
              }
            }
          }
        }
      }
    }

    // Get all stages (not filtered) for the dropdown options
    final run = _getActiveRun();
    List<String> stageNames = [];
    if (run != null) {
      final stagesValue = run['stages'];
      final stages = (stagesValue is Map) 
          ? Map<String, dynamic>.from(stagesValue) 
          : <String, dynamic>{};
      
      // Get all stage names from all stages
      for (var value in stages.values) {
        if (value is Map) {
          final stageMap = value is Map<String, dynamic> 
              ? value 
              : Map<String, dynamic>.from(value);
          final stageName = stageMap['stage']?.toString();
          if (stageName != null && stageName.isNotEmpty) {
            stageNames.add(stageName);
          }
        }
      }
      // Remove duplicates and sort
      stageNames = stageNames.toSet().toList();
      // Sort by stage order
      final order = ['syn', 'init', 'floorplan', 'place', 'cts', 'postcts', 'route', 'postroute'];
      stageNames.sort((a, b) {
        final aIdx = order.indexOf(a.toLowerCase());
        final bIdx = order.indexOf(b.toLowerCase());
        if (aIdx == -1 && bIdx == -1) return a.compareTo(b);
        if (aIdx == -1) return 1;
        if (bIdx == -1) return -1;
        return aIdx.compareTo(bIdx);
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        final isTablet = constraints.maxWidth < 1000;
        
        // Ensure we have valid constraints
        final maxWidth = constraints.maxWidth > 0 ? constraints.maxWidth : double.infinity;
        
        // Calculate widths with proper bounds checking
        double calculateWidth(bool isLast) {
          if (isMobile) {
            return maxWidth > 40 ? maxWidth - 40 : 200.0;
          } else if (isTablet) {
            final width = (maxWidth - 36) / 2;
            return width > 0 ? width : 200.0;
          } else {
            final width = isLast ? (maxWidth - 104) / 5 : (maxWidth - 104) / 5;
            return width > 0 ? width : 200.0;
          }
        }
        
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _buildDropdown(
                'Block Name',
                availableBlocks,
                _selectedBlock ?? '',
                (v) => _updateCascadingFilters(b: v),
                width: calculateWidth(false),
              ),
              _buildDropdown(
                'RTL Version',
                availableTags,
                _selectedTag ?? '',
                (v) => _updateCascadingFilters(t: v),
                width: calculateWidth(false),
              ),
              _buildDropdown(
                'Experiment',
                availableExperiments,
                _selectedExperiment ?? '',
                (v) => _updateCascadingFilters(e: v),
                width: calculateWidth(false),
              ),
              _buildDropdown(
                'Stage Filter',
                ['all', ...stageNames],
                _stageFilter,
                (v) => setState(() => _stageFilter = v ?? 'all'),
                isBlue: true,
                width: calculateWidth(true),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDropdown(
    String label,
    List<String> items,
    String? value,
    ValueChanged<String?> onChanged, {
    bool isBlue = false,
    double? width,
    String? placeholder,
  }) {
    final validWidth = width != null && width > 0 ? width : null;
    final hasValue = value != null && value.isNotEmpty && items.contains(value);
    final displayValue = hasValue ? value : null;
    
    return SizedBox(
      width: validWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: isBlue ? const Color(0xFF2563EB) : const Color(0xFF94A3B8),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              color: isBlue ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
                value: displayValue,
            isExpanded: true,
            hint: placeholder != null 
                ? Text(
                    placeholder,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  )
                : null,
            style: TextStyle(
              fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isBlue ? Colors.blue[700] : Colors.black87,
                ),
                items: items.map((e) => DropdownMenuItem(
                  value: e,
                  child: Text(e.toUpperCase()),
                )).toList(),
            onChanged: items.isEmpty ? null : onChanged,
            ),
          ),
        ),
      ],
      ),
    );
  }

  Widget _buildSummarySection(Map<String, dynamic>? activeRun, List<Map<String, dynamic>> stages) {
    if (activeRun == null || stages.isEmpty) return const SizedBox();

    double? globalWorstSlack;
    for (var stage in stages) {
      final slacks = [
        _parseNumeric(stage['internal_timing_r2r_wns']),
        _parseNumeric(stage['interface_timing_i2r_wns']),
        _parseNumeric(stage['interface_timing_r2o_wns']),
        _parseNumeric(stage['interface_timing_i2o_wns']),
        _parseNumeric(stage['hold_wns']),
      ];
      
      for (var slack in slacks) {
        if (slack != null && slack is num) {
          if (globalWorstSlack == null || slack < globalWorstSlack) {
            globalWorstSlack = slack.toDouble();
          }
        }
      }
    }

    final lastStage = stages.last;
    final totalWarnings = stages.fold<int>(0, (sum, s) => sum + ((s['log_warnings'] as num?)?.toInt() ?? 0));
    final totalCritical = stages.fold<int>(0, (sum, s) => sum + ((s['log_critical'] as num?)?.toInt() ?? 0));

    return LayoutBuilder(
      builder: (context, constraints) {
        // Ensure we have valid constraints
        final maxWidth = constraints.maxWidth > 0 && constraints.maxWidth.isFinite 
            ? constraints.maxWidth 
            : 1000.0;
        final isMobile = maxWidth < 1000;
        
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMobile) ...[
              _buildInfoGrid(activeRun, lastStage, maxWidth > 40 ? maxWidth - 40 : 200.0),
              const SizedBox(height: 24),
              _buildMetricsCard(globalWorstSlack, totalWarnings, totalCritical, maxWidth > 40 ? maxWidth - 40 : 200.0),
            ] else
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildInfoGrid(activeRun, lastStage, ((maxWidth * 2 / 3) - 12).clamp(200.0, double.infinity)),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: _buildMetricsCard(globalWorstSlack, totalWarnings, totalCritical, ((maxWidth / 3) - 12).clamp(200.0, double.infinity)),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildInfoGrid(Map<String, dynamic> activeRun, Map<String, dynamic> lastStage, double width) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.folder_open, size: 16, color: Color(0xFF3B82F6)),
                    SizedBox(width: 8),
                    Text(
                      'ACTIVE RUN SUMMARY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF475569),
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                _statusBadge(lastStage['run_status']),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _infoRow(Icons.storage, 'Project', _selectedProject ?? 'N/A'),
                _infoRow(Icons.memory, 'Block', _selectedBlock ?? 'N/A'),
                _infoRow(Icons.layers, 'RTL Version', _selectedTag ?? 'N/A'),
                _infoRow(Icons.person, 'User', lastStage['user_name']?.toString() ?? 'N/A'),
                const Divider(height: 32, color: Color(0xFFF1F5F9)),
                _infoRow(Icons.open_in_new, 'Run Dir', activeRun['run_directory']?.toString() ?? 'N/A', isFull: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsCard(double? worstSlack, int warnings, int critical, double width) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFEE2E2)),
            ),
            child: Column(
              children: [
                const Text(
                  'GLOBAL WORST SLACK',
                  style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  worstSlack != null ? worstSlack.toStringAsFixed(3) : '--',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFB91C1C),
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _metricBox('TOTAL WARNINGS', warnings.toString(), const Color(0xFFF8FAFC))),
              const SizedBox(width: 16),
              Expanded(child: _metricBox('TOTAL CRITICAL', critical.toString(), const Color(0xFFF8FAFC))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {bool isFull = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFF94A3B8),
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricBox(String label, String value, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w800,
              fontSize: 9,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String? status) {
    Color bg = const Color(0xFFF1F5F9);
    Color text = const Color(0xFF64748B);
    Color border = const Color(0xFFE2E8F0);
    
    final s = status?.toString().toLowerCase() ?? 'unknown';
    if (s == 'fail') {
      bg = const Color(0xFFFEF2F2);
      text = const Color(0xFFDC2626);
      border = const Color(0xFFFEE2E2);
    } else if (s == 'success') {
      bg = const Color(0xFFF0FDF4);
      text = const Color(0xFF16A34A);
      border = const Color(0xFFDCFCE7);
    } else if (s == 'continue_with_error') {
      bg = const Color(0xFFFFF7ED);
      text = const Color(0xFFEA580C);
      border = const Color(0xFFFFEDD5);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: Text(
        s.toUpperCase().replaceAll('_', ' '),
        style: TextStyle(
          color: text,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildMetricsGraphSection(List<Map<String, dynamic>> stages) {
    if (stages.isEmpty) return const SizedBox();

    final allMetricGroups = ['INTERNAL (R2R)', 'INTERFACE I2R', 'INTERFACE R2O', 'INTERFACE I2O', 'HOLD'];
    final allMetricTypes = ['WNS', 'TNS', 'NVP'];

    // Generate all combinations of selected groups and types
    final graphCombinations = <Map<String, String>>[];
    for (var group in _selectedMetricGroups) {
      for (var type in _selectedMetricTypes) {
        graphCombinations.add({'group': group, 'type': type});
      }
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.show_chart, size: 20, color: Color(0xFF0F172A)),
                  SizedBox(width: 12),
                  Text(
                    'Timing Metrics Matrix Visualization',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Multi-select chips for Metric Groups
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SELECT METRIC GROUPS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF94A3B8),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: allMetricGroups.map((group) {
                  final isSelected = _selectedMetricGroups.contains(group);
                  return FilterChip(
                    label: Text(group),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedMetricGroups.add(group);
                        } else {
                          _selectedMetricGroups.remove(group);
                        }
                        if (_selectedMetricGroups.isEmpty) {
                          _selectedMetricGroups.add(allMetricGroups.first);
                        }
                      });
                    },
                    selectedColor: const Color(0xFFEFF6FF),
                    checkmarkColor: const Color(0xFF2563EB),
                    labelStyle: TextStyle(
                      color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Multi-select chips for Metric Types
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SELECT METRIC TYPES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF94A3B8),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: allMetricTypes.map((type) {
                  final isSelected = _selectedMetricTypes.contains(type);
                  return FilterChip(
                    label: Text(type),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedMetricTypes.add(type);
                        } else {
                          _selectedMetricTypes.remove(type);
                        }
                        if (_selectedMetricTypes.isEmpty) {
                          _selectedMetricTypes.add(allMetricTypes.first);
                        }
                      });
                    },
                    selectedColor: const Color(0xFFEFF6FF),
                    checkmarkColor: const Color(0xFF2563EB),
                    labelStyle: TextStyle(
                      color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 32),
          // Visualization type selector
          Row(
            children: [
              const Text(
                'VIEW TYPE:',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF94A3B8),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 16),
              _buildVisualizationTypeChip('Graph', 'graph'),
              const SizedBox(width: 8),
              _buildVisualizationTypeChip('Heat Map', 'heatmap'),
            ],
          ),
          const SizedBox(height: 24),
          // Single combined graph or heat map with all selected metrics
          if (graphCombinations.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Text('Please select at least one metric group and type', style: TextStyle(color: Colors.grey)),
              ),
            )
          else if (_visualizationType == 'heatmap')
            _buildHeatMap(stages, graphCombinations)
          else
            _buildCombinedGraph(stages, graphCombinations),
        ],
      ),
    );
  }
  
  Widget _buildVisualizationTypeChip(String label, String value) {
    final isSelected = _visualizationType == value;
    return GestureDetector(
      onTap: () => setState(() => _visualizationType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
  
  Widget _buildHeatMap(List<Map<String, dynamic>> stages, List<Map<String, String>> combinations) {
    if (stages.isEmpty || combinations.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text('No data available for heat map', style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    
    final stageNames = stages.map((s) => s['stage']?.toString() ?? 'Unknown').toList();
    
    // Build heat map data: rows = metric combinations, columns = stages
    final heatMapData = <List<double?>>[];
    final rowLabels = <String>[];
    
    for (var combo in combinations) {
      final group = combo['group']!;
      final type = combo['type']!;
      final row = <double?>[];
      
      for (var stage in stages) {
        final val = _getMetricValue(stage, group, type);
        row.add(val);
      }
      
      // Only add row if it has at least one value
      if (row.any((v) => v != null)) {
        heatMapData.add(row);
        rowLabels.add('$group - $type');
      }
    }
    
    if (heatMapData.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text('No data available for the selected metrics', style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    
    // Calculate min/max for color scaling
    double? minVal;
    double? maxVal;
    for (var row in heatMapData) {
      for (var val in row) {
        if (val != null) {
          if (minVal == null || val < minVal) minVal = val;
          if (maxVal == null || val > maxVal) maxVal = val;
        }
      }
    }
    
    // If all values are the same, add some range for visualization
    if (minVal != null && maxVal != null && minVal == maxVal) {
      final absVal = minVal.abs();
      minVal = minVal - (absVal > 0 ? absVal * 0.1 : 0.1);
      maxVal = maxVal + (absVal > 0 ? absVal * 0.1 : 0.1);
    }
    
    final range = (maxVal ?? 1.0) - (minVal ?? 0.0);
    
    // Color function: red for negative/bad, green for positive/good (for WNS/TNS)
    // For NVP, reverse: green for low, red for high
    Color getColorForValue(double? value, String type) {
      if (value == null) return Colors.grey.shade200;
      
      // Normalize value to 0-1 range
      final normalized = range > 0 ? ((value - (minVal ?? 0.0)) / range).clamp(0.0, 1.0) : 0.5;
      
      if (type == 'NVP') {
        // For NVP: low is good (green), high is bad (red)
        if (normalized < 0.33) {
          return Color.lerp(const Color(0xFF10B981), const Color(0xFFFEF3C7), normalized * 3)!;
        } else if (normalized < 0.67) {
          return Color.lerp(const Color(0xFFFEF3C7), const Color(0xFFF59E0B), (normalized - 0.33) * 3)!;
        } else {
          return Color.lerp(const Color(0xFFF59E0B), const Color(0xFFDC2626), (normalized - 0.67) * 3)!;
        }
      } else {
        // For WNS/TNS: negative is bad (red), positive is good (green)
        if (normalized < 0.33) {
          return Color.lerp(const Color(0xFFDC2626), const Color(0xFFF59E0B), normalized * 3)!;
        } else if (normalized < 0.67) {
          return Color.lerp(const Color(0xFFF59E0B), const Color(0xFFFEF3C7), (normalized - 0.33) * 3)!;
        } else {
          return Color.lerp(const Color(0xFFFEF3C7), const Color(0xFF10B981), (normalized - 0.67) * 3)!;
        }
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Color scale legend
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Color Scale',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 20,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFDC2626),
                            const Color(0xFFF59E0B),
                            const Color(0xFFFEF3C7),
                            const Color(0xFF10B981),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Min: ${minVal?.toStringAsFixed(2) ?? "N/A"}',
                    style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Max: ${maxVal?.toStringAsFixed(2) ?? "N/A"}',
                    style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Heat map table
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: Table(
              border: TableBorder.all(color: const Color(0xFFE2E8F0), width: 1),
              defaultColumnWidth: const FixedColumnWidth(100),
              children: [
                // Header row with stage names
                TableRow(
                  decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                  children: [
                    const TableCell(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Metric',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ),
                    ...stageNames.map((stage) => TableCell(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          stage.toUpperCase().replaceAll('_', ' '),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                            color: Color(0xFF64748B),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )).toList(),
                  ],
                ),
                // Data rows
                ...List.generate(heatMapData.length, (rowIdx) {
                  final row = heatMapData[rowIdx];
                  final label = rowLabels[rowIdx];
                  final type = combinations[rowIdx]['type']!;
                  
                  return TableRow(
                    children: [
                      TableCell(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          color: Colors.white,
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                      ...List.generate(row.length, (colIdx) {
                        final value = row[colIdx];
                        final color = getColorForValue(value, type);
                        
                        return TableCell(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            color: color,
                            child: Center(
                              child: Text(
                                value != null ? value.toStringAsFixed(2) : '–',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  color: value != null 
                                      ? (value < 0 ? Colors.white : const Color(0xFF0F172A))
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSingleGraph(List<Map<String, dynamic>> stages, String group, String type) {
    final points = <FlSpot>[];
    final stageNames = <String>[];
    
    // Build points and stage names for all stages to maintain proper alignment
    for (int i = 0; i < stages.length; i++) {
      final stage = stages[i];
      final stageName = stage['stage']?.toString() ?? 'Unknown';
      final val = _getMetricValue(stage, group, type);
      
      // Always add stage name to maintain X-axis alignment
      stageNames.add(stageName);
      
      // Add point - use actual value if available, otherwise 0
      if (val != null) {
        points.add(FlSpot(i.toDouble(), val));
      } else {
        // Add point with 0 value to maintain X-axis positions
        points.add(FlSpot(i.toDouble(), 0));
      }
    }

    Color lineColor = const Color(0xFF2563EB);
    if (type == 'WNS') {
      lineColor = const Color(0xFFDC2626); 
    } else if (type == 'TNS') {
      lineColor = const Color(0xFFF59E0B);
    } else if (type == 'NVP') {
      lineColor = const Color(0xFF64748B);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$group - $type',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: points.isEmpty 
              ? const Center(
                  child: Text('No data', style: TextStyle(fontSize: 10, color: Colors.grey)),
                )
              : LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFFE2E8F0), strokeWidth: 1),
                    ),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 24,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            int idx = value.toInt();
                            if (idx >= 0 && idx < stageNames.length) {
                              String name = stageNames[idx].replaceAll('_', ' ').toUpperCase();
                              // Show full name if space allows, otherwise truncate
                              if (name.length > 8) name = '${name.substring(0, 8)}..'; 
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  name, 
                                  style: const TextStyle(fontSize: 9, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                                ),
                              );
                            }
                            return const Text('');
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true, 
                          reservedSize: 30,
                          getTitlesWidget: (value, meta) {
                            return Text(
                              value.toStringAsFixed(1),
                              style: const TextStyle(fontSize: 8, color: Color(0xFF64748B)),
                            );
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: true, border: Border.all(color: const Color(0xFFE2E8F0))),
                    lineBarsData: [
                      LineChartBarData(
                        spots: points,
                        isCurved: true,
                        color: lineColor,
                        barWidth: 2,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(show: true, color: lineColor.withOpacity(0.1)),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        tooltipBgColor: Colors.blueGrey.shade800,
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((spot) {
                            int idx = spot.x.toInt();
                            String stageName = idx >= 0 && idx < stageNames.length 
                                ? stageNames[idx].toUpperCase().replaceAll('_', ' ')
                                : 'Unknown';
                            return LineTooltipItem(
                              '$stageName\n$type: ${spot.y.toStringAsFixed(3)}',
                              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                            );
                          }).toList();
                        }
                      )
                    ),
                    minY: points.isEmpty ? 0 : (points.map((p) => p.y).reduce((a, b) => a < b ? a : b) - 0.1),
                    maxY: points.isEmpty ? 1 : (points.map((p) => p.y).reduce((a, b) => a > b ? a : b) + 0.1),
                  ),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildCombinedGraph(List<Map<String, dynamic>> stages, List<Map<String, String>> combinations) {
    final stageNames = stages.map((s) => s['stage']?.toString() ?? 'Unknown').toList();
    
    // Generate colors for each combination
    final colors = [
      const Color(0xFFDC2626), // Red
      const Color(0xFF2563EB),  // Blue
      const Color(0xFFF59E0B), // Orange
      const Color(0xFF10B981),  // Green
      const Color(0xFF8B5CF6),  // Purple
      const Color(0xFFEC4899),  // Pink
      const Color(0xFF06B6D4),  // Cyan
      const Color(0xFFF97316),  // Orange Red
      const Color(0xFF84CC16),  // Lime
      const Color(0xFF6366F1),  // Indigo
    ];
    
    // Build line data for each combination
    final lineBarsData = <LineChartBarData>[];
    final legendItems = <Widget>[];
    
    for (int i = 0; i < combinations.length; i++) {
      final combo = combinations[i];
      final group = combo['group']!;
      final type = combo['type']!;
      final points = <FlSpot>[];
      
      for (int j = 0; j < stages.length; j++) {
        final stage = stages[j];
        final val = _getMetricValue(stage, group, type);
        // Only add points with actual values (not null)
        if (val != null) {
          points.add(FlSpot(j.toDouble(), val));
        }
      }
      
      // Only add line data if there are points to display
      if (points.isNotEmpty) {
        final color = colors[i % colors.length];
        final label = '$group - $type';
        
        lineBarsData.add(
          LineChartBarData(
            spots: points,
            isCurved: true,
            color: color,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: false),
          ),
        );
        
        legendItems.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 16,
                height: 3,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }
    }
    
    // Check if we have any data to display
    if (lineBarsData.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            'No data available for the selected metrics and stages',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    
    // Calculate min/max Y values across all lines (only from actual data points)
    double minY = 0.0;
    double maxY = 1.0;
    bool hasData = false;
    
    for (var lineData in lineBarsData) {
      for (var spot in lineData.spots) {
        if (!hasData) {
          minY = spot.y;
          maxY = spot.y;
          hasData = true;
        } else {
          if (spot.y < minY) minY = spot.y;
          if (spot.y > maxY) maxY = spot.y;
        }
      }
    }
    
    // Add padding to Y-axis for better visualization
    if (hasData) {
      final range = maxY - minY;
      // Add 10% padding on each side, with minimum padding
      // Handle case when range is 0 or very small
      double yPadding;
      if (range == 0) {
        // When all values are the same, use a percentage of the absolute value
        final absValue = minY.abs();
        yPadding = absValue > 0 ? absValue * 0.1 : 0.1;
      } else {
        // Normal case: clamp between 10% and 15% of range, but ensure minimum
        final minPadding = range * 0.1;
        final maxPadding = range * 0.15;
        yPadding = minPadding.clamp(0.1, maxPadding);
      }
      
      // Ensure we show zero line if values span both positive and negative
      if (minY < 0 && maxY > 0) {
        // If spanning zero, ensure zero is visible with padding
        final maxAbs = minY.abs() > maxY.abs() ? minY.abs() : maxY.abs();
        minY = -maxAbs - yPadding;
        maxY = maxAbs + yPadding;
      } else {
        // Add padding to min/max
        minY = minY - yPadding;
        maxY = maxY + yPadding;
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Legend
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: legendItems,
        ),
        const SizedBox(height: 16),
        // Combined graph
        SizedBox(
          height: 400,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                getDrawingHorizontalLine: (value) {
                  // Highlight zero line if it's visible
                  if (value == 0 && minY < 0 && maxY > 0) {
                    return const FlLine(color: Color(0xFF94A3B8), strokeWidth: 1.5);
                  }
                  return const FlLine(color: Color(0xFFE2E8F0), strokeWidth: 1);
                },
                getDrawingVerticalLine: (value) => const FlLine(color: Color(0xFFE2E8F0), strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      int idx = value.toInt();
                      if (idx >= 0 && idx < stageNames.length) {
                        String name = stageNames[idx].replaceAll('_', ' ').toUpperCase();
                        if (name.length > 8) name = '${name.substring(0, 8)}..';
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            name,
                            style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                          ),
                        );
                      }
                      return const Text('');
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 50,
                    interval: _calculateYInterval(minY, maxY),
                    getTitlesWidget: (value, meta) {
                      // Format based on value magnitude
                      String label;
                      if (value.abs() >= 1000) {
                        label = '${(value / 1000).toStringAsFixed(1)}k';
                      } else if (value.abs() >= 1) {
                        label = value.toStringAsFixed(1);
                      } else {
                        label = value.toStringAsFixed(2);
                      }
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            color: value == 0 && minY < 0 && maxY > 0
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                            fontWeight: value == 0 ? FontWeight.w700 : FontWeight.w400,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: true, border: Border.all(color: const Color(0xFFE2E8F0))),
              lineBarsData: lineBarsData,
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  tooltipBgColor: Colors.blueGrey.shade800,
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      int idx = spot.x.toInt();
                      String stageName = idx >= 0 && idx < stageNames.length
                          ? stageNames[idx].toUpperCase().replaceAll('_', ' ')
                          : 'Unknown';
                      final combo = combinations[spot.barIndex];
                      return LineTooltipItem(
                        '$stageName\n${combo['group']} - ${combo['type']}: ${spot.y.toStringAsFixed(3)}',
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                      );
                    }).toList();
                  },
                ),
              ),
              minY: minY,
              maxY: maxY,
              minX: 0,
              maxX: stages.length > 1 ? (stages.length - 1).toDouble() : (stages.length > 0 ? 1.0 : 1.0),
            ),
          ),
        ),
      ],
    );
  }

  double _calculateYInterval(double minY, double maxY) {
    final range = maxY - minY;
    if (range <= 0) return 1.0;
    
    // Calculate appropriate interval based on range
    if (range <= 0.5) return 0.1;
    if (range <= 2) return 0.5;
    if (range <= 10) return 1.0;
    if (range <= 50) return 5.0;
    if (range <= 100) return 10.0;
    if (range <= 500) return 50.0;
    if (range <= 1000) return 100.0;
    return 200.0;
  }

  double? _getMetricValue(Map<String, dynamic> stage, String group, String type) {
       String prefix = '';
       switch (group) {
         case 'INTERNAL (R2R)': prefix = 'internal_timing_r2r'; break;
         case 'INTERFACE I2R': prefix = 'interface_timing_i2r'; break;
         case 'INTERFACE R2O': prefix = 'interface_timing_r2o'; break;
         case 'INTERFACE I2O': prefix = 'interface_timing_i2o'; break;
         case 'HOLD': prefix = 'hold'; break;
       }
       String key = '${prefix}_${type.toLowerCase()}';
       return _parseNumeric(stage[key]);
  }

  Widget _buildComparisonMatrix(List<Map<String, dynamic>> stages) {
    if (stages.isEmpty) return const SizedBox();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Table Title and Legend
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.table_chart_outlined, size: 20, color: Color(0xFF0F172A)),
                        SizedBox(width: 12),
                Text(
                          'Stage Metrics Comparison',
                  style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
                    IconButton(
                      icon: const Icon(Icons.fullscreen),
                      tooltip: 'Full Screen View',
                      color: const Color(0xFF64748B),
                      onPressed: () => _showFullScreenTable(stages),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildLegend(),
              ],
            ),
          ),
          
          // The Table
          _buildTableLayout(
            stages, 
            _horizontalScrollController, 
            _verticalScrollController, 
            fixedHeight: 600
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 24,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _legendItem('WNS', 'Worst Negative Slack', const Color(0xFFEF4444)),
        _legendItem('TNS', 'Total Negative Slack', const Color(0xFFF59E0B)),
        _legendItem('NVP', 'Number of Violating Paths', const Color(0xFF64748B)),
        Container(width: 1, height: 12, color: Colors.grey[300]),
        _legendItem('Critical', '< -0.5ns', const Color(0xFFB91C1C), isBox: true),
        _legendItem('Warning', '< 0.0ns', const Color(0xFFEF4444), isBox: true),
        _legendItem('Safe', '≥ 0.0ns', const Color(0xFF10B981), isBox: true),
      ],
    );
  }

  Widget _legendItem(String label, String desc, Color color, {bool isBox = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isBox)
          Container(
            width: 8,
            height: 8,
      decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          )
        else
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
        const SizedBox(width: 8),
        Text(
          desc,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // A unified header builder that creates a Column of Rows.
  // It manually calculates widths to ensure "merged" cells (Row 1) align perfectly 
  // with the sub-columns (Row 2) which match the Table below.
  Widget _buildUnifiedHeader(Map<int, TableColumnWidth> colWidths) {
    // Helper to get raw double value
    double getW(int idx) => (colWidths[idx] as FixedColumnWidth).value;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
          children: [
          // LEVEL 1: Dimensions / Groups
          Row(
              children: [
              _buildHeaderCell('STAGE INFO', width: getW(0) + getW(1), isMain: true),
              _buildHeaderCell('INTERNAL (R2R)', width: getW(2) + getW(3) + getW(4), isMain: true, color: Colors.blue[50]),
              _buildHeaderCell('INTERFACE I2R', width: getW(5) + getW(6) + getW(7), isMain: true, color: Colors.indigo[50]),
              _buildHeaderCell('INTERFACE R2O', width: getW(8) + getW(9) + getW(10), isMain: true, color: Colors.purple[50]),
              _buildHeaderCell('INTERFACE I2O', width: getW(11) + getW(12) + getW(13), isMain: true, color: Colors.indigo[50]),
              _buildHeaderCell('HOLD', width: getW(14) + getW(15) + getW(16), isMain: true),
              _buildHeaderCell('CONSTRAINTS', width: (getW(17) + getW(18)) + (getW(19) + getW(20)) + (getW(21) + getW(22)), isMain: true, color: Colors.orange[50]),
              _buildHeaderCell('INTEGRITY', width: getW(23) + getW(24) + getW(25) + getW(26), isMain: true),
              _buildHeaderCell('POWER / IR', width: getW(27) + getW(28) + getW(29) + getW(30), isMain: true),
              _buildHeaderCell('PHYSICAL VERIF', width: getW(31) + getW(32) + getW(33), isMain: true),
              _buildHeaderCell('SIGNOFF', width: getW(34) + getW(35) + getW(36) + getW(37), isMain: true),
              _buildHeaderCell('PHYSICAL STATS', width: getW(38) + getW(39) + getW(40), isMain: true),
              _buildHeaderCell('LOGS', width: getW(41) + getW(42) + getW(43), isMain: true),
              _buildHeaderCell('AI SUM', width: getW(44), isMain: true),
              _buildHeaderCell('RESOURCES', width: getW(45) + getW(46), isMain: true),
            ],
          ),
          Divider(height: 1, color: Colors.grey.withOpacity(0.2)),
          // LEVEL 2: Specific Metrics
          Row(
            children: [
              _buildHeaderCell('Stage', width: getW(0)),
              _buildHeaderCell('Status', width: getW(1)),
              
              // Internal
              _buildHeaderCell('WNS', width: getW(2)),
              _buildHeaderCell('TNS', width: getW(3)),
              _buildHeaderCell('NVP', width: getW(4), isLastInGroup: true),

              // I2R
              _buildHeaderCell('WNS', width: getW(5)),
              _buildHeaderCell('TNS', width: getW(6)),
              _buildHeaderCell('NVP', width: getW(7), isLastInGroup: true),

              // R2O
              _buildHeaderCell('WNS', width: getW(8)),
              _buildHeaderCell('TNS', width: getW(9)),
              _buildHeaderCell('NVP', width: getW(10), isLastInGroup: true),

              // I2O
              _buildHeaderCell('WNS', width: getW(11)),
              _buildHeaderCell('TNS', width: getW(12)),
              _buildHeaderCell('NVP', width: getW(13), isLastInGroup: true),
              
              // Hold
              _buildHeaderCell('WNS', width: getW(14)),
              _buildHeaderCell('TNS', width: getW(15)),
              _buildHeaderCell('NVP', width: getW(16), isLastInGroup: true),

              // Constraints (Max Tran, Max Cap, Max Fanout)
              _buildHeaderCell('Tran WNS', width: getW(17)),
              _buildHeaderCell('Tran NVP', width: getW(18)),
              _buildHeaderCell('Cap WNS', width: getW(19)),
              _buildHeaderCell('Cap NVP', width: getW(20)),
              _buildHeaderCell('Fan WNS', width: getW(21)),
              _buildHeaderCell('Fan NVP', width: getW(22), isLastInGroup: true),
              
              // Integrity
              _buildHeaderCell('Noise', width: getW(23)),
              _buildHeaderCell('Pulse', width: getW(24)),
              _buildHeaderCell('Period', width: getW(25)),
              _buildHeaderCell('Dbl Sw', width: getW(26), isLastInGroup: true),

              // Power
              _buildHeaderCell('Static', width: getW(27)),
              _buildHeaderCell('Dynamic', width: getW(28)),
              _buildHeaderCell('Pwr', width: getW(29)),
              _buildHeaderCell('Sig', width: getW(30), isLastInGroup: true),

              // PV
              _buildHeaderCell('Base', width: getW(31)),
              _buildHeaderCell('Metal', width: getW(32)),
              _buildHeaderCell('Antenna', width: getW(33), isLastInGroup: true),

              // Signoff
              _buildHeaderCell('LVS', width: getW(34)),
              _buildHeaderCell('ERC', width: getW(35)),
              _buildHeaderCell('R2G', width: getW(36)),
              _buildHeaderCell('G2G', width: getW(37), isLastInGroup: true),

              // Physicals
              _buildHeaderCell('Area', width: getW(38)),
              _buildHeaderCell('Inst', width: getW(39)),
              _buildHeaderCell('Util', width: getW(40), isLastInGroup: true),

              // Logs
              _buildHeaderCell('Err', width: getW(41)),
              _buildHeaderCell('War', width: getW(42)),
              _buildHeaderCell('Crit', width: getW(43), isLastInGroup: true),

              _buildHeaderCell('Summary', width: getW(44), isLastInGroup: true),
              
              // Resources
              _buildHeaderCell('Mem', width: getW(45)),
              _buildHeaderCell('Time', width: getW(46)),
              ],
            ),
          ],
        ),
    );
  }

  Widget _buildHeaderCell(String text, {
    required double width,
    bool isMain = false,
    bool isLastInGroup = false,
    Color? color,
  }) {
    return Container(
      width: width,
      height: isMain ? 40 : 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? Colors.transparent,
            border: Border(
          right: BorderSide(
            color: isLastInGroup || isMain ? const Color(0xFFCBD5E1) : const Color(0xFFE2E8F0),
            width: isLastInGroup ? 1.5 : 1.0,
          ),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: isMain ? 11 : 10,
          fontWeight: isMain ? FontWeight.w800 : FontWeight.w600,
          color: isMain ? const Color(0xFF334155) : const Color(0xFF64748B),
          letterSpacing: 0.5,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Map<int, TableColumnWidth> _buildColumnWidths() {
    final widths = <int, TableColumnWidth>{};
    // Stage (0)
    widths[0] = const FixedColumnWidth(160);
    // Status (1)
    widths[1] = const FixedColumnWidth(120); // Wider for better pill

    // 2-4: Internal
    widths[2] = const FixedColumnWidth(80);
    widths[3] = const FixedColumnWidth(80);
    widths[4] = const FixedColumnWidth(60);

    // 5-7: I2R
    widths[5] = const FixedColumnWidth(80);
    widths[6] = const FixedColumnWidth(80);
    widths[7] = const FixedColumnWidth(60);

    // 8-10: R2O
    widths[8] = const FixedColumnWidth(80);
    widths[9] = const FixedColumnWidth(80);
    widths[10] = const FixedColumnWidth(60);

    // 11-13: I2O
    widths[11] = const FixedColumnWidth(80);
    widths[12] = const FixedColumnWidth(80);
    widths[13] = const FixedColumnWidth(60);

    // 14-16: Hold
    widths[14] = const FixedColumnWidth(80);
    widths[15] = const FixedColumnWidth(80);
    widths[16] = const FixedColumnWidth(60);
    
    // 17-22: Constraints
    for (int i = 17; i <= 22; i++) widths[i] = const FixedColumnWidth(70);
    
    // 23-26: Integrity
    for (int i = 23; i <= 26; i++) widths[i] = const FixedColumnWidth(70);
    
    // 27-30: Power
    for (int i = 27; i <= 30; i++) widths[i] = const FixedColumnWidth(70);
    
    // 31-33: PV
    for (int i = 31; i <= 33; i++) widths[i] = const FixedColumnWidth(70);
    
    // 34-37: Signoff
    for (int i = 34; i <= 37; i++) widths[i] = const FixedColumnWidth(70);
    
    // 38-40: Physicals
    widths[38] = const FixedColumnWidth(80);
    widths[39] = const FixedColumnWidth(80);
    widths[40] = const FixedColumnWidth(70);

    // 41-43: Logs
    widths[41] = const FixedColumnWidth(50);
    widths[42] = const FixedColumnWidth(50);
    widths[43] = const FixedColumnWidth(50);

    // 44: AI
    widths[44] = const FixedColumnWidth(150);

    // 45-46: Resources
    widths[45] = const FixedColumnWidth(80);
    widths[46] = const FixedColumnWidth(80);

    return widths;
  }

  Widget _buildStatusCell(String? status) {
    String s = (status ?? 'unknown').toLowerCase();
    
    Color color;
    Color bg;
    IconData icon;
    String label;

    switch (s) {
      case 'success':
        color = const Color(0xFF16A34A);
        bg = const Color(0xFFDCFCE7);
        icon = Icons.check_circle_outline;
        label = 'SUCCESS';
        break;
      case 'fail':
        color = const Color(0xFFDC2626);
        bg = const Color(0xFFFEF2F2);
        icon = Icons.error_outline;
        label = 'FAILED';
        break;
      case 'continue_with_error':
        color = const Color(0xFFEA580C);
        bg = const Color(0xFFFFF7ED);
        icon = Icons.warning_amber_rounded;
        label = 'ERRORS';
        break;
      default:
        color = const Color(0xFF64748B);
        bg = const Color(0xFFF1F5F9);
        icon = Icons.help_outline;
        label = s.toUpperCase().replaceAll('_', ' ');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            label,
        style: TextStyle(
          color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
        ),
          ),
        ],
      ),
    );
  }

  TableRow _buildTableRow(Map<String, dynamic> s) {
    // Formatting date
    final timestamp = s['timestamp']?.toString() ?? '';
    final timeDisplay = timestamp.length > 5 ? timestamp.replaceAll('T', ' ').substring(0, 16) : timestamp;

    return TableRow(
          decoration: const BoxDecoration(
            color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
          ),
      children: [
        // Stage Name & Time
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                (s['stage']?.toString() ?? '–').toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: Color(0xFF0F172A),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 10, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 4),
              Text(
                    timeDisplay,
                    style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // Status
        Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _buildStatusCell(s['run_status']),
        ),

        // Internal
        _dataCell(s['internal_timing_r2r_wns'], isTiming: true, bg: Colors.blue[50]),
        _dataCell(s['internal_timing_r2r_tns'], isTiming: true, bg: Colors.blue[50]),
        _dataCell(s['internal_timing_r2r_nvp'], bg: Colors.blue[50], borderRight: true),

        // I2R
        _dataCell(s['interface_timing_i2r_wns'], isTiming: true, bg: Colors.indigo[50]),
        _dataCell(s['interface_timing_i2r_tns'], isTiming: true, bg: Colors.indigo[50]),
        _dataCell(s['interface_timing_i2r_nvp'], bg: Colors.indigo[50], borderRight: true),

        // R2O
        _dataCell(s['interface_timing_r2o_wns'], isTiming: true, bg: Colors.purple[50]),
        _dataCell(s['interface_timing_r2o_tns'], isTiming: true, bg: Colors.purple[50]),
        _dataCell(s['interface_timing_r2o_nvp'], bg: Colors.purple[50], borderRight: true),

        // I2O
        _dataCell(s['interface_timing_i2o_wns'], isTiming: true, bg: Colors.indigo[50]),
        _dataCell(s['interface_timing_i2o_tns'], isTiming: true, bg: Colors.indigo[50]),
        _dataCell(s['interface_timing_i2o_nvp'], bg: Colors.indigo[50], borderRight: true),

        // Hold
        _dataCell(s['hold_wns'], isTiming: true),
        _dataCell(s['hold_tns'], isTiming: true),
        _dataCell(s['hold_nvp'], borderRight: true),

        // Constraints
        _dataCell(s['max_tran_wns'], isTiming: true, bg: Colors.orange[50]),
        _dataCell(s['max_tran_nvp'], bg: Colors.orange[50]),
        _dataCell(s['max_cap_wns'], isTiming: true, bg: Colors.orange[50]),
        _dataCell(s['max_cap_nvp'], bg: Colors.orange[50]),
        _dataCell(s['max_fanout_wns'], isTiming: true, bg: Colors.orange[50]),
        _dataCell(s['max_fanout_nvp'], bg: Colors.orange[50], borderRight: true),

        // Integrity
        _dataCell(s['noise_violations']),
        _dataCell(s['min_pulse_width']),
        _dataCell(s['min_period']),
        _dataCell(s['double_switching'], borderRight: true),

        // Power
        _dataCell(s['ir_static']),
        _dataCell(s['ir_dynamic']),
        _dataCell(s['em_power']),
        _dataCell(s['em_signal'], borderRight: true),

        // PV
        _dataCell(s['pv_drc_base']),
        _dataCell(s['pv_drc_metal']),
        _dataCell(s['pv_drc_antenna'], borderRight: true),

        // Signoff
        _dataCell(s['lvs']),
        _dataCell(s['erc']),
        _dataCell(s['r2g_lec']),
        _dataCell(s['g2g_lec'], borderRight: true),

        // Physicals
        _dataCell(s['area']),
        _dataCell(s['inst_count']),
        _dataCell(s['utilization'], borderRight: true),

        // Logs
        _dataCell(s['log_errors'], textColor: Colors.red[700], isBold: true),
        _dataCell(s['log_warnings'], textColor: Colors.amber[700], isBold: true),
        _dataCell(s['log_critical'], textColor: Colors.red[900], isBold: true, borderRight: true),

        // AI Summary
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          alignment: Alignment.centerLeft,
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Text(
            s['ai_summary']?.toString() ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
          ),
        ),

        // Resources
        _dataCell(s['memory_usage']),
        _dataCell(s['runtime']),
      ],
    );
  }

  Widget _dataCell(
    dynamic value, {
    bool isTiming = false,
    Color? bg,
    bool borderRight = false,
    Color? textColor,
    bool isBold = false,
  }) {
    // Parsing logic
    String display = '—';
    Color? finalTextColor = textColor ?? const Color(0xFF334155);
    FontWeight fontWeight = isBold ? FontWeight.w700 : FontWeight.w400;

    if (value != null && value.toString().isNotEmpty && value.toString() != 'N/A' && value.toString() != 'NA') {
      if (isTiming && value is num) {
        display = value.toStringAsFixed(3);
        if (value < -0.0001) {
          finalTextColor = const Color(0xFFDC2626); // Red for violations
          fontWeight = FontWeight.w700;
        } else if (value >= 0) {
          finalTextColor = const Color(0xFF059669); // Green for safe
        }
      } else if (value is num) {
        display = value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(2);
      } else {
        display = value.toString();
      }
    } else {
      finalTextColor = const Color(0xFFCBD5E1); // Light grey for empty
    }

    return Container(
      height: 48, // Fixed height for rows
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg?.withOpacity(0.3) ?? Colors.transparent,
        border: Border(
          right: borderRight ? const BorderSide(color: Color(0xFF94A3B8), width: 0.5) : const BorderSide(color: Color(0xFFF1F5F9)),
        ),
      ),
      child: Text(
        display,
        style: TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          color: finalTextColor,
          fontWeight: fontWeight,
        ),
      ),
    );
  }

  void _showFullScreenTable(List<Map<String, dynamic>> stages) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text(
              'Stage Metrics Comparison - Full Screen',
              style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF0F172A),
            elevation: 1,
          ),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLegend(),
                const SizedBox(height: 24),
                Expanded(
                  child: _ScrollControllerProvider(
                    builder: (h, v) => _buildTableLayout(stages, h, v),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTableLayout(
    List<Map<String, dynamic>> stages,
    ScrollController hCtrl,
    ScrollController vCtrl, {
    double? fixedHeight,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidths = _buildColumnWidths();
        double totalWidth = 0;
        for (var width in columnWidths.values) {
          if (width is FixedColumnWidth) {
            totalWidth += width.value;
          }
        }
        final minTableWidth = totalWidth;
        final maxWidth = constraints.maxWidth > 0 && constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : minTableWidth;

        Widget content = Scrollbar(
          controller: hCtrl,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 8,
          child: SingleChildScrollView(
            controller: hCtrl,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalWidth < maxWidth ? maxWidth : totalWidth,
              child: Column(
                children: [
                  _buildUnifiedHeader(columnWidths),
                  Expanded(
                    child: Scrollbar(
                      controller: vCtrl,
                      thumbVisibility: true,
                      thickness: 8,
                      child: SingleChildScrollView(
                        controller: vCtrl,
                        child: Table(
                          columnWidths: columnWidths,
                          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                          border: const TableBorder(
                            horizontalInside: BorderSide(color: Color(0xFFF1F5F9)),
                          ),
                          children: stages.map((s) => _buildTableRow(s)).toList(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        if (fixedHeight != null) {
          return SizedBox(height: fixedHeight, child: content);
        }
        return content;
      },
    );
  }

  // Lead View - Filtered table with specific columns
  Widget _buildLeadView(List<Map<String, dynamic>> stages) {
    if (_selectedProject == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            'Please select a project to view lead dashboard',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }

    // Get all stages for the selected project/block
    final allProjectStages = _selectedBlock != null 
        ? _getAllStagesForBlock() 
        : _getAllStagesForProject();
    
    // Get milestone progress and block summary
    final milestoneProgress = _getMilestoneProgress(allProjectStages);
    final blockSummary = _getBlockStagesSummary(allProjectStages);
    final blockHealth = allProjectStages.isNotEmpty 
        ? _calculateBlockHealthIndex(allProjectStages) 
        : 0.0;

    return Column(
      children: [
        // Summary cards row
        Row(
          children: [
            Expanded(
              child: _buildLeadCard(
                'Milestone Progress',
                _buildMilestoneProgress(milestoneProgress),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _buildLeadCard(
                'Block Stages Summary',
                _buildBlockStagesSummary(blockSummary),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _buildLeadCard(
                'Block Health',
                _buildBlockHealthCard(blockHealth),
              ),
            ),
          ],
        ),
        if (stages.isNotEmpty) ...[
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                    border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.table_chart_outlined, size: 20, color: Color(0xFF0F172A)),
                      SizedBox(width: 12),
                      Text(
                        'Lead View - Stage Metrics Comparison',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildLeadTable(stages),
              ],
            ),
          ),
        ],
      ],
    );
  }
  
  Widget _buildLeadCard(String title, Widget content) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF94A3B8),
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 16),
          content,
        ],
      ),
    );
  }
  
  // Get all stages for the selected block
  List<Map<String, dynamic>> _getAllStagesForBlock() {
    if (_selectedProject == null || _selectedBlock == null) return [];
    
    final allStages = <Map<String, dynamic>>[];
    
    try {
      final projectValue = _groupedData[_selectedProject];
      if (projectValue is! Map) return [];
      
      final projectData = Map<String, dynamic>.from(projectValue);
      final blockValue = projectData[_selectedBlock];
      if (blockValue is! Map) return [];
      
      final blockData = Map<String, dynamic>.from(blockValue);
      
      // Iterate through all RTL tags
      for (var rtlTag in blockData.keys) {
        final tagValue = blockData[rtlTag];
        if (tagValue is! Map) continue;
        
        final tagData = Map<String, dynamic>.from(tagValue);
        
        // Iterate through all experiments
        for (var experiment in tagData.keys) {
          final expValue = tagData[experiment];
          if (expValue is! Map) continue;
          
          final expData = Map<String, dynamic>.from(expValue);
          final stages = expData['stages'];
          if (stages is! Map) continue;
          
          final stagesMap = Map<String, dynamic>.from(stages);
          
          // Add all stages from this experiment
          for (var stageData in stagesMap.values) {
            if (stageData is Map<String, dynamic>) {
              final stageWithContext = Map<String, dynamic>.from(stageData);
              stageWithContext['block_name'] = _selectedBlock;
              stageWithContext['rtl_tag'] = rtlTag;
              stageWithContext['experiment'] = experiment;
              allStages.add(stageWithContext);
            } else if (stageData is Map) {
              final stageWithContext = Map<String, dynamic>.from(stageData);
              stageWithContext['block_name'] = _selectedBlock;
              stageWithContext['rtl_tag'] = rtlTag;
              stageWithContext['experiment'] = experiment;
              allStages.add(stageWithContext);
            }
          }
        }
      }
    } catch (e) {
      print('Error getting all stages for block: $e');
    }
    
    return allStages;
  }
  
  // Get milestone progress
  Map<String, dynamic> _getMilestoneProgress(List<Map<String, dynamic>> stages) {
    final stageOrder = ['syn', 'init', 'floorplan', 'place', 'cts', 'postcts', 'route', 'postroute'];
    final milestoneData = <String, Map<String, dynamic>>{};
    
    // Initialize all milestones
    for (var stage in stageOrder) {
      milestoneData[stage] = {
        'stage': stage,
        'completed': 0,
        'pending': 0,
        'failed': 0,
        'in_progress': 0,
      };
    }
    
    // Count statuses for each stage
    for (var stageData in stages) {
      final stageName = stageData['stage']?.toString().toLowerCase() ?? '';
      final status = stageData['run_status']?.toString().toLowerCase() ?? 'unknown';
      
      if (milestoneData.containsKey(stageName)) {
        if (status == 'pass' || status == 'completed') {
          milestoneData[stageName]!['completed'] = (milestoneData[stageName]!['completed'] as int) + 1;
        } else if (status == 'fail' || status == 'failed') {
          milestoneData[stageName]!['failed'] = (milestoneData[stageName]!['failed'] as int) + 1;
        } else if (status == 'continue_with_error' || status == 'in_progress') {
          milestoneData[stageName]!['in_progress'] = (milestoneData[stageName]!['in_progress'] as int) + 1;
        } else {
          milestoneData[stageName]!['pending'] = (milestoneData[stageName]!['pending'] as int) + 1;
        }
      }
    }
    
    // Calculate totals
    int totalCompleted = 0;
    int totalPending = 0;
    int totalFailed = 0;
    int totalInProgress = 0;
    
    for (var data in milestoneData.values) {
      totalCompleted += data['completed'] as int;
      totalPending += data['pending'] as int;
      totalFailed += data['failed'] as int;
      totalInProgress += data['in_progress'] as int;
    }
    
    return {
      'milestones': milestoneData,
      'total': {
        'completed': totalCompleted,
        'pending': totalPending,
        'failed': totalFailed,
        'in_progress': totalInProgress,
        'total': totalCompleted + totalPending + totalFailed + totalInProgress,
      },
    };
  }
  
  // Get block stages summary
  Map<String, dynamic> _getBlockStagesSummary(List<Map<String, dynamic>> stages) {
    final blockStages = <String, Set<String>>{};
    final blockStatuses = <String, Map<String, int>>{};
    
    for (var stageData in stages) {
      final blockName = stageData['block_name']?.toString() ?? 'Unknown';
      final stageName = stageData['stage']?.toString() ?? 'Unknown';
      final status = stageData['run_status']?.toString().toLowerCase() ?? 'unknown';
      
      if (!blockStages.containsKey(blockName)) {
        blockStages[blockName] = <String>{};
        blockStatuses[blockName] = {
          'pass': 0,
          'fail': 0,
          'continue_with_error': 0,
          'unknown': 0,
        };
      }
      
      blockStages[blockName]!.add(stageName);
      
      if (status == 'pass' || status == 'completed') {
        blockStatuses[blockName]!['pass'] = (blockStatuses[blockName]!['pass'] ?? 0) + 1;
      } else if (status == 'fail' || status == 'failed') {
        blockStatuses[blockName]!['fail'] = (blockStatuses[blockName]!['fail'] ?? 0) + 1;
      } else if (status == 'continue_with_error') {
        blockStatuses[blockName]!['continue_with_error'] = (blockStatuses[blockName]!['continue_with_error'] ?? 0) + 1;
      } else {
        blockStatuses[blockName]!['unknown'] = (blockStatuses[blockName]!['unknown'] ?? 0) + 1;
      }
    }
    
    return {
      'blocks': blockStages.map((key, value) => MapEntry(key, {
        'stages': value.toList(),
        'stageCount': value.length,
        'statuses': blockStatuses[key] ?? {},
      })),
      'totalBlocks': blockStages.length,
    };
  }
  
  Widget _buildMilestoneProgress(Map<String, dynamic> progressData) {
    final milestones = progressData['milestones'] as Map<String, dynamic>;
    final total = progressData['total'] as Map<String, dynamic>;
    final totalCount = total['total'] as int;
    
    if (totalCount == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No milestone data available',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    
    final completedPercent = totalCount > 0 
        ? ((total['completed'] as int) / totalCount * 100).round()
        : 0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Overall progress
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildStatusIndicator('Completed', total['completed'] as int, const Color(0xFF10B981)),
            _buildStatusIndicator('In Progress', total['in_progress'] as int, const Color(0xFFF59E0B)),
            _buildStatusIndicator('Failed', total['failed'] as int, const Color(0xFFDC2626)),
            _buildStatusIndicator('Pending', total['pending'] as int, const Color(0xFF94A3B8)),
          ],
        ),
        const SizedBox(height: 16),
        // Progress bar
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Overall Progress',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  '$completedPercent%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: completedPercent / 100,
                minHeight: 8,
                backgroundColor: const Color(0xFFE2E8F0),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Milestone breakdown
        ...milestones.values.take(5).map((milestone) {
          final stage = milestone['stage'] as String;
          final completed = milestone['completed'] as int;
          final milestoneTotal = (milestone['completed'] as int) + 
                       (milestone['pending'] as int) + 
                       (milestone['failed'] as int) + 
                       (milestone['in_progress'] as int);
          final percent = milestoneTotal > 0 ? (completed / milestoneTotal * 100).round() : 0;
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    stage.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: milestoneTotal > 0 ? completed / milestoneTotal : 0,
                      minHeight: 6,
                      backgroundColor: const Color(0xFFE2E8F0),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$percent%',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
  
  Widget _buildStatusIndicator(String label, int count, Color color) {
    return Column(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
  
  Widget _buildBlockStagesSummary(Map<String, dynamic> summary) {
    final blocks = summary['blocks'] as Map<String, dynamic>;
    final totalBlocks = summary['totalBlocks'] as int;
    
    if (totalBlocks == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No block data available',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Total Blocks: $totalBlocks',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 16),
        ...blocks.entries.take(5).map((entry) {
          final blockName = entry.key;
          final data = entry.value as Map<String, dynamic>;
          final stageCount = data['stageCount'] as int;
          final statuses = data['statuses'] as Map<String, int>;
          final passCount = statuses['pass'] ?? 0;
          final failCount = statuses['fail'] ?? 0;
          final errorCount = statuses['continue_with_error'] ?? 0;
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        blockName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        '$stageCount stages',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (passCount > 0)
                        _buildStatusBadge('Pass', passCount, const Color(0xFF10B981)),
                      if (failCount > 0) ...[
                        const SizedBox(width: 8),
                        _buildStatusBadge('Fail', failCount, const Color(0xFFDC2626)),
                      ],
                      if (errorCount > 0) ...[
                        const SizedBox(width: 8),
                        _buildStatusBadge('Error', errorCount, const Color(0xFFF59E0B)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }
  
  Widget _buildStatusBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$label: $count',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildBlockHealthCard(double healthIndex) {
    Color color;
    String status;
    if (healthIndex >= 80) {
      color = const Color(0xFF10B981);
      status = 'Excellent';
    } else if (healthIndex >= 60) {
      color = const Color(0xFFF59E0B);
      status = 'Good';
    } else if (healthIndex >= 40) {
      color = const Color(0xFFF97316);
      status = 'Fair';
    } else {
      color = const Color(0xFFDC2626);
      status = 'Poor';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              healthIndex.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: healthIndex / 100,
            minHeight: 12,
            backgroundColor: const Color(0xFFE2E8F0),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Health Index',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildLeadTable(List<Map<String, dynamic>> stages) {
    final columnWidths = <int, TableColumnWidth>{
      0: const FixedColumnWidth(120), // Stage
      1: const FixedColumnWidth(100), // Status
      2: const FixedColumnWidth(80), // Internal WNS
      3: const FixedColumnWidth(80), // Internal TNS
      4: const FixedColumnWidth(60), // Internal NVP
      5: const FixedColumnWidth(80), // I2R WNS
      6: const FixedColumnWidth(80), // I2R TNS
      7: const FixedColumnWidth(60), // I2R NVP
      8: const FixedColumnWidth(80), // R2O WNS
      9: const FixedColumnWidth(80), // R2O TNS
      10: const FixedColumnWidth(60), // R2O NVP
      11: const FixedColumnWidth(80), // I2O WNS
      12: const FixedColumnWidth(80), // I2O TNS
      13: const FixedColumnWidth(60), // I2O NVP
      14: const FixedColumnWidth(70), // Max Tran WNS
      15: const FixedColumnWidth(70), // Max Tran NVP
      16: const FixedColumnWidth(70), // Max Cap WNS
      17: const FixedColumnWidth(70), // Max Cap NVP
      18: const FixedColumnWidth(80), // Noise
      19: const FixedColumnWidth(80), // Congestion/DRC
      20: const FixedColumnWidth(80), // Area
      21: const FixedColumnWidth(80), // Inst Count
      22: const FixedColumnWidth(70), // Utilization
      23: const FixedColumnWidth(50), // Log Errors
      24: const FixedColumnWidth(50), // Log Warnings
      25: const FixedColumnWidth(100), // Run Status
      26: const FixedColumnWidth(80), // Runtime
      27: const FixedColumnWidth(200), // AI Summary
      28: const FixedColumnWidth(80), // IR Static
      29: const FixedColumnWidth(80), // IR Dynamic
      30: const FixedColumnWidth(80), // EM Power
      31: const FixedColumnWidth(80), // EM Signal
      32: const FixedColumnWidth(70), // PV Base
      33: const FixedColumnWidth(70), // PV Metal
      34: const FixedColumnWidth(70), // PV Antenna
      35: const FixedColumnWidth(70), // LVS
      36: const FixedColumnWidth(70), // LEC R2G
      37: const FixedColumnWidth(70), // LEC G2G
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        double totalWidth = 0;
        for (var width in columnWidths.values) {
          if (width is FixedColumnWidth) {
            totalWidth += width.value;
          }
        }

        return SizedBox(
          height: 600,
          child: Scrollbar(
            controller: _horizontalScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth,
                child: Column(
                  children: [
                    _buildLeadHeader(columnWidths),
                    Expanded(
                      child: Scrollbar(
                        controller: _verticalScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _verticalScrollController,
                          child: Table(
                            columnWidths: columnWidths,
                            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                            border: const TableBorder(
                              horizontalInside: BorderSide(color: Color(0xFFF1F5F9)),
                            ),
                            children: stages.map((s) => _buildLeadTableRow(s)).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLeadHeader(Map<int, TableColumnWidth> colWidths) {
    double getW(int idx) => (colWidths[idx] as FixedColumnWidth).value;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        children: [
          // LEVEL 1: Group Headers
          Row(
            children: [
              _buildHeaderCell('STAGE INFO', width: getW(0) + getW(1), isMain: true),
              _buildHeaderCell('INTERNAL (R2R)', width: getW(2) + getW(3) + getW(4), isMain: true, color: Colors.blue[50]),
              _buildHeaderCell('INTERFACE I2R', width: getW(5) + getW(6) + getW(7), isMain: true, color: Colors.indigo[50]),
              _buildHeaderCell('INTERFACE R2O', width: getW(8) + getW(9) + getW(10), isMain: true, color: Colors.purple[50]),
              _buildHeaderCell('INTERFACE I2O', width: getW(11) + getW(12) + getW(13), isMain: true, color: Colors.indigo[50]),
              _buildHeaderCell('CONSTRAINTS', width: getW(14) + getW(15) + getW(16) + getW(17), isMain: true, color: Colors.orange[50]),
              _buildHeaderCell('INTEGRITY', width: getW(18) + getW(19), isMain: true),
              _buildHeaderCell('PHYSICAL STATS', width: getW(20) + getW(21) + getW(22), isMain: true),
              _buildHeaderCell('LOGS', width: getW(23) + getW(24), isMain: true),
              _buildHeaderCell('RUN STATUS', width: getW(25), isMain: true),
              _buildHeaderCell('RUNTIME', width: getW(26), isMain: true),
              _buildHeaderCell('AI SUMMARY', width: getW(27), isMain: true),
              _buildHeaderCell('POWER / IR', width: getW(28) + getW(29), isMain: true),
              _buildHeaderCell('EM', width: getW(30) + getW(31), isMain: true),
              _buildHeaderCell('PHYSICAL VERIF', width: getW(32) + getW(33) + getW(34), isMain: true),
              _buildHeaderCell('SIGNOFF', width: getW(35) + getW(36) + getW(37), isMain: true),
            ],
          ),
          Divider(height: 1, color: Colors.grey.withOpacity(0.2)),
          // LEVEL 2: Specific Metric Headers
          Row(
            children: [
              _buildHeaderCell('Stage', width: getW(0)),
              _buildHeaderCell('Status', width: getW(1)),
              // Internal
              _buildHeaderCell('WNS', width: getW(2)),
              _buildHeaderCell('TNS', width: getW(3)),
              _buildHeaderCell('NVP', width: getW(4), isLastInGroup: true),
              // I2R
              _buildHeaderCell('WNS', width: getW(5)),
              _buildHeaderCell('TNS', width: getW(6)),
              _buildHeaderCell('NVP', width: getW(7), isLastInGroup: true),
              // R2O
              _buildHeaderCell('WNS', width: getW(8)),
              _buildHeaderCell('TNS', width: getW(9)),
              _buildHeaderCell('NVP', width: getW(10), isLastInGroup: true),
              // I2O
              _buildHeaderCell('WNS', width: getW(11)),
              _buildHeaderCell('TNS', width: getW(12)),
              _buildHeaderCell('NVP', width: getW(13), isLastInGroup: true),
              // Constraints
              _buildHeaderCell('Tran WNS', width: getW(14)),
              _buildHeaderCell('Tran NVP', width: getW(15)),
              _buildHeaderCell('Cap WNS', width: getW(16)),
              _buildHeaderCell('Cap NVP', width: getW(17), isLastInGroup: true),
              // Integrity
              _buildHeaderCell('Noise', width: getW(18)),
              _buildHeaderCell('Congestion/DRC', width: getW(19), isLastInGroup: true),
              // Physical Stats
              _buildHeaderCell('Area', width: getW(20)),
              _buildHeaderCell('Inst Count', width: getW(21)),
              _buildHeaderCell('Utilization', width: getW(22), isLastInGroup: true),
              // Logs
              _buildHeaderCell('Errors', width: getW(23)),
              _buildHeaderCell('Warnings', width: getW(24), isLastInGroup: true),
              // Run Status
              _buildHeaderCell('Status', width: getW(25), isLastInGroup: true),
              // Runtime
              _buildHeaderCell('Runtime', width: getW(26), isLastInGroup: true),
              // AI Summary
              _buildHeaderCell('Summary', width: getW(27), isLastInGroup: true),
              // Power/IR
              _buildHeaderCell('IR Static', width: getW(28)),
              _buildHeaderCell('IR Dynamic', width: getW(29), isLastInGroup: true),
              // EM
              _buildHeaderCell('EM Power', width: getW(30)),
              _buildHeaderCell('EM Signal', width: getW(31), isLastInGroup: true),
              // PV
              _buildHeaderCell('PV Base', width: getW(32)),
              _buildHeaderCell('PV Metal', width: getW(33)),
              _buildHeaderCell('PV Antenna', width: getW(34), isLastInGroup: true),
              // Signoff
              _buildHeaderCell('LVS', width: getW(35)),
              _buildHeaderCell('LEC R2G', width: getW(36)),
              _buildHeaderCell('LEC G2G', width: getW(37)),
            ],
          ),
        ],
      ),
    );
  }

  TableRow _buildLeadTableRow(Map<String, dynamic> s) {
    return TableRow(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Text(
            (s['stage']?.toString() ?? '–').toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _buildStatusCell(s['run_status']),
        ),
        _dataCell(s['internal_timing_r2r_wns'], isTiming: true),
        _dataCell(s['internal_timing_r2r_tns'], isTiming: true),
        _dataCell(s['internal_timing_r2r_nvp']),
        _dataCell(s['interface_timing_i2r_wns'], isTiming: true),
        _dataCell(s['interface_timing_i2r_tns'], isTiming: true),
        _dataCell(s['interface_timing_i2r_nvp']),
        _dataCell(s['interface_timing_r2o_wns'], isTiming: true),
        _dataCell(s['interface_timing_r2o_tns'], isTiming: true),
        _dataCell(s['interface_timing_r2o_nvp']),
        _dataCell(s['interface_timing_i2o_wns'], isTiming: true),
        _dataCell(s['interface_timing_i2o_tns'], isTiming: true),
        _dataCell(s['interface_timing_i2o_nvp']),
        _dataCell(s['max_tran_wns'], isTiming: true),
        _dataCell(s['max_tran_nvp']),
        _dataCell(s['max_cap_wns'], isTiming: true),
        _dataCell(s['max_cap_nvp']),
        _dataCell(s['noise_violations']),
        _dataCell(s['drc_violations']),
        _dataCell(s['area']),
        _dataCell(s['inst_count']),
        _dataCell(s['utilization']),
        _dataCell(s['log_errors'], textColor: Colors.red[700], isBold: true),
        _dataCell(s['log_warnings'], textColor: Colors.amber[700], isBold: true),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          child: _buildStatusCell(s['run_status']),
        ),
        _dataCell(s['runtime']),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(
            s['ai_summary']?.toString() ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
          ),
        ),
        _dataCell(s['ir_static']),
        _dataCell(s['ir_dynamic']),
        _dataCell(s['em_power']),
        _dataCell(s['em_signal']),
        _dataCell(s['pv_drc_base']),
        _dataCell(s['pv_drc_metal']),
        _dataCell(s['pv_drc_antenna']),
        _dataCell(s['lvs']),
        _dataCell(s['r2g_lec']),
        _dataCell(s['g2g_lec']),
      ],
    );
  }

  // Manager View - High-level overview
  Widget _buildManagerView() {
    if (_selectedProject == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            'Please select a project to view manager dashboard',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }

    // Get all stages for the selected project (across all blocks)
    final allProjectStages = _getAllStagesForProject();
    
    // Get block statuses and critical blocks for the selected project
    final blockStatuses = _getBlockStatusesForProject();
    final criticalBlocks = _getCriticalBlocksForProject();

    // Get current stage (most recent from all project stages)
    // Sort by timestamp to find the most recent
    final sortedStages = List<Map<String, dynamic>>.from(allProjectStages);
    sortedStages.sort((a, b) {
      final aTime = a['timestamp']?.toString() ?? '';
      final bTime = b['timestamp']?.toString() ?? '';
      if (aTime.isEmpty && bTime.isEmpty) return 0;
      if (aTime.isEmpty) return 1;
      if (bTime.isEmpty) return -1;
      try {
        final aDate = DateTime.parse(aTime);
        final bDate = DateTime.parse(bTime);
        return bDate.compareTo(aDate); // Descending order (most recent first)
      } catch (e) {
        return 0;
      }
    });
    
    final currentStage = sortedStages.isNotEmpty ? sortedStages.first : null;
    final healthIndex = allProjectStages.isNotEmpty 
        ? _calculateBlockHealthIndex(allProjectStages) 
        : 0.0;

    return Column(
      children: [
        // Charts row
        Row(
          children: [
            Expanded(
              child: _buildManagerCard(
                'Block Status Histogram',
                _buildBlockStatusHistogram(blockStatuses),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _buildManagerCard(
                'Critical Blocks',
                _buildCriticalBlocksChart(criticalBlocks),
              ),
            ),
          ],
        ),
        if (allProjectStages.isNotEmpty && currentStage != null) ...[
          const SizedBox(height: 24),
          _buildManagerCard('Current Stage', _buildCurrentStageCard(currentStage)),
          const SizedBox(height: 24),
          _buildManagerCard('Block Health Index', _buildHealthIndexCard(healthIndex)),
          const SizedBox(height: 24),
          _buildManagerCard('Brief Summary', _buildBriefSummaryCard(currentStage)),
        ] else if (allProjectStages.isEmpty) ...[
          const SizedBox(height: 24),
          _buildManagerCard(
            'Current Stage',
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Text(
                  'No stage data available for the selected project',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildManagerCard('Block Health Index', _buildHealthIndexCard(0.0)),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: _buildManagerCard('Open Tickets', _buildTicketsCard())),
            const SizedBox(width: 24),
            Expanded(child: _buildManagerCard('Milestone Status', _buildMilestoneCard())),
            const SizedBox(width: 24),
            Expanded(child: _buildManagerCard('QMS Status', _buildQMSStatusCard())),
          ],
        ),
      ],
    );
  }
  
  // Get all stages from all blocks in the selected project
  List<Map<String, dynamic>> _getAllStagesForProject() {
    if (_selectedProject == null || _selectedDomain == null) return [];
    
    final allStages = <Map<String, dynamic>>[];
    
    try {
      final projectValue = _groupedData[_selectedProject];
      if (projectValue is! Map) return [];
      
      final projectData = Map<String, dynamic>.from(projectValue);
      
      // Iterate through all blocks
      for (var blockName in projectData.keys) {
        final blockValue = projectData[blockName];
        if (blockValue is! Map) continue;
        
        final blockData = Map<String, dynamic>.from(blockValue);
        
        // Iterate through all RTL tags
        for (var rtlTag in blockData.keys) {
          final tagValue = blockData[rtlTag];
          if (tagValue is! Map) continue;
          
          final tagData = Map<String, dynamic>.from(tagValue);
          
          // Iterate through all experiments
          for (var experiment in tagData.keys) {
            final expValue = tagData[experiment];
            if (expValue is! Map) continue;
            
            final expData = Map<String, dynamic>.from(expValue);
            final stages = expData['stages'];
            if (stages is! Map) continue;
            
            final stagesMap = Map<String, dynamic>.from(stages);
            
            // Add all stages from this experiment
            for (var stageData in stagesMap.values) {
              if (stageData is Map<String, dynamic>) {
                // Add block info to stage data for context
                final stageWithContext = Map<String, dynamic>.from(stageData);
                stageWithContext['block_name'] = blockName;
                stageWithContext['rtl_tag'] = rtlTag;
                stageWithContext['experiment'] = experiment;
                allStages.add(stageWithContext);
              } else if (stageData is Map) {
                final stageWithContext = Map<String, dynamic>.from(stageData);
                stageWithContext['block_name'] = blockName;
                stageWithContext['rtl_tag'] = rtlTag;
                stageWithContext['experiment'] = experiment;
                allStages.add(stageWithContext);
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error getting all stages for project: $e');
    }
    
    return allStages;
  }
  
  // Get block statuses for the selected project
  Map<String, String> _getBlockStatusesForProject() {
    final blockStatuses = <String, String>{};
    
    if (_selectedProject == null) return blockStatuses;
    
    try {
      final projectValue = _groupedData[_selectedProject];
      if (projectValue is! Map) return blockStatuses;
      
      final projectData = Map<String, dynamic>.from(projectValue);
      
      // Iterate through all blocks
      for (var blockName in projectData.keys) {
        final blockValue = projectData[blockName];
        if (blockValue is! Map) continue;
        
        final blockData = Map<String, dynamic>.from(blockValue);
        String latestStatus = 'unknown';
        DateTime? latestTimestamp;
        
        // Find the latest stage status for this block
        for (var rtlTag in blockData.keys) {
          final tagValue = blockData[rtlTag];
          if (tagValue is! Map) continue;
          
          final tagData = Map<String, dynamic>.from(tagValue);
          for (var experiment in tagData.keys) {
            final expValue = tagData[experiment];
            if (expValue is! Map) continue;
            
            final expData = Map<String, dynamic>.from(expValue);
            final stages = expData['stages'];
            if (stages is! Map) continue;
            
            final stagesMap = Map<String, dynamic>.from(stages);
            for (var stageData in stagesMap.values) {
              if (stageData is! Map) continue;
              
              final stage = Map<String, dynamic>.from(stageData);
              final status = stage['run_status']?.toString().toLowerCase() ?? 'unknown';
              final timestampStr = stage['timestamp']?.toString() ?? '';
              
              // Parse timestamp if available
              DateTime? timestamp;
              if (timestampStr.isNotEmpty) {
                try {
                  timestamp = DateTime.parse(timestampStr);
                } catch (e) {
                  // Ignore parse errors
                }
              }
              
              // Update if this is the latest
              if (timestamp != null && (latestTimestamp == null || timestamp.isAfter(latestTimestamp))) {
                latestTimestamp = timestamp;
                latestStatus = status;
              } else if (latestTimestamp == null && status != 'unknown') {
                // If no timestamp but has status, use it
                latestStatus = status;
              }
            }
          }
        }
        
        blockStatuses[blockName] = latestStatus;
      }
    } catch (e) {
      print('Error getting block statuses: $e');
    }
    
    return blockStatuses;
  }
  
  // Get critical blocks for the selected project
  List<Map<String, dynamic>> _getCriticalBlocksForProject() {
    final criticalBlocks = <Map<String, dynamic>>[];
    
    if (_selectedProject == null) return criticalBlocks;
    
    try {
      final projectValue = _groupedData[_selectedProject];
      if (projectValue is! Map) return criticalBlocks;
      
      final projectData = Map<String, dynamic>.from(projectValue);
      
      // Iterate through all blocks
      for (var blockName in projectData.keys) {
        final blockValue = projectData[blockName];
        if (blockValue is! Map) continue;
        
        final blockData = Map<String, dynamic>.from(blockValue);
        double maxWns = 0.0;
        int totalErrors = 0;
        int totalWarnings = 0;
        String worstStatus = 'pass';
        int criticalScore = 0;
        
        // Analyze all stages for this block
        for (var rtlTag in blockData.keys) {
          final tagValue = blockData[rtlTag];
          if (tagValue is! Map) continue;
          
          final tagData = Map<String, dynamic>.from(tagValue);
          for (var experiment in tagData.keys) {
            final expValue = tagData[experiment];
            if (expValue is! Map) continue;
            
            final expData = Map<String, dynamic>.from(expValue);
            final stages = expData['stages'];
            if (stages is! Map) continue;
            
            final stagesMap = Map<String, dynamic>.from(stages);
            for (var stageData in stagesMap.values) {
              if (stageData is! Map) continue;
              
              final stage = Map<String, dynamic>.from(stageData);
              
              // Check WNS (negative is bad)
              final wns = _parseNumeric(stage['internal_timing_r2r_wns']);
              if (wns != null && wns < maxWns) {
                maxWns = wns;
              }
              
              // Count errors and warnings
              final errors = _parseNumeric(stage['log_errors']) ?? 0;
              final warnings = _parseNumeric(stage['log_warnings']) ?? 0;
              totalErrors += (errors is int ? errors : errors.toInt()) as int;
              totalWarnings += (warnings is int ? warnings : warnings.toInt()) as int;
              
              // Check status
              final status = stage['run_status']?.toString().toLowerCase() ?? 'pass';
              if (status == 'fail') {
                worstStatus = 'fail';
                criticalScore += 30;
              } else if (status == 'continue_with_error' && worstStatus != 'fail') {
                worstStatus = 'continue_with_error';
                criticalScore += 15;
              }
            }
          }
        }
        
        // Calculate critical score
        if (maxWns < 0) {
          criticalScore += (maxWns.abs() * 10).toInt().clamp(0, 30);
        }
        criticalScore += (totalErrors * 2).clamp(0, 20);
        criticalScore += (totalWarnings * 0.5).toInt().clamp(0, 10);
        
        // Add to critical blocks if score > 0
        if (criticalScore > 0) {
          criticalBlocks.add({
            'block': blockName,
            'score': criticalScore,
            'status': worstStatus,
            'wns': maxWns,
            'errors': totalErrors,
            'warnings': totalWarnings,
          });
        }
      }
      
      // Sort by critical score (highest first)
      criticalBlocks.sort((a, b) => (b['score'] as num).compareTo(a['score'] as num));
    } catch (e) {
      print('Error getting critical blocks: $e');
    }
    
    return criticalBlocks;
  }
  
  Widget _buildBlockStatusHistogram(Map<String, String> blockStatuses) {
    if (blockStatuses.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text('No block data available', style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    
    // Count statuses
    final statusCounts = <String, int>{};
    for (var status in blockStatuses.values) {
      final normalizedStatus = status.toLowerCase();
      statusCounts[normalizedStatus] = (statusCounts[normalizedStatus] ?? 0) + 1;
    }
    
    // Define status order and colors
    final statusOrder = ['pass', 'continue_with_error', 'fail', 'unknown'];
    final statusColors = {
      'pass': const Color(0xFF10B981),
      'continue_with_error': const Color(0xFFF59E0B),
      'fail': const Color(0xFFDC2626),
      'unknown': const Color(0xFF94A3B8),
    };
    final statusLabels = {
      'pass': 'Pass',
      'continue_with_error': 'Warning',
      'fail': 'Fail',
      'unknown': 'Unknown',
    };
    
    // Prepare data for chart
    final barGroups = <BarChartGroupData>[];
    final bottomTitles = <String>[];
    int index = 0;
    
    for (var status in statusOrder) {
      final count = statusCounts[status] ?? 0;
      if (count > 0 || status == 'pass') { // Always show pass even if 0
        barGroups.add(
          BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: count.toDouble(),
                color: statusColors[status] ?? const Color(0xFF94A3B8),
                width: 40,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          ),
        );
        bottomTitles.add(statusLabels[status] ?? status);
        index++;
      }
    }
    
    if (barGroups.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text('No status data available', style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    
    final maxCount = statusCounts.values.isEmpty ? 1 : statusCounts.values.reduce((a, b) => a > b ? a : b);
    
    return SizedBox(
      height: 300,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxCount.toDouble() * 1.2,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipBgColor: Colors.grey[800]!,
              tooltipRoundedRadius: 8,
              tooltipPadding: const EdgeInsets.all(8),
              tooltipMargin: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final status = statusOrder[groupIndex];
                return BarTooltipItem(
                  '${statusLabels[status] ?? status}: ${rod.toY.toInt()}',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx >= 0 && idx < bottomTitles.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        bottomTitles[idx],
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }
                  return const Text('');
                },
                reservedSize: 40,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() == value) {
                    return Text(
                      value.toInt().toString(),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (value) {
              return const FlLine(
                color: Color(0xFFE2E8F0),
                strokeWidth: 1,
              );
            },
          ),
          borderData: FlBorderData(show: false),
          barGroups: barGroups,
        ),
      ),
    );
  }
  
  Widget _buildCriticalBlocksChart(List<Map<String, dynamic>> criticalBlocks) {
    if (criticalBlocks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            'No critical blocks found',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    
    // Take top 10 critical blocks
    final topBlocks = criticalBlocks.take(10).toList();
    final maxScore = criticalBlocks.isNotEmpty 
        ? (criticalBlocks.first['score'] as num).toDouble() 
        : 100.0;
    
    return SizedBox(
      height: 300,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxScore * 1.2,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipBgColor: Colors.grey[800]!,
              tooltipRoundedRadius: 8,
              tooltipPadding: const EdgeInsets.all(8),
              tooltipMargin: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final block = topBlocks[groupIndex];
                final blockName = block['block'] as String;
                final score = block['score'] as num;
                final status = block['status'] as String;
                final wns = block['wns'] as num?;
                final errors = block['errors'] as num;
                
                return BarTooltipItem(
                  '$blockName\nScore: ${score.toInt()}\nStatus: ${status.toUpperCase()}\nWNS: ${wns?.toStringAsFixed(2) ?? "N/A"}\nErrors: ${errors.toInt()}',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx >= 0 && idx < topBlocks.length) {
                    final blockName = topBlocks[idx]['block'] as String;
                    // Truncate long names
                    final displayName = blockName.length > 10 
                        ? '${blockName.substring(0, 10)}...' 
                        : blockName;
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 9,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }
                  return const Text('');
                },
                reservedSize: 60,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() == value) {
                    return Text(
                      value.toInt().toString(),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxScore / 5,
            getDrawingHorizontalLine: (value) {
              return const FlLine(
                color: Color(0xFFE2E8F0),
                strokeWidth: 1,
              );
            },
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(topBlocks.length, (index) {
            final block = topBlocks[index];
            final score = (block['score'] as num).toDouble();
            final status = block['status'] as String;
            
            // Color based on status
            Color barColor;
            if (status == 'fail') {
              barColor = const Color(0xFFDC2626);
            } else if (status == 'continue_with_error') {
              barColor = const Color(0xFFF59E0B);
            } else {
              barColor = const Color(0xFFF59E0B);
            }
            
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: score,
                  color: barColor,
                  width: 30,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildManagerCard(String title, Widget content) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF94A3B8),
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 16),
          content,
        ],
      ),
    );
  }

  Widget _buildCurrentStageCard(Map<String, dynamic> stage) {
    final stageName = stage['stage']?.toString() ?? 'Unknown';
    final status = stage['run_status']?.toString() ?? 'unknown';
    final timestamp = stage['timestamp']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stageName.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  if (timestamp.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 14, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 4),
                        Text(
                          timestamp.length > 16 ? timestamp.substring(0, 16) : timestamp,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            _statusBadge(status),
          ],
        ),
      ],
    );
  }

  double _calculateBlockHealthIndex(List<Map<String, dynamic>> stages) {
    if (stages.isEmpty) return 0.0;

    double totalScore = 100.0;
    int count = 0;

    for (var stage in stages) {
      double stageScore = 100.0;

      // Deduct points for violations
      final wns = _parseNumeric(stage['internal_timing_r2r_wns']);
      if (wns != null && wns < 0) {
        stageScore -= (wns.abs() * 10).clamp(0, 30);
      }

      final errors = _parseNumeric(stage['log_errors']) ?? 0;
      stageScore -= (errors * 2).clamp(0, 20);

      final warnings = _parseNumeric(stage['log_warnings']) ?? 0;
      stageScore -= (warnings * 0.5).clamp(0, 10);

      final status = stage['run_status']?.toString().toLowerCase() ?? '';
      if (status == 'fail') {
        stageScore -= 30;
      } else if (status == 'continue_with_error') {
        stageScore -= 15;
      }

      totalScore += stageScore.clamp(0, 100);
      count++;
    }

    return count > 0 ? (totalScore / count).clamp(0, 100) : 0.0;
  }

  Widget _buildHealthIndexCard(double healthIndex) {
    Color color;
    if (healthIndex >= 80) {
      color = const Color(0xFF10B981);
    } else if (healthIndex >= 60) {
      color = const Color(0xFFF59E0B);
    } else {
      color = const Color(0xFFEF4444);
    }

    return Column(
      children: [
        Text(
          healthIndex.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: healthIndex / 100,
          backgroundColor: Colors.grey[200],
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 8,
        ),
        const SizedBox(height: 8),
        Text(
          healthIndex >= 80 ? 'HEALTHY' : healthIndex >= 60 ? 'NEEDS ATTENTION' : 'CRITICAL',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildBriefSummaryCard(Map<String, dynamic> stage) {
    final summary = stage['ai_summary']?.toString() ?? 'No summary available';
    return Text(
      summary,
      style: const TextStyle(
        fontSize: 14,
        color: Color(0xFF1E293B),
        height: 1.5,
      ),
    );
  }

  Widget _buildTicketsCard() {
    // Placeholder - would integrate with ticket system
    return Column(
      children: [
        const Icon(Icons.assignment, size: 32, color: Color(0xFF94A3B8)),
        const SizedBox(height: 8),
        const Text(
          '0',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Color(0xFF1E293B),
          ),
        ),
        const Text(
          'Open Tickets',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }

  Widget _buildMilestoneCard() {
    // Placeholder - would integrate with milestone tracking
    return Column(
      children: [
        const Icon(Icons.flag, size: 32, color: Color(0xFF94A3B8)),
        const SizedBox(height: 8),
        const Text(
          'ON TRACK',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF10B981),
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Current Milestone',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }

  Widget _buildQMSStatusCard() {
    // Placeholder - would integrate with QMS system
    return Column(
      children: [
        const Icon(Icons.verified, size: 32, color: Color(0xFF94A3B8)),
        const SizedBox(height: 8),
        const Text(
          'COMPLIANT',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF10B981),
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'QMS Status',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }
}

class _ScrollControllerProvider extends StatefulWidget {
  final Widget Function(ScrollController h, ScrollController v) builder;

  const _ScrollControllerProvider({required this.builder});

  @override
  State<_ScrollControllerProvider> createState() => _ScrollControllerProviderState();
}

class _ScrollControllerProviderState extends State<_ScrollControllerProvider> {
  late final ScrollController _hResult;
  late final ScrollController _vResult;

  @override
  void initState() {
    super.initState();
    _hResult = ScrollController();
    _vResult = ScrollController();
  }

  @override
  void dispose() {
    _hResult.dispose();
    _vResult.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(_hResult, _vResult);
  }
}
