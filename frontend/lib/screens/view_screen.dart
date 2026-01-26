import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../providers/auth_provider.dart';
import '../providers/view_screen_provider.dart';
import '../services/api_service.dart';
import '../services/qms_service.dart';
import '../widgets/qms_status_badge.dart';
import 'qms_dashboard_screen.dart';
import 'package:fl_chart/fl_chart.dart';

class ViewScreen extends ConsumerStatefulWidget {
  final String? initialProject;
  final String? initialDomain;
  final String? initialViewType;
  
  const ViewScreen({
    super.key,
    this.initialProject,
    this.initialDomain,
    this.initialViewType,
  });

  @override
  ConsumerState<ViewScreen> createState() => _ViewScreenState();
}

class _ViewScreenState extends ConsumerState<ViewScreen> {
  final ApiService _apiService = ApiService();
  final QmsService _qmsService = QmsService();
  
  // Data structure: project -> block -> rtl_tag -> experiment -> stages
  Map<String, dynamic> _groupedData = {};
  
  /// Normalize domain name to handle case variations and abbreviations
  /// Returns uppercase abbreviation (PD, DV, RTL, DFT, AL) for consistency
  String _normalizeDomainName(String domain) {
    if (domain.isEmpty) return domain;
    
    final lower = domain.trim().toLowerCase();
    
    // Map to standard abbreviations
    if (lower == 'pd' || lower == 'physical design' || lower.contains('physical') && lower.contains('design')) {
      return 'PD';
    } else if (lower == 'dv' || lower == 'design verification' || (lower.contains('design') && lower.contains('verification'))) {
      return 'DV';
    } else if (lower == 'rtl' || lower == 'register transfer level' || lower.contains('rtl')) {
      return 'RTL';
    } else if (lower == 'dft' || lower == 'design for testability' || (lower.contains('testability') || lower.contains('dft'))) {
      return 'DFT';
    } else if (lower == 'al' || lower == 'analog layout' || (lower.contains('analog') && lower.contains('layout'))) {
      return 'AL';
    }
    
    // If no match, return uppercase version
    return domain.trim().toUpperCase();
  }
  
  /// Convert domain abbreviation to full name for backend queries
  /// Backend stores full lowercase names like "physical design", "design verification"
  String _domainToFullName(String domain) {
    final normalized = _normalizeDomainName(domain);
    switch (normalized) {
      case 'PD':
        return 'physical design';
      case 'DV':
        return 'design verification';
      case 'RTL':
        return 'register transfer level';
      case 'DFT':
        return 'design for testability';
      case 'AL':
        return 'analog layout';
      default:
        return domain.toLowerCase();
    }
  }
  
  // Selection state
  String? _selectedProject;
  String? _selectedDomain;
  String? _selectedBlock;
  String? _selectedTag;
  String? _selectedExperiment;
  String _stageFilter = 'all';
  String _viewType = 'engineer'; // Will be set based on user role in initState
  
  // Project-specific role and available view types
  List<String> _availableViewTypes = ['engineer']; // Default to engineer only
  String? _projectRole; // Project-specific role from user_projects
  
  // Lead View filters
  String _leadStageFilter = ''; // Empty means all stages
  String _leadStatusFilter = ''; // Empty means all statuses
  
  // Data
  bool _isLoading = false;
  bool _isLoadingDomains = false;
  List<dynamic> _projects = [];
  List<String> _availableDomainsForProject = [];
  
  // QMS data - block IDs and checklist data
  Map<String, int> _blockNameToId = {}; // Map block name to block ID
  Map<String, Map<String, dynamic>> _blockQmsData = {}; // Map block name to QMS checklist info
  
  // Graph Selection State - Multiple selections
  Set<String> _selectedMetricGroups = {'INTERNAL (R2R)'};
  Set<String> _selectedMetricTypes = {'WNS'};
  
  // Visualization type: 'graph' or 'heatmap'
  String _visualizationType = 'graph';
  
  // Chart type selector
  String _selectedChartType = 'Timing Metrics';

  // Scroll controllers for table
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Set initial values from parameters (widget params take priority)
    if (widget.initialProject != null) {
      _selectedProject = widget.initialProject;
    } else {
      // Check provider for params (when navigating from within app)
      final params = ref.read(viewScreenParamsProvider);
      if (params?.project != null) {
        _selectedProject = params!.project;
      }
    }
    
    if (widget.initialDomain != null) {
      _selectedDomain = widget.initialDomain;
    } else {
      final params = ref.read(viewScreenParamsProvider);
      if (params?.domain != null) {
        _selectedDomain = params!.domain;
      }
    }
    
    if (widget.initialViewType != null) {
      _viewType = widget.initialViewType!;
    } else {
      final params = ref.read(viewScreenParamsProvider);
      if (params?.viewType != null) {
        _viewType = params!.viewType!;
      }
      // View type will be set in _loadProjectsAndDomains based on user role
    }
    
    // Wait for next frame to ensure auth state is loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
    _loadProjectsAndDomains();
    });
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
      final userRole = authState.user?['role'];
      
      // Load projects with Zoho option - backend will check if Zoho is connected
      // This avoids an extra API call to check Zoho status
      Map<String, dynamic> projectsData;
      try {
        // Try to load with Zoho first - backend handles gracefully if not connected
        projectsData = await _apiService.getProjectsWithZoho(token: token, includeZoho: true);
      } catch (e) {
        // If Zoho fails, fallback to regular projects
        final projects = await _apiService.getProjects(token: token);
        projectsData = {'all': projects, 'local': projects, 'zoho': []};
      }
      
      // Set default view type based on user role
      // Note: Project-specific role will be fetched later and may override this
      String defaultViewType = 'engineer';
      if (userRole == 'management') {
        defaultViewType = 'management';
      } else if (userRole == 'cad_engineer') {
        defaultViewType = 'cad';
      } else if (userRole == 'customer') {
        defaultViewType = 'customer';
      } else if (userRole == 'admin' || userRole == 'project_manager') {
        // Admin and project_manager can see manager view, but default to manager (not management)
        defaultViewType = 'manager';
      } else if (userRole == 'lead') {
        defaultViewType = 'lead';
      }
      
      setState(() {
        _projects = projectsData['all'] ?? projectsData['local'] ?? [];
        // View type will be set based on project-specific role after project is loaded
        _isLoading = false;
      });
      
      // If project is pre-selected (from widget or provider), load domains for it
      final params = ref.read(viewScreenParamsProvider);
      final projectToLoad = widget.initialProject ?? params?.project ?? _selectedProject;
      
      // If project is already selected, fetch its role
      if (projectToLoad != null) {
        await _fetchProjectRole(projectToLoad);
        // Set view type based on available views if not explicitly set
        if (widget.initialViewType == null) {
          String defaultViewType = 'engineer';
          if (_availableViewTypes.contains('management')) {
            defaultViewType = 'management';
          } else if (_availableViewTypes.contains('manager')) {
            defaultViewType = 'manager';
          } else if (_availableViewTypes.contains('lead')) {
            defaultViewType = 'lead';
          } else if (_availableViewTypes.contains('engineer')) {
            defaultViewType = 'engineer';
          } else if (_availableViewTypes.contains('customer')) {
            defaultViewType = 'customer';
          }
          setState(() {
            _viewType = defaultViewType;
          });
        }
      } else {
        // No project selected, use global role default
        if (widget.initialViewType == null) {
          setState(() {
            _viewType = defaultViewType;
          });
        }
      }
      final domainToLoad = widget.initialDomain ?? params?.domain ?? _selectedDomain;
      
      // Set project immediately if provided (important for customer view)
      if (projectToLoad != null && _selectedProject != projectToLoad) {
        setState(() {
          _selectedProject = projectToLoad;
        });
      }
      
      if (projectToLoad != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Load domains first, then select domain and load data
          _loadDomainsForProject(projectToLoad).then((_) {
            // After domains are loaded, select domain if provided
            if (mounted) {
              if (domainToLoad != null && domainToLoad.isNotEmpty) {
                // Domain was provided - try to select it
                if (_availableDomainsForProject.contains(domainToLoad)) {
                  setState(() {
                    _selectedDomain = domainToLoad;
                  });
                  _loadInitialData();
                } else {
                  // Try case-insensitive match
                  final lowerDomainToLoad = domainToLoad.toLowerCase();
                  final matchingDomain = _availableDomainsForProject.firstWhere(
                    (d) => d.toLowerCase() == lowerDomainToLoad,
                    orElse: () => '',
                  );
                  if (matchingDomain.isNotEmpty) {
                    setState(() {
                      _selectedDomain = matchingDomain;
                    });
                    _loadInitialData();
                  } else if (_availableDomainsForProject.isNotEmpty) {
                    // Use first available domain if provided domain not found
                    setState(() {
                      _selectedDomain = _availableDomainsForProject.first;
                    });
                    _loadInitialData();
                  }
                }
              } else if (userRole == 'customer' && _availableDomainsForProject.isNotEmpty) {
                // For customers, auto-select first domain
                setState(() {
                  _selectedDomain = _availableDomainsForProject.first;
                });
                _loadInitialData();
              } else if (_availableDomainsForProject.length == 1) {
                // Only one domain available
                setState(() {
                  _selectedDomain = _availableDomainsForProject.first;
                });
                _loadInitialData();
              }
            }
          });
        });
      } else if (_selectedProject != null && _selectedDomain != null) {
        // If project and domain are already selected, load data automatically
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadInitialData();
        });
      }
      
      // Clear the provider params after reading them
      if (params != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(viewScreenParamsProvider.notifier).state = null;
        });
      }
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
      
      // Load EDA files with backend filtering by project and domain
      // This reduces data transfer and improves performance
      // Convert domain abbreviation to full name for backend query
      final domainForQuery = _selectedDomain != null ? _domainToFullName(_selectedDomain!) : null;
      final filesResponse = await _apiService.getEdaFiles(
        token: token,
        projectName: _selectedProject,
        domainName: domainForQuery, // Use full name for backend query
        limit: 500, // Reduced from 1000 for faster initial load
      );
      
      final files = filesResponse['files'] ?? [];
      
      print('🔵 [VIEW_SCREEN] Loaded ${files.length} files for project: $_selectedProject, domain: $_selectedDomain (query used: $domainForQuery)');
      
      // Files are already filtered by backend, no need to filter again
      final filteredFiles = files;
      
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
          'metal_density_max': _parseNumeric(file['metal_density_max']),
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

    // Watch auth state to check user role
    final currentAuthState = ref.watch(authProvider);
    final userRole = currentAuthState.user?['role'];
    final isCustomer = userRole == 'customer';
    
    // For customers, show customer view even if project/domain not selected yet (they're loading)
    if (isCustomer && _viewType == 'customer') {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1900),
              child: _buildCustomerView(),
            ),
          ),
        ),
      );
    }
    
    // Show project and domain selection if not selected (for non-customers)
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
                ],
              ),
            ),
          ),
        ),
      );
    }

    // For customers, show customer view (even if data is empty, let customer view handle it)
    if (isCustomer && _viewType == 'customer') {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1900),
              child: _buildCustomerView(),
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

    // Update view type if it doesn't match the user's role (important for refresh)
    // Check both global role and project role to handle project admins
    if (widget.initialViewType == null && userRole != null) {
      String correctViewType = 'engineer';
      // Check if user is admin (either globally or in project)
      final isAdmin = userRole == 'admin' || _projectRole == 'admin';
      if (userRole == 'customer') {
        correctViewType = 'customer';
      } else if (isAdmin || userRole == 'project_manager' || _projectRole == 'project_manager') {
        // Admins (global or project) and PMs default to manager view
        // But check available views first to see if management is available
        if (_availableViewTypes.contains('management')) {
          correctViewType = 'management';
        } else if (_availableViewTypes.contains('manager')) {
          correctViewType = 'manager';
        } else {
          correctViewType = 'manager';
        }
      } else if (userRole == 'lead' || _projectRole == 'lead') {
        correctViewType = 'lead';
      }
      
      // Only update if current view type is wrong and the correct one is available
      if (_viewType != correctViewType && _availableViewTypes.contains(correctViewType)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _viewType = correctViewType;
            });
          }
        });
      }
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
                // Hide header for customers and management - they don't need project/domain selection
                if (_viewType != 'customer' && _viewType != 'management') ...[
                _buildHeader(),
                const SizedBox(height: 24),
                ],
                if (_viewType == 'engineer') ...[
                  _buildFilterBar(),
                  const SizedBox(height: 24),
                  _buildEngineerKPICards(activeRun, activeStages),
                  const SizedBox(height: 24),
                  _buildStageProgressVisualization(activeStages),
                  const SizedBox(height: 24),
                  _buildDetailedTimingMetricsTable(activeStages),
                  const SizedBox(height: 24),
                  _buildPhysicalMetricsTable(activeStages),
                  const SizedBox(height: 24),
                  _buildResourceUtilizationTable(activeStages),
                  const SizedBox(height: 24),
                  _buildMetricsGraphSection(activeStages),
                ] else if (_viewType == 'lead') ...[
                  _buildFilterBar(),
                  const SizedBox(height: 24),
                  _buildLeadView(activeStages),
                ] else if (_viewType == 'manager') ...[
                  _buildManagerView(),
                ] else if (_viewType == 'customer') ...[
                  _buildCustomerView(),
                ] else if (_viewType == 'management') ...[
                  _buildManagementView(),
                ] else if (_viewType == 'cad') ...[
                  _buildCadView(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }



  Widget _buildViewTypeSelector() {
    // Only show view types that are available for the current project
    final viewTypeChips = <Widget>[];

    bool viewTypeChandleSpacing(List<Widget> chips) => chips.isNotEmpty;
    
    if (_availableViewTypes.contains('engineer')) {
      viewTypeChips.add(_buildViewTypeChip('Engineer View', 'engineer'));
    }
    
    if (_availableViewTypes.contains('lead')) {
      if (viewTypeChips.isNotEmpty) {
        viewTypeChips.add(const SizedBox(width: 8));
      }
      viewTypeChips.add(_buildViewTypeChip('Lead View', 'lead'));
    }
    
    if (_availableViewTypes.contains('manager')) {
      if (viewTypeChips.isNotEmpty) {
        viewTypeChips.add(const SizedBox(width: 8));
      }
      viewTypeChips.add(_buildViewTypeChip('Manager View', 'manager'));
    }
    
    if (_availableViewTypes.contains('customer')) {
      if (viewTypeChandleSpacing(viewTypeChips)) {
        viewTypeChips.add(const SizedBox(width: 8));
      }
      viewTypeChips.add(_buildViewTypeChip('Customer View', 'customer'));
    }
    
    if (_availableViewTypes.contains('management')) {
      if (viewTypeChandleSpacing(viewTypeChips)) {
        viewTypeChips.add(const SizedBox(width: 8));
      }
      viewTypeChips.add(_buildViewTypeChip('Management View', 'management'));
    }

    if (_availableViewTypes.contains('cad')) {
      if (viewTypeChandleSpacing(viewTypeChips)) {
        viewTypeChips.add(const SizedBox(width: 8));
      }
      viewTypeChips.add(_buildViewTypeChip('CAD View', 'cad'));
    }
    
    // If no view types available, show engineer as fallback
    if (viewTypeChips.isEmpty) {
      viewTypeChips.add(_buildViewTypeChip('Engineer View', 'engineer'));
    }
    
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
          ...viewTypeChips,
        ],
      ),
    );
  }

  Widget _buildViewTypeChip(String label, String value) {
    final isSelected = _viewType == value;
    final isAvailable = _availableViewTypes.contains(value);
    return GestureDetector(
      onTap: isAvailable
          ? () {
              setState(() {
                _viewType = value;
              });
              if (value == 'cad' && _selectedProject != null) {
                _loadCadStatusForProject(_selectedProject!);
              }
            }
          : null,
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
    // Get project names and domains
    final projectNames = <String>[];
    try {
      if (_projects.isNotEmpty) {
        projectNames.addAll(
          _projects.map((p) => p['name']?.toString() ?? 'Unknown').toList().cast<String>()
        );
      }
    } catch (e) {
      // Handle error
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left side: Project and Domain dropdowns
          Row(
            children: [
              // Project Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: DropdownButton<String>(
                  value: _selectedProject,
                  hint: const Text(
                    'Select Project',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                  underline: const SizedBox(),
                  isDense: true,
                  items: projectNames.map((name) {
                    return DropdownMenuItem<String>(
                      value: name,
                      child: Text(
                        name,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B)),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) => _updateProject(value),
                ),
              ),
              const SizedBox(width: 16),
              // Domain Dropdown
              if (_selectedProject != null) ...[
                if (_isLoadingDomains)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                      ),
                    ),
                  )
                else if (_availableDomainsForProject.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: DropdownButton<String>(
                      value: _selectedDomain,
                      hint: const Text(
                        'Select Domain',
                        style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                      ),
                      underline: const SizedBox(),
                      isDense: true,
                      items: _availableDomainsForProject.map((domain) {
                        return DropdownMenuItem<String>(
                          value: domain,
                          child: Text(
                            domain,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B)),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) => _updateDomain(value),
                    ),
                  ),
              ],
            ],
          ),
          // Right side: View Type Selector (only show when project and domain are selected, and not customer)
          if (_selectedProject != null && _selectedDomain != null)
            Builder(
              builder: (context) {
                final userRole = ref.read(authProvider).user?['role'];
                if (userRole == 'customer') {
                  return const SizedBox.shrink();
                }
                // Only show view types that are available for the current project
                final viewTypeChipsInline = <Widget>[];
                
                if (_availableViewTypes.contains('engineer')) {
                  viewTypeChipsInline.add(_buildViewTypeChip('Engineer View', 'engineer'));
                }
                
                if (_availableViewTypes.contains('lead')) {
                  if (viewTypeChipsInline.isNotEmpty) {
                    viewTypeChipsInline.add(const SizedBox(width: 8));
                  }
                  viewTypeChipsInline.add(_buildViewTypeChip('Lead View', 'lead'));
                }
                
                if (_availableViewTypes.contains('manager')) {
                  if (viewTypeChipsInline.isNotEmpty) {
                    viewTypeChipsInline.add(const SizedBox(width: 8));
                  }
                  viewTypeChipsInline.add(_buildViewTypeChip('Manager View', 'manager'));
                }
                
                if (_availableViewTypes.contains('customer')) {
                  if (viewTypeChipsInline.isNotEmpty) {
                    viewTypeChipsInline.add(const SizedBox(width: 8));
                  }
                  viewTypeChipsInline.add(_buildViewTypeChip('Customer View', 'customer'));
                }
                
                if (_availableViewTypes.contains('management')) {
                  if (viewTypeChipsInline.isNotEmpty) {
                    viewTypeChipsInline.add(const SizedBox(width: 8));
                  }
                  viewTypeChipsInline.add(_buildViewTypeChip('Management View', 'management'));
                }

                if (_availableViewTypes.contains('cad')) {
                  if (viewTypeChipsInline.isNotEmpty) {
                    viewTypeChipsInline.add(const SizedBox(width: 8));
                  }
                  viewTypeChipsInline.add(_buildViewTypeChip('CAD View', 'cad'));
                }
                
                // If no view types available, show engineer as fallback
                if (viewTypeChipsInline.isEmpty) {
                  viewTypeChipsInline.add(_buildViewTypeChip('Engineer View', 'engineer'));
                }
                
                return Row(
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
                    ...viewTypeChipsInline,
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _loadDomainsForProject(String projectName) async {
    print('🔵 [VIEW_SCREEN] Loading domains for project: $projectName');
    print('🔵 [VIEW_SCREEN] Initial domain from widget: ${widget.initialDomain}');
    print('🔵 [VIEW_SCREEN] Current selected domain: $_selectedDomain');
    setState(() {
      _selectedProject = projectName;
      _isLoadingDomains = true;
    });

    // Get domains for this project from multiple sources
    try {
      final authState = ref.read(authProvider);
      final token = authState.token;
      
      final domainSet = <String>{};
      
      // First, try to get domains from project data (project_domains table)
      Map<String, dynamic>? matchingProject;
      try {
        // Use getProjectsWithZoho to get both local and Zoho projects
        final projectsData = await _apiService.getProjectsWithZoho(token: token, includeZoho: true);
        final allProjects = projectsData['all'] ?? [];
        
        matchingProject = allProjects.firstWhere(
          (p) => (p['name']?.toString() ?? '') == projectName,
          orElse: () => null,
        );
        
        if (matchingProject != null) {
          // Check if it's a Zoho project
          final isZohoProject = matchingProject['source'] == 'zoho' || 
                                matchingProject['zoho_project_id'] != null;
          
          // Check if project has domains array (from project_domains table)
          final projectDomains = matchingProject['domains'];
          if (projectDomains is List && projectDomains.isNotEmpty) {
            for (var domain in projectDomains) {
              if (domain is Map<String, dynamic>) {
                final domainName = domain['name']?.toString();
                if (domainName != null && domainName.isNotEmpty) {
                  domainSet.add(domainName);
                }
              }
            }
          }
          
          // For Zoho projects, also try to get domains from Zoho tasklists
          if (isZohoProject && domainSet.isEmpty) {
            try {
              final zohoProjectId = matchingProject['zoho_project_id']?.toString();
              final zohoData = matchingProject['zoho_data'] as Map<String, dynamic>?;
              final portalId = zohoData?['portal_id']?.toString() ?? 
                              zohoData?['portal']?.toString();
              
              if (zohoProjectId != null && zohoProjectId.isNotEmpty) {
                print('🔵 [VIEW_SCREEN] Fetching domains from Zoho tasklists for project: $projectName');
                final tasksResponse = await _apiService.getZohoTasks(
                  projectId: zohoProjectId,
                  token: token,
                  portalId: portalId,
                );
                
                final tasks = tasksResponse['tasks'] ?? [];
                final tasklistNames = <String>{};
                
                for (final task in tasks) {
                  final tasklistName = (task['tasklist_name'] ?? task['tasklistName'] ?? '').toString();
                  if (tasklistName.isNotEmpty) {
                    tasklistNames.add(tasklistName);
                  }
                }
                
                // Add tasklist names as domains (normalized to avoid duplicates)
                for (final tasklistName in tasklistNames) {
                  final normalized = _normalizeDomainName(tasklistName);
                  if (normalized.isNotEmpty) {
                    domainSet.add(normalized);
                  }
                }
                
                print('🔵 [VIEW_SCREEN] Found ${tasklistNames.length} domains from Zoho tasklists: $tasklistNames');
              }
            } catch (e) {
              print('Error loading domains from Zoho tasklists: $e');
            }
          }
        }
      } catch (e) {
        print('Error loading domains from project data: $e');
      }
      
      // Also load EDA files to find domains for this project
      try {
        final filesResponse = await _apiService.getEdaFiles(
          token: token,
          limit: 1000,
        );
        
        final files = filesResponse['files'] ?? [];
        
        for (var file in files) {
          final projectNameFromFile = file['project_name']?.toString() ?? 'Unknown';
          final domainName = file['domain_name']?.toString() ?? '';
          if (projectNameFromFile == projectName && domainName.isNotEmpty) {
            final normalized = _normalizeDomainName(domainName);
            if (normalized.isNotEmpty) {
              domainSet.add(normalized);
            }
          }
        }
      } catch (e) {
        print('Error loading domains from EDA files: $e');
      }
      
      // For Zoho projects, also extract domains from run_directory paths
      // Run directory format: /CX_RUN_NEW/{project}/{domain}/users/{username}/{block}/{experiment}
      if (matchingProject != null) {
        try {
          final isZohoProject = matchingProject['source'] == 'zoho' || 
                                matchingProject['zoho_project_id'] != null;
          
          if (isZohoProject) {
            // Try to get domains from run directories
            final runDirectories = matchingProject['run_directories'] as List<dynamic>? ?? [];
            if (runDirectories.isEmpty) {
              final runDirectory = matchingProject['run_directory']?.toString();
              if (runDirectory != null && runDirectory.isNotEmpty) {
                runDirectories.add(runDirectory);
              }
            }
            
            // Extract domain from run directory paths
            // Format: /CX_RUN_NEW/{project}/{domain}/users/...
            for (var runDir in runDirectories) {
              final runDirStr = runDir.toString();
              // Match pattern: /CX_RUN_NEW/{project}/{domain}/
              final match = RegExp(r'/CX_RUN_NEW/[^/]+/([^/]+)/').firstMatch(runDirStr);
              if (match != null && match.groupCount >= 1) {
                final domainFromPath = match.group(1);
                if (domainFromPath != null && domainFromPath.isNotEmpty) {
                  final normalized = _normalizeDomainName(domainFromPath);
                  if (normalized.isNotEmpty) {
                    domainSet.add(normalized);
                  }
                }
              }
            }
            
            // Also check if project is mapped to local project and get domains from there
            // Need to fetch projects again to get local projects list
            final asiProjectId = matchingProject['asi_project_id'];
            if (asiProjectId != null) {
              try {
                final projectsDataForLocal = await _apiService.getProjectsWithZoho(token: token, includeZoho: true);
                final localProjects = projectsDataForLocal['local'] ?? [];
                final localProject = localProjects.firstWhere(
                  (p) => p['id'] == asiProjectId,
                  orElse: () => null,
                );
                
                if (localProject != null) {
                  final localProjectDomains = localProject['domains'];
                  if (localProjectDomains is List) {
                    for (var domain in localProjectDomains) {
                      if (domain is Map<String, dynamic>) {
                        final domainName = domain['name']?.toString();
                        if (domainName != null && domainName.isNotEmpty) {
                          final normalized = _normalizeDomainName(domainName);
                          if (normalized.isNotEmpty) {
                            domainSet.add(normalized);
                          }
                        }
                      }
                    }
                  }
                }
              } catch (e) {
                print('Error loading domains from mapped local project: $e');
              }
            }
          }
        } catch (e) {
          print('Error extracting domains from run directories: $e');
        }
      }
      
      // If initialDomain is provided but not in the found domains, add it to the list
      // This ensures the domain dropdown shows the passed domain even if it's not in the database yet
      if (widget.initialDomain != null && 
          widget.initialDomain!.isNotEmpty) {
        final normalizedInitial = _normalizeDomainName(widget.initialDomain!);
        if (normalizedInitial.isNotEmpty && !domainSet.contains(normalizedInitial)) {
          print('🔵 [VIEW_SCREEN] Initial domain ${widget.initialDomain} (normalized: $normalizedInitial) not found in available domains, adding it to list');
          domainSet.add(normalizedInitial);
        }
      }
      
      final availableDomains = domainSet.toList()..sort();
      
      print('🔵 [VIEW_SCREEN] Found ${availableDomains.length} domains: $availableDomains');
      print('🔵 [VIEW_SCREEN] Initial domain from widget: ${widget.initialDomain}');
      print('🔵 [VIEW_SCREEN] Current selected domain before update: $_selectedDomain');
      
      setState(() {
        _availableDomainsForProject = availableDomains;
        _isLoadingDomains = false;
        
        // Auto-select domain if:
        // 1. initialDomain is provided - normalize and match
        if (widget.initialDomain != null && widget.initialDomain!.isNotEmpty) {
          final normalizedInitial = _normalizeDomainName(widget.initialDomain!);
          print('🔵 [VIEW_SCREEN] Attempting to match initial domain: ${widget.initialDomain} (normalized: $normalizedInitial)');
          // Try normalized match (availableDomains are already normalized)
          if (normalizedInitial.isNotEmpty && availableDomains.contains(normalizedInitial)) {
            print('🔵 [VIEW_SCREEN] Match found for domain: $normalizedInitial');
            _selectedDomain = normalizedInitial;
            _loadInitialData();
          } else if (availableDomains.isNotEmpty) {
            // If no match found, use first available domain
            print('🔵 [VIEW_SCREEN] No match found for ${widget.initialDomain}, using first available domain: ${availableDomains.first}');
            _selectedDomain = availableDomains.first;
            _loadInitialData();
          } else {
            print('⚠️ [VIEW_SCREEN] No domains available for project: $projectName');
          }
        } else if (availableDomains.length == 1) {
          // 2. Only one domain available
          print('🔵 [VIEW_SCREEN] Only one domain available, auto-selecting: ${availableDomains.first}');
          _selectedDomain = availableDomains.first;
          _loadInitialData();
        } else if (availableDomains.isNotEmpty && _selectedDomain == null) {
          // 3. For customers, always auto-select first domain
          // For other roles, also auto-select first domain if available
          final authStateForRole = ref.read(authProvider);
          final userRoleForDomain = authStateForRole.user?['role'];
          final isCustomerForDomain = userRoleForDomain == 'customer';
          
          if (isCustomerForDomain || widget.initialDomain == null) {
            print('🔵 [VIEW_SCREEN] Auto-selecting first domain: ${availableDomains.first}');
            _selectedDomain = availableDomains.first;
            _loadInitialData();
          }
        } else {
          print('⚠️ [VIEW_SCREEN] No domain selected. Available domains: $availableDomains, Initial domain: ${widget.initialDomain}');
        }
        
        print('🔵 [VIEW_SCREEN] Final selected domain after update: $_selectedDomain');
        print('🔵 [VIEW_SCREEN] Available domains list: $_availableDomainsForProject');
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

  // Fetch project-specific role and update available view types
  Future<void> _fetchProjectRole(String projectIdentifier) async {
    try {
      final authState = ref.read(authProvider);
      final token = authState.token;
      
      final roleResponse = await _apiService.getUserProjectRole(
        projectIdentifier: projectIdentifier,
        token: token,
      );
      
      if (roleResponse['success'] == true) {
        final availableViewTypes = List<String>.from(roleResponse['availableViewTypes'] ?? ['engineer']);
        final effectiveRole = roleResponse['effectiveRole'] ?? 'engineer';
        final projectRole = roleResponse['projectRole'];
        
        // Set default view type to the highest available view
        // For admins (global or project-specific), default to manager view
        String defaultViewType = 'engineer';
        if (projectRole == 'admin' || effectiveRole == 'admin') {
          // Project admins should default to manager view (or management if available)
          if (availableViewTypes.contains('management')) {
            defaultViewType = 'management';
          } else if (availableViewTypes.contains('manager')) {
            defaultViewType = 'manager';
          } else if (availableViewTypes.contains('cad')) {
            defaultViewType = 'cad';
          } else if (availableViewTypes.contains('lead')) {
            defaultViewType = 'lead';
          } else if (availableViewTypes.contains('engineer')) {
            defaultViewType = 'engineer';
          }
        } else if (availableViewTypes.contains('cad')) {
          defaultViewType = 'cad';
        } else if (availableViewTypes.contains('manager')) {
          defaultViewType = 'manager';
        } else if (availableViewTypes.contains('lead')) {
          defaultViewType = 'lead';
        } else if (availableViewTypes.contains('engineer')) {
          defaultViewType = 'engineer';
        } else if (availableViewTypes.contains('customer')) {
          defaultViewType = 'customer';
        }
        
        setState(() {
          _availableViewTypes = availableViewTypes;
          _projectRole = projectRole;
          // Only update view type if current one is not available
          if (!availableViewTypes.contains(_viewType)) {
            _viewType = defaultViewType;
          }
        });
      }
    } catch (e) {
      // If fetching project role fails, default to engineer view
      setState(() {
        _availableViewTypes = ['engineer'];
        _projectRole = null;
        if (_viewType != 'engineer' && _viewType != 'customer') {
          _viewType = 'engineer';
        }
      });
    }
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
        _availableViewTypes = ['engineer'];
        _projectRole = null;
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

    // Fetch project-specific role first
    await _fetchProjectRole(projectName);

    // Load domains for this project (reuse the same method)
    await _loadDomainsForProject(projectName);
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
              // Only show stage filter in engineer view, not in lead view
              if (_viewType != 'lead')
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

  // ============================================================================
  // ENGINEER VIEW - NEW IMPLEMENTATION
  // ============================================================================

  Widget _buildEngineerKPICards(Map<String, dynamic>? activeRun, List<Map<String, dynamic>> stages) {
    if (activeRun == null || stages.isEmpty) return const SizedBox();

    final lastStage = stages.last;
    
    // Get setup timing QOR with path group breakdown
    final setupPathGroups = lastStage['setup_path_groups'] as Map<String, dynamic>? ?? {};
    final reg2regWns = _parseNumeric(setupPathGroups['reg2reg']?['wns']) ?? 
                      _parseNumeric(lastStage['internal_timing_r2r_wns']);
    
    // Get hold timing metrics (reg2reg focused)
    final holdWns = _parseNumeric(lastStage['hold_wns']);
    final holdTns = _parseNumeric(lastStage['hold_tns']);
    final holdNvp = _parseNumeric(lastStage['hold_nvp'])?.toInt() ?? 0;
    
    // Physical metrics
    final area = _parseNumeric(lastStage['area']);
    final utilization = lastStage['utilization']?.toString() ?? 'N/A';
    final instCount = _parseNumeric(lastStage['inst_count'])?.toInt() ?? 0;
    
    // Verification status
    final drc = lastStage['pv_drc_base']?.toString() ?? 'N/A';
    final lvs = lastStage['lvs']?.toString() ?? 'N/A';
    final r2gLec = lastStage['r2g_lec']?.toString() ?? 'N/A';
    final g2gLec = lastStage['g2g_lec']?.toString() ?? 'N/A';
    
    // Latest stage info
    final runtime = lastStage['runtime']?.toString() ?? 'N/A';
    final memory = lastStage['memory_usage']?.toString() ?? 'N/A';
    final stageName = lastStage['stage']?.toString().toUpperCase() ?? 'N/A';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 768;
        final cardWidth = isMobile ? constraints.maxWidth : (constraints.maxWidth - 80) / 5;
        
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            // KPI Card 1: Latest Stage Info
            SizedBox(
              width: isMobile ? constraints.maxWidth : cardWidth,
              child: _buildKPICard(
                title: 'Latest Stage Info',
                icon: Icons.info_outline,
                color: const Color(0xFF3B82F6),
                children: [
                  _buildKPIValue(stageName, subtitle: 'Stage'),
                  const SizedBox(height: 12),
                  _buildKPIValue(runtime, subtitle: 'Runtime'),
                  const SizedBox(height: 8),
                  _buildKPIValue(memory, subtitle: 'Memory'),
                ],
              ),
            ),
            
            // KPI Card 2: Setup Timing QOR
            SizedBox(
              width: isMobile ? constraints.maxWidth : cardWidth,
              child: _buildKPICard(
                title: 'Setup Timing QOR',
                icon: Icons.timer_outlined,
                color: const Color(0xFF10B981),
                children: [
                  _buildKPIValue(
                    reg2regWns != null ? reg2regWns.toStringAsFixed(3) : 'N/A',
                    subtitle: 'Reg2Reg WNS',
                  ),
                  const SizedBox(height: 12),
                  _buildPathGroupBreakdown(setupPathGroups),
                ],
              ),
            ),
            
            // KPI Card 3: Hold Timing Metrics
            SizedBox(
              width: isMobile ? constraints.maxWidth : cardWidth,
              child: _buildKPICard(
                title: 'Hold Timing (Reg2Reg)',
                icon: Icons.schedule,
                color: const Color(0xFFF59E0B),
                children: [
                  _buildKPIValue(
                    holdWns != null ? holdWns.toStringAsFixed(3) : 'N/A',
                    subtitle: 'WNS',
                  ),
                  const SizedBox(height: 8),
                  _buildKPIValue(
                    holdTns != null ? holdTns.toStringAsFixed(2) : 'N/A',
                    subtitle: 'TNS',
                  ),
                  const SizedBox(height: 8),
                  _buildKPIValue(
                    holdNvp.toString(),
                    subtitle: 'NVP',
                  ),
                ],
              ),
            ),
            
            // KPI Card 4: Physical Metrics
            SizedBox(
              width: isMobile ? constraints.maxWidth : cardWidth,
              child: _buildKPICard(
                title: 'Physical Metrics',
                icon: Icons.square_foot,
                color: const Color(0xFF8B5CF6),
                children: [
                  _buildKPIValue(
                    area != null ? area.toStringAsFixed(2) : 'N/A',
                    subtitle: 'Area',
                  ),
                  const SizedBox(height: 8),
                  _buildKPIValue(utilization, subtitle: 'Utilization'),
                  const SizedBox(height: 8),
                  _buildKPIValue(
                    instCount.toString(),
                    subtitle: 'Instance Count',
                  ),
                ],
              ),
            ),
            
            // KPI Card 5: Verification Status
            SizedBox(
              width: isMobile ? constraints.maxWidth : cardWidth,
              child: _buildKPICard(
                title: 'Verification Status',
                icon: Icons.verified_outlined,
                color: const Color(0xFFEF4444),
                children: [
                  _buildVerificationItem('DRC', drc),
                  const SizedBox(height: 8),
                  _buildVerificationItem('LVS', lvs),
                  const SizedBox(height: 8),
                  _buildVerificationItem('R2G LEC', r2gLec),
                  const SizedBox(height: 8),
                  _buildVerificationItem('G2G LEC', g2gLec),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildKPICard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildKPIValue(String value, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (subtitle != null)
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF94A3B8),
              letterSpacing: 0.5,
            ),
          ),
        if (subtitle != null) const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E293B),
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildPathGroupBreakdown(Map<String, dynamic> pathGroups) {
    final groups = ['reg2reg', 'in2reg', 'reg2out', 'all'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Path Groups',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Color(0xFF94A3B8),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        ...groups.map((group) {
          final data = pathGroups[group] as Map<String, dynamic>?;
          final wns = _parseNumeric(data?['wns']);
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  group.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
                Text(
                  wns != null ? wns.toStringAsFixed(3) : 'N/A',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildVerificationItem(String label, String value) {
    final isPass = value.toString().toLowerCase() == 'pass' || 
                   value.toString().toLowerCase() == '0' ||
                   value.toString() == 'N/A';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isPass ? const Color(0xFFDCFCE7) : const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isPass ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
              width: 1,
            ),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: isPass ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStageProgressVisualization(List<Map<String, dynamic>> stages) {
    if (stages.isEmpty) return const SizedBox();

    // Full stage order for sorting
    final stageOrder = ['syn', 'init', 'floorplan', 'place', 'cts', 'postcts', 'route', 'postroute'];
    final stageNames = {
      'syn': 'Synthesis',
      'init': 'Init',
      'floorplan': 'Floorplan',
      'place': 'Placement',
      'cts': 'CTS',
      'postcts': 'Post-CTS',
      'route': 'Routing',
      'postroute': 'Post-Route',
    };

    // Extract unique stages from the provided stages list
    final uniqueStages = <String, Map<String, dynamic>>{};
    for (var stage in stages) {
      final stageKey = stage['stage']?.toString().toLowerCase() ?? '';
      if (stageKey.isNotEmpty) {
        // Keep the most recent stage if there are duplicates (by timestamp)
        if (!uniqueStages.containsKey(stageKey)) {
          uniqueStages[stageKey] = stage;
        } else {
          final existingTimestamp = uniqueStages[stageKey]!['timestamp']?.toString() ?? '';
          final currentTimestamp = stage['timestamp']?.toString() ?? '';
          if (currentTimestamp.isNotEmpty && existingTimestamp.isNotEmpty) {
            try {
              final existingDate = DateTime.parse(existingTimestamp);
              final currentDate = DateTime.parse(currentTimestamp);
              if (currentDate.isAfter(existingDate)) {
                uniqueStages[stageKey] = stage;
              }
            } catch (e) {
              // If timestamp parsing fails, keep existing
            }
          }
        }
      }
    }

    // Sort stages according to stage order
    final sortedStageKeys = uniqueStages.keys.toList();
    sortedStageKeys.sort((a, b) {
      final aIdx = stageOrder.indexOf(a);
      final bIdx = stageOrder.indexOf(b);
      if (aIdx == -1 && bIdx == -1) return 0;
      if (aIdx == -1) return 1;
      if (bIdx == -1) return -1;
      return aIdx.compareTo(bIdx);
    });

    // Determine the recent/latest stage (last one in the sorted list)
    final recentStageKey = sortedStageKeys.isNotEmpty ? sortedStageKeys.last : null;

    // Colors: green for all stages, blue for latest
    const allStageColor = Color(0xFF10B981); // Green
    const latestStageColor = Color(0xFF3B82F6); // Blue

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.timeline, size: 20, color: Color(0xFF0F172A)),
              SizedBox(width: 12),
              Text(
                'Stage Progress',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: sortedStageKeys.map((stageKey) {
              final stage = uniqueStages[stageKey]!;
              final isLatestStage = stageKey == recentStageKey;
              final stageColor = isLatestStage ? latestStageColor : allStageColor;

              return Container(
                width: 140,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: stageColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: stageColor,
                    width: isLatestStage ? 2.5 : 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: stageColor,
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      stageNames[stageKey] ?? stageKey.toUpperCase(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isLatestStage ? FontWeight.w700 : FontWeight.w600,
                        color: stageColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (stage['timestamp'] != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        stage['timestamp']?.toString().split(' ').first ?? '',
                        style: TextStyle(
                          fontSize: 10,
                          color: stageColor.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedTimingMetricsTable(List<Map<String, dynamic>> stages) {
    if (stages.isEmpty) return const SizedBox();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white, // White background
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
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
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.table_chart, size: 22, color: Color(0xFF0F172A)),
                SizedBox(width: 12),
                Text(
                  'Detailed Timing Metrics',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              border: TableBorder(
                horizontalInside: BorderSide(color: Colors.grey.shade200, width: 1),
                verticalInside: BorderSide(color: Colors.grey.shade200, width: 1),
                top: BorderSide(color: Colors.grey.shade300, width: 1),
                bottom: BorderSide(color: Colors.grey.shade300, width: 1),
                left: BorderSide(color: Colors.grey.shade300, width: 1),
                right: BorderSide(color: Colors.grey.shade300, width: 1),
              ),
              columnWidths: const {
                0: FixedColumnWidth(120),
                1: FixedColumnWidth(110),
                2: FixedColumnWidth(110),
                3: FixedColumnWidth(100),
                4: FixedColumnWidth(110),
                5: FixedColumnWidth(110),
                6: FixedColumnWidth(110),
                7: FixedColumnWidth(110),
                8: FixedColumnWidth(110),
                9: FixedColumnWidth(110),
                10: FixedColumnWidth(100),
              },
              children: [
                // Header Row
                TableRow(
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                  ),
                  children: [
                    _buildTableHeaderCell('STAGE'),
                    _buildTableHeaderCell('Reg2Reg WNS'),
                    _buildTableHeaderCell('Reg2Reg TNS'),
                    _buildTableHeaderCell('Reg2Reg NVP'),
                    _buildTableHeaderCell('I2R WNS'),
                    _buildTableHeaderCell('I2R TNS'),
                    _buildTableHeaderCell('R2O WNS'),
                    _buildTableHeaderCell('R2O TNS'),
                    _buildTableHeaderCell('Hold WNS'),
                    _buildTableHeaderCell('Hold TNS'),
                    _buildTableHeaderCell('Hold NVP'),
                  ],
                ),
                // Data Rows
                ...stages.map((stage) {
                  final r2rWns = _formatTimingValueString(stage['internal_timing_r2r_wns']);
                  final r2rTns = _formatTimingValueString(stage['internal_timing_r2r_tns']);
                  final r2rNvp = _formatValueString(stage['internal_timing_r2r_nvp']);
                  final i2rWns = _formatTimingValueString(stage['interface_timing_i2r_wns']);
                  final i2rTns = _formatTimingValueString(stage['interface_timing_i2r_tns']);
                  final r2oWns = _formatTimingValueString(stage['interface_timing_r2o_wns']);
                  final r2oTns = _formatTimingValueString(stage['interface_timing_r2o_tns']);
                  final holdWns = _formatTimingValueString(stage['hold_wns']);
                  final holdTns = _formatTimingValueString(stage['hold_tns']);
                  final holdNvp = _formatValueString(stage['hold_nvp']);
                  
                  return TableRow(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                    ),
                    children: [
                      _buildTableCell(
                        (stage['stage']?.toString() ?? '').toUpperCase(),
                        isBold: true,
                        textColor: const Color(0xFF1E293B),
                      ),
                      _buildTableCell(r2rWns, isNA: _isNA(r2rWns)),
                      _buildTableCell(r2rTns, isNA: _isNA(r2rTns)),
                      _buildTableCell(r2rNvp, isNA: _isNA(r2rNvp)),
                      _buildTableCell(i2rWns, isNA: _isNA(i2rWns)),
                      _buildTableCell(i2rTns, isNA: _isNA(i2rTns)),
                      _buildTableCell(r2oWns, isNA: _isNA(r2oWns)),
                      _buildTableCell(r2oTns, isNA: _isNA(r2oTns)),
                      _buildTableCell(holdWns, isNA: _isNA(holdWns)),
                      _buildTableCell(holdTns, isNA: _isNA(holdTns)),
                      _buildTableCell(holdNvp, isNA: _isNA(holdNvp)),
                    ],
                  );
                }).toList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeaderCell(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // Build header cell for customer view with consistent structure
  Widget _buildCustomerHeaderCell(String text, Alignment alignment) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      alignment: alignment,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
        textAlign: alignment == Alignment.centerLeft ? TextAlign.left : TextAlign.center,
      ),
    );
  }

  // Build data cell for customer view with consistent structure matching header
  Widget _buildCustomerDataCell(String text, Alignment alignment, {FontWeight? fontWeight}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      alignment: alignment,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: fontWeight ?? FontWeight.w500,
          color: const Color(0xFF1E293B),
        ),
        textAlign: alignment == Alignment.centerLeft ? TextAlign.left : TextAlign.center,
      ),
    );
  }

  Widget _buildTableCell(String text, {bool isBold = false, Color? textColor, bool isNA = false}) {
    // If text is N/A and no explicit color, use green
    // Otherwise use dark color for white background, or provided color
    final displayColor = isNA && textColor == null 
        ? Colors.green 
        : (textColor ?? const Color(0xFF1E293B)); // Dark text for white background
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
          color: displayColor,
          fontFamily: isBold ? null : 'monospace',
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // Build clickable block name cell for Lead View
  Widget _buildClickableBlockNameCell(String blockName, {required VoidCallback onTap}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onTap,
        child: Text(
          blockName,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF3B82F6),
          ),
        ),
      ),
    );
  }

  String _formatTimingValueString(dynamic value) {
    final num = _parseNumeric(value);
    if (num == null) {
      return 'N/A';
    }
    return num.toStringAsFixed(3);
  }

  String _formatValueString(dynamic value) {
    if (value == null || value.toString() == 'N/A') {
      return 'N/A';
    }
    return value.toString();
  }

  String _formatAreaString(dynamic value) {
    if (value == null || value.toString() == 'N/A') {
      return 'N/A';
    }
    final num = _parseNumeric(value);
    if (num == null) {
      return 'N/A';
    }
    return '${num.toStringAsFixed(2)}';
  }

  String _formatUtilizationString(dynamic value) {
    if (value == null || value.toString() == 'N/A') {
      return 'N/A';
    }
    final num = _parseNumeric(value);
    if (num == null) {
      return 'N/A';
    }
    return '${num.toStringAsFixed(2)}';
  }

  String _formatDRCCountString(dynamic drcViolations) {
    if (drcViolations == null || drcViolations.toString() == 'N/A') {
      return 'N/A';
    }
    final num = _parseNumeric(drcViolations);
    if (num == null) {
      return 'N/A';
    }
    return num.toInt().toString();
  }

  bool _isNA(String value) {
    return value == 'N/A';
  }

  Widget _buildPhysicalMetricsTable(List<Map<String, dynamic>> stages) {
    if (stages.isEmpty) return const SizedBox();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white, // White background
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
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
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.square_foot, size: 22, color: Color(0xFF0F172A)),
                SizedBox(width: 12),
                Text(
                  'Physical Metrics',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              border: TableBorder(
                horizontalInside: BorderSide(color: Colors.grey.shade200, width: 1),
                verticalInside: BorderSide(color: Colors.grey.shade200, width: 1),
                top: BorderSide(color: Colors.grey.shade300, width: 1),
                bottom: BorderSide(color: Colors.grey.shade300, width: 1),
                left: BorderSide(color: Colors.grey.shade300, width: 1),
                right: BorderSide(color: Colors.grey.shade300, width: 1),
              ),
              columnWidths: const {
                0: FixedColumnWidth(120),
                1: FixedColumnWidth(140),
                2: FixedColumnWidth(140),
                3: FixedColumnWidth(120),
                4: FixedColumnWidth(140),
                5: FixedColumnWidth(140),
              },
              children: [
                // Header Row
                TableRow(
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                  ),
                  children: [
                    _buildTableHeaderCell('STAGE'),
                    _buildTableHeaderCell('AREA (MM²)'),
                    _buildTableHeaderCell('UTILIZATION (%)'),
                    _buildTableHeaderCell('DRC COUNT'),
                    _buildTableHeaderCell('METAL DENSITY (%)'),
                    _buildTableHeaderCell('INSTANCE COUNT'),
                  ],
                ),
                // Data Rows
                ...stages.map((stage) {
                  final areaStr = _formatAreaString(stage['area']);
                  final utilStr = _formatUtilizationString(stage['utilization']);
                  final drcCountStr = _formatDRCCountString(stage['drc_violations']);
                  final metalDensityStr = _formatUtilizationString(stage['metal_density_max']);
                  final instCountStr = _formatValueString(stage['inst_count']);
                  
                  // Determine DRC color: red if > 0, green if N/A
                  final drcColor = _isNA(drcCountStr) 
                      ? Colors.green 
                      : (int.tryParse(drcCountStr) ?? 0) > 0 
                          ? Colors.red[700] 
                          : const Color(0xFF1E293B);
                  
                  return TableRow(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                    ),
                    children: [
                      _buildTableCell(
                        (stage['stage']?.toString() ?? '').toUpperCase(),
                        isBold: true,
                        textColor: const Color(0xFF1E293B),
                      ),
                      _buildTableCell(
                        _isNA(areaStr) ? areaStr : '$areaStr',
                        isNA: _isNA(areaStr),
                      ),
                      _buildTableCell(
                        _isNA(utilStr) ? utilStr : '$utilStr',
                        isNA: _isNA(utilStr),
                      ),
                      _buildTableCell(
                        drcCountStr,
                        textColor: drcColor,
                        isNA: _isNA(drcCountStr),
                      ),
                      _buildTableCell(
                        _isNA(metalDensityStr) ? metalDensityStr : '$metalDensityStr',
                        isNA: _isNA(metalDensityStr),
                      ),
                      _buildTableCell(
                        instCountStr,
                        isNA: _isNA(instCountStr),
                      ),
                    ],
                  );
                }).toList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResourceUtilizationTable(List<Map<String, dynamic>> stages) {
    if (stages.isEmpty) return const SizedBox();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white, // White background
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
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
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.memory, size: 22, color: Color(0xFF0F172A)),
                SizedBox(width: 12),
                Text(
                  'Resource Utilization',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              border: TableBorder(
                horizontalInside: BorderSide(color: Colors.grey.shade200, width: 1),
                verticalInside: BorderSide(color: Colors.grey.shade200, width: 1),
                top: BorderSide(color: Colors.grey.shade300, width: 1),
                bottom: BorderSide(color: Colors.grey.shade300, width: 1),
                left: BorderSide(color: Colors.grey.shade300, width: 1),
                right: BorderSide(color: Colors.grey.shade300, width: 1),
              ),
              columnWidths: const {
                0: FixedColumnWidth(120),
                1: FixedColumnWidth(120),
                2: FixedColumnWidth(120),
                3: FixedColumnWidth(100),
                4: FixedColumnWidth(120),
                5: FixedColumnWidth(140),
              },
              children: [
                // Header Row
                TableRow(
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                  ),
                  children: [
                    _buildTableHeaderCell('STAGE'),
                    _buildTableHeaderCell('Runtime'),
                    _buildTableHeaderCell('Memory'),
                    _buildTableHeaderCell('Errors'),
                    _buildTableHeaderCell('Warnings'),
                    _buildTableHeaderCell('Critical Logs'),
                  ],
                ),
                // Data Rows
                ...stages.map((stage) {
                  final runtimeStr = _formatValueString(stage['runtime']);
                  final memoryStr = _formatValueString(stage['memory_usage']);
                  final errors = (stage['log_errors'] as num?)?.toInt() ?? 0;
                  final warnings = (stage['log_warnings'] as num?)?.toInt() ?? 0;
                  final critical = (stage['log_critical'] as num?)?.toInt() ?? 0;
                  
                  final errorStr = errors.toString();
                  final warningStr = warnings.toString();
                  final criticalStr = critical.toString();
                  
                  final errorColor = errors > 0 ? Colors.red[700]! : const Color(0xFF1E293B);
                  final warningColor = warnings > 0 ? Colors.amber[700]! : const Color(0xFF1E293B);
                  final criticalColor = critical > 0 ? Colors.red[900]! : const Color(0xFF1E293B);
                  
                  return TableRow(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                    ),
                    children: [
                      _buildTableCell(
                        (stage['stage']?.toString() ?? '').toUpperCase(),
                        isBold: true,
                        textColor: const Color(0xFF1E293B),
                      ),
                      _buildTableCell(runtimeStr, isNA: _isNA(runtimeStr)),
                      _buildTableCell(memoryStr, isNA: _isNA(memoryStr)),
                      _buildTableCell(
                        errorStr,
                        textColor: errorColor,
                        isBold: errors > 0,
                      ),
                      _buildTableCell(
                        warningStr,
                        textColor: warningColor,
                        isBold: warnings > 0,
                      ),
                      _buildTableCell(
                        criticalStr,
                        textColor: criticalColor,
                        isBold: critical > 0,
                      ),
                    ],
                  );
                }).toList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEngineerChartsSection(List<Map<String, dynamic>> stages) {
    if (stages.isEmpty) return const SizedBox();

    return Column(
      children: [
        // Setup Timing WNS Trend
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.show_chart, size: 20, color: Color(0xFF0F172A)),
                  SizedBox(width: 12),
                  Text(
                    'Setup Timing WNS Trend',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 300,
                child: _buildSetupWNSChart(stages),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Area & Utilization Trend
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.trending_up, size: 20, color: Color(0xFF0F172A)),
                  SizedBox(width: 12),
                  Text(
                    'Area & Utilization Trend',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 300,
                child: _buildAreaUtilizationChart(stages),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Runtime & Memory Usage
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.speed, size: 20, color: Color(0xFF0F172A)),
                  SizedBox(width: 12),
                  Text(
                    'Runtime & Memory Usage',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 300,
                child: _buildRuntimeMemoryChart(stages),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSetupWNSChart(List<Map<String, dynamic>> stages) {
    final spots = <FlSpot>[];
    final stageNames = stages.map((s) => s['stage']?.toString() ?? 'Unknown').toList();
    
    for (int i = 0; i < stages.length; i++) {
      final wns = _parseNumeric(stages[i]['internal_timing_r2r_wns']);
      if (wns != null) {
        spots.add(FlSpot(i.toDouble(), wns.toDouble()));
      }
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFFE2E8F0), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(2),
                  style: const TextStyle(fontSize: 9, color: Color(0xFF64748B)),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx >= 0 && idx < stageNames.length) {
                  String name = stageNames[idx].toUpperCase();
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
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: true, border: Border.all(color: const Color(0xFFE2E8F0))),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: const Color(0xFF3B82F6),
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: Color(0xFF3B82F6).withOpacity(0.1)),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: Colors.blueGrey.shade800,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final idx = spot.x.toInt();
                final stageName = idx >= 0 && idx < stageNames.length 
                    ? stageNames[idx].toUpperCase()
                    : 'Unknown';
                return LineTooltipItem(
                  '$stageName\nWNS: ${spot.y.toStringAsFixed(3)}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                );
              }).toList();
            },
          ),
        ),
        minY: spots.isEmpty ? 0.0 : (spots.map((p) => p.y).reduce((a, b) => a < b ? a : b) - 0.1).toDouble(),
        maxY: spots.isEmpty ? 1.0 : (spots.map((p) => p.y).reduce((a, b) => a > b ? a : b) + 0.1).toDouble(),
      ),
    );
  }

  Widget _buildAreaUtilizationChart(List<Map<String, dynamic>> stages) {
    final areaSpots = <FlSpot>[];
    final utilSpots = <FlSpot>[];
    final stageNames = stages.map((s) => s['stage']?.toString() ?? 'Unknown').toList();
    
    for (int i = 0; i < stages.length; i++) {
      final area = _parseNumeric(stages[i]['area']);
      final util = _parseNumeric(stages[i]['utilization']);
      if (area != null) {
        areaSpots.add(FlSpot(i.toDouble(), area.toDouble()));
      }
      if (util != null) {
        utilSpots.add(FlSpot(i.toDouble(), util.toDouble()));
      }
    }

    final allSpots = [...areaSpots, ...utilSpots];
    final minY = allSpots.isEmpty ? 0 : (allSpots.map((p) => p.y).reduce((a, b) => a < b ? a : b) - 0.1);
    final maxY = allSpots.isEmpty ? 1 : (allSpots.map((p) => p.y).reduce((a, b) => a > b ? a : b) + 0.1);

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFFE2E8F0), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 9, color: Color(0xFF64748B)),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx >= 0 && idx < stageNames.length) {
                  String name = stageNames[idx].toUpperCase();
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
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: true, border: Border.all(color: const Color(0xFFE2E8F0))),
        lineBarsData: [
          LineChartBarData(
            spots: areaSpots,
            isCurved: true,
            color: const Color(0xFF10B981),
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: Color(0xFF10B981).withOpacity(0.1)),
          ),
          if (utilSpots.isNotEmpty)
            LineChartBarData(
              spots: utilSpots,
              isCurved: true,
              color: const Color(0xFFF59E0B),
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: true, color: Color(0xFFF59E0B).withOpacity(0.1)),
            ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: Colors.blueGrey.shade800,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final idx = spot.x.toInt();
                final stageName = idx >= 0 && idx < stageNames.length 
                    ? stageNames[idx].toUpperCase()
                    : 'Unknown';
                final label = areaSpots.any((p) => p.x == spot.x) ? 'Area' : 'Utilization';
                return LineTooltipItem(
                  '$stageName\n$label: ${spot.y.toStringAsFixed(2)}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                );
              }).toList();
            },
          ),
        ),
        minY: minY.toDouble(),
        maxY: maxY.toDouble(),
      ),
    );
  }

  Widget _buildRuntimeMemoryChart(List<Map<String, dynamic>> stages) {
    // Parse runtime to minutes for chart
    final runtimeSpots = <FlSpot>[];
    final memorySpots = <FlSpot>[];
    final stageNames = stages.map((s) => s['stage']?.toString() ?? 'Unknown').toList();
    
    for (int i = 0; i < stages.length; i++) {
      final runtimeStr = stages[i]['runtime']?.toString() ?? '';
      final runtimeMinutes = _parseRuntimeToMinutes(runtimeStr);
      if (runtimeMinutes != null) {
        runtimeSpots.add(FlSpot(i.toDouble(), runtimeMinutes));
      }
      
      final memoryStr = stages[i]['memory_usage']?.toString() ?? '';
      final memoryMB = _parseMemoryToMB(memoryStr);
      if (memoryMB != null) {
        memorySpots.add(FlSpot(i.toDouble(), memoryMB));
      }
    }

    final allSpots = [...runtimeSpots, ...memorySpots];
    final minY = allSpots.isEmpty ? 0 : (allSpots.map((p) => p.y).reduce((a, b) => a < b ? a : b) - 0.1);
    final maxY = allSpots.isEmpty ? 1 : (allSpots.map((p) => p.y).reduce((a, b) => a > b ? a : b) + 0.1);

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFFE2E8F0), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 9, color: Color(0xFF64748B)),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx >= 0 && idx < stageNames.length) {
                  String name = stageNames[idx].toUpperCase();
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
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: true, border: Border.all(color: const Color(0xFFE2E8F0))),
        lineBarsData: [
          LineChartBarData(
            spots: runtimeSpots,
            isCurved: true,
            color: const Color(0xFF8B5CF6),
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: Color(0xFF8B5CF6).withOpacity(0.1)),
          ),
          if (memorySpots.isNotEmpty)
            LineChartBarData(
              spots: memorySpots,
              isCurved: true,
              color: const Color(0xFFEF4444),
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: true, color: Color(0xFFEF4444).withOpacity(0.1)),
            ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: Colors.blueGrey.shade800,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final idx = spot.x.toInt();
                final stageName = idx >= 0 && idx < stageNames.length 
                    ? stageNames[idx].toUpperCase()
                    : 'Unknown';
                final label = runtimeSpots.any((p) => p.x == spot.x) ? 'Runtime (min)' : 'Memory (MB)';
                return LineTooltipItem(
                  '$stageName\n$label: ${spot.y.toStringAsFixed(2)}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                );
              }).toList();
            },
          ),
        ),
        minY: minY.toDouble(),
        maxY: maxY.toDouble(),
      ),
    );
  }

  double? _parseRuntimeToMinutes(String runtime) {
    if (runtime == 'N/A' || runtime.isEmpty) return null;
    try {
      // Format: "HH:MM:SS"
      final parts = runtime.split(':');
      if (parts.length == 3) {
        final hours = int.parse(parts[0]);
        final minutes = int.parse(parts[1]);
        final seconds = int.parse(parts[2]);
        return hours * 60.0 + minutes + seconds / 60.0;
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  double? _parseMemoryToMB(String memory) {
    if (memory == 'N/A' || memory.isEmpty) return null;
    try {
      // Format: "1,046M" or similar
      final cleaned = memory.replaceAll(',', '').replaceAll('M', '').replaceAll('G', '');
      final value = double.parse(cleaned);
      if (memory.contains('G')) {
        return value * 1024; // Convert GB to MB
      }
      return value;
    } catch (e) {
      return null;
    }
  }

  Widget _formatTimingValue(dynamic value) {
    final num = _parseNumeric(value);
    if (num == null) {
      return const Text('N/A', style: TextStyle(color: Colors.grey));
    }
    return Text(
      num.toStringAsFixed(3),
      style: TextStyle(
        color: num < 0 ? Colors.red[700] : Colors.green[700],
        fontWeight: FontWeight.w600,
        fontFamily: 'monospace',
      ),
    );
  }

  Widget _formatValue(dynamic value) {
    if (value == null || value.toString() == 'N/A') {
      return const Text('N/A', style: TextStyle(color: Colors.grey));
    }
    return Text(
      value.toString(),
      style: const TextStyle(
        fontWeight: FontWeight.w500,
        fontFamily: 'monospace',
      ),
    );
  }

  Widget _buildMetricsGraphSection(List<Map<String, dynamic>> stages) {
    if (stages.isEmpty) return const SizedBox();

    final allMetricGroups = ['INTERNAL (R2R)', 'INTERFACE I2R', 'INTERFACE R2O', 'INTERFACE I2O', 'HOLD'];
    final allMetricTypes = ['WNS', 'TNS', 'NVP'];
    final allChartTypes = ['Timing Metrics', 'Setup WNS Trend', 'Area & Utilization', 'Runtime & Memory'];

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
                    'Metrics Visualization',
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
          // Chart Type Selector
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SELECT CHART TYPE',
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
                children: allChartTypes.map((chartType) {
                  final isSelected = _selectedChartType == chartType;
                  return FilterChip(
                    label: Text(chartType),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedChartType = chartType;
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
          // Conditional rendering based on chart type
          if (_selectedChartType == 'Timing Metrics') ...[
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
          ] else if (_selectedChartType == 'Setup WNS Trend') ...[
            const SizedBox(height: 24),
            SizedBox(
              height: 300,
              child: _buildSetupWNSChart(stages),
            ),
          ] else if (_selectedChartType == 'Area & Utilization') ...[
            const SizedBox(height: 24),
            SizedBox(
              height: 300,
              child: _buildAreaUtilizationChart(stages),
            ),
          ] else if (_selectedChartType == 'Runtime & Memory') ...[
            const SizedBox(height: 24),
            SizedBox(
              height: 300,
              child: _buildRuntimeMemoryChart(stages),
            ),
          ],
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

  // Lead View - Comprehensive dashboard with KPI cards and block summary table
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

    // Get all stages for the project to calculate KPIs
    final allProjectStages = _getAllStagesForProject();
    
    // Calculate KPI metrics
    final kpiMetrics = _calculateLeadKPIMetrics(allProjectStages);
    
    // Get block summary data for the table
    final blockSummaryData = _getBlockSummaryData(allProjectStages);
    
    // Load QMS data if not already loaded (async, will update UI when ready)
    if (_blockNameToId.isEmpty && _selectedProject != null) {
      // Load QMS data asynchronously without blocking UI
      _loadQmsDataForBlocks(blockSummaryData).catchError((error) {
        // Silently fail - QMS data won't be available but UI still works
        print('Failed to load QMS data: $error');
      });
    }
    
    // Apply filters
    final filteredBlockSummary = _applyLeadFilters(blockSummaryData);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 5 KPI Cards
        _buildLeadKPICards(kpiMetrics),
        const SizedBox(height: 24),
        
        // Filter Section
        _buildLeadFilterSection(),
        const SizedBox(height: 24),
        
        // Block Summary Table
        _buildLeadBlockSummaryTable(filteredBlockSummary),
      ],
    );
  }
  
  // Calculate Lead View KPI metrics
  Map<String, dynamic> _calculateLeadKPIMetrics(List<Map<String, dynamic>> allStages) {
    // Get unique blocks
    final blocks = <String>{};
    final stageDistribution = <String, int>{};
    int timingCriticalCount = 0;
    int congestionIssuesCount = 0;
    int highRuntimeCount = 0;
    
    // Track latest stage for each block
    final blockLatestStages = <String, Map<String, dynamic>>{};
    final stageOrder = ['syn', 'init', 'floorplan', 'place', 'cts', 'postcts', 'route', 'postroute'];
    
    for (var stage in allStages) {
      final blockName = stage['block_name']?.toString() ?? '';
      if (blockName.isEmpty) continue;
      
      blocks.add(blockName);
      
      // Track stage distribution
      final stageName = stage['stage']?.toString().toLowerCase() ?? '';
      stageDistribution[stageName] = (stageDistribution[stageName] ?? 0) + 1;
      
      // Track latest stage per block
      if (!blockLatestStages.containsKey(blockName)) {
        blockLatestStages[blockName] = stage;
      } else {
        final currentStage = blockLatestStages[blockName]!;
        final currentStageName = currentStage['stage']?.toString().toLowerCase() ?? '';
        final currentIndex = stageOrder.indexOf(currentStageName);
        final newIndex = stageOrder.indexOf(stageName);
        
        if (newIndex > currentIndex) {
          blockLatestStages[blockName] = stage;
        }
      }
    }
    
    // Analyze latest stages for each block
    for (var latestStage in blockLatestStages.values) {
      // Check for timing-critical (negative WNS)
      final wns = _parseNumeric(latestStage['internal_timing_r2r_wns']) ?? 
                   _parseNumeric(latestStage['setup_wns']);
      if (wns != null && wns < 0) {
        timingCriticalCount++;
      }
      
      // Check for congestion issues (DRC violations > 0)
      final drc = _parseNumeric(latestStage['drc_violations'])?.toInt() ?? 0;
      if (drc > 0) {
        congestionIssuesCount++;
      }
      
      // Check for high runtime (runtime > 24 hours = 86400 seconds, or if it's a large number)
      final runtime = _parseNumeric(latestStage['runtime']);
      if (runtime != null && runtime > 86400) {
        highRuntimeCount++;
      }
    }
    
    return {
      'totalBlocks': blocks.length,
      'stageDistribution': stageDistribution,
      'timingCriticalCount': timingCriticalCount,
      'congestionIssuesCount': congestionIssuesCount,
      'highRuntimeCount': highRuntimeCount,
    };
  }
  
  // Get block summary data for the table
  List<Map<String, dynamic>> _getBlockSummaryData(List<Map<String, dynamic>> allStages) {
    final blockDataMap = <String, Map<String, dynamic>>{};
    final stageOrder = ['syn', 'init', 'floorplan', 'place', 'cts', 'postcts', 'route', 'postroute'];
    
    // Group stages by block
    for (var stage in allStages) {
      final blockName = stage['block_name']?.toString() ?? '';
      if (blockName.isEmpty) continue;
      
      if (!blockDataMap.containsKey(blockName)) {
        blockDataMap[blockName] = {
          'block_name': blockName,
          'engineer': 'TBD', // Placeholder - can be enhanced with actual assignment data
          'latest_stage': '',
          'latest_stage_status': 'unknown',
          'latest_stage_index': -1,
          'wns': null,
          'tns': null,
          'area': null,
          'utilization': null,
          'drc_violations': 0,
          'runtime': null,
          'stages': <Map<String, dynamic>>[],
        };
      }
      
      blockDataMap[blockName]!['stages']!.add(stage);
    }
    
    // Process each block to find latest stage and calculate metrics
    final blockSummaryList = <Map<String, dynamic>>[];
    
    for (var blockEntry in blockDataMap.entries) {
      final blockName = blockEntry.key;
      final blockData = Map<String, dynamic>.from(blockEntry.value);
      final stages = blockData['stages'] as List<Map<String, dynamic>>;
      
      // Find latest stage
      Map<String, dynamic>? latestStage;
      int latestIndex = -1;
      
      for (var stage in stages) {
        final stageName = stage['stage']?.toString().toLowerCase() ?? '';
        final stageIndex = stageOrder.indexOf(stageName);
        
        if (stageIndex > latestIndex) {
          latestIndex = stageIndex;
          latestStage = stage;
        }
      }
      
      if (latestStage != null) {
        blockData['latest_stage'] = latestStage['stage']?.toString().toUpperCase() ?? '';
        blockData['latest_stage_status'] = latestStage['run_status']?.toString().toLowerCase() ?? 'unknown';
        blockData['latest_stage_index'] = latestIndex;
        
        // Extract key metrics from latest stage
        blockData['wns'] = _parseNumeric(latestStage['internal_timing_r2r_wns']) ?? 
                          _parseNumeric(latestStage['setup_wns']);
        blockData['tns'] = _parseNumeric(latestStage['internal_timing_r2r_tns']) ?? 
                          _parseNumeric(latestStage['setup_tns']);
        blockData['area'] = _parseNumeric(latestStage['area']);
        blockData['utilization'] = latestStage['utilization']?.toString();
        blockData['drc_violations'] = _parseNumeric(latestStage['drc_violations'])?.toInt() ?? 0;
        blockData['runtime'] = _parseNumeric(latestStage['runtime']);
        
        // Calculate trend (compare with previous stage if available)
        if (latestIndex > 0) {
          final prevStageName = stageOrder[latestIndex - 1];
          final prevStage = stages.firstWhere(
            (s) => s['stage']?.toString().toLowerCase() == prevStageName,
            orElse: () => <String, dynamic>{},
          );
          
          if (prevStage.isNotEmpty) {
            final prevWns = _parseNumeric(prevStage['internal_timing_r2r_wns']) ?? 
                          _parseNumeric(prevStage['setup_wns']);
            final currWns = blockData['wns'];
            
            if (prevWns != null && currWns != null) {
              blockData['wns_trend'] = currWns > prevWns ? 'up' : (currWns < prevWns ? 'down' : 'neutral');
            } else {
              blockData['wns_trend'] = 'neutral';
            }
          } else {
            blockData['wns_trend'] = 'neutral';
          }
        } else {
          blockData['wns_trend'] = 'neutral';
        }
      }
      
      blockSummaryList.add(blockData);
    }
    
    // Sort by block name
    blockSummaryList.sort((a, b) => 
      (a['block_name'] as String).compareTo(b['block_name'] as String));
    
    return blockSummaryList;
  }
  
  // Load block IDs and QMS checklist data
  Future<void> _loadQmsDataForBlocks(List<Map<String, dynamic>> blockSummary) async {
    if (_selectedProject == null) return;
    
    try {
      final token = ref.read(authProvider).token;
      if (token == null) return;
      
      // Get project ID
      final projects = await _apiService.getProjects(token: token);
      Map<String, dynamic>? project;
      try {
        project = projects.firstWhere(
          (p) => (p['name']?.toString().toLowerCase() ?? '') == _selectedProject!.toLowerCase(),
        ) as Map<String, dynamic>?;
      } catch (e) {
        return;
      }
      
      if (project == null || project['id'] == null) return;
      
      final projectId = project['id'] as int;
      
      // Get blocks for this project
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
      
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/projects/$projectId/blocks'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final blocks = data is Map && data['data'] != null ? data['data'] : (data is List ? data : []);
        if (blocks is List) {
          final blockMap = <String, int>{};
          for (var block in blocks) {
            final blockName = block['block_name']?.toString();
            final blockId = block['id'];
            if (blockName != null && blockId != null) {
              blockMap[blockName] = blockId is int ? blockId : int.tryParse(blockId.toString()) ?? 0;
            }
          }
          
          if (mounted) {
            setState(() {
              _blockNameToId = blockMap;
            });
          }
          
          // Load QMS checklist data for each block
          final qmsDataMap = <String, Map<String, dynamic>>{};
          for (var blockEntry in blockMap.entries) {
            final blockName = blockEntry.key;
            final blockId = blockEntry.value;
            
            try {
              final checklists = await _qmsService.getChecklistsForBlock(blockId, token: token);
              if (checklists.isNotEmpty) {
                // Store all checklists for this block
                final checklistList = checklists.map((checklist) => {
                  'name': checklist['name'] ?? 'N/A',
                  'status': checklist['status'] ?? 'draft',
                  'id': checklist['id'],
                }).toList();
                
                qmsDataMap[blockName] = {
                  'checklists': checklistList,
                  'block_id': blockId,
                };
              }
            } catch (e) {
              // Silently fail for blocks without QMS data
            }
          }
          
          if (mounted) {
            setState(() {
              _blockQmsData = qmsDataMap;
            });
          }
        }
      }
    } catch (e) {
      // Silently fail - QMS data won't be available
      print('Failed to load QMS data: $e');
    }
  }
  
  // Apply filters to block summary data
  List<Map<String, dynamic>> _applyLeadFilters(List<Map<String, dynamic>> blockSummary) {
    return blockSummary.where((block) {
      // Stage filter
      if (_leadStageFilter.isNotEmpty) {
        final latestStage = block['latest_stage']?.toString().toLowerCase() ?? '';
        if (latestStage != _leadStageFilter.toLowerCase()) {
          return false;
        }
      }
      
      // Status filter
      if (_leadStatusFilter.isNotEmpty) {
        final status = block['latest_stage_status']?.toString().toLowerCase() ?? '';
        if (status != _leadStatusFilter.toLowerCase()) {
          return false;
        }
      }
      
      return true;
    }).toList();
  }
  
  // Build 5 KPI Cards for Lead View
  Widget _buildLeadKPICards(Map<String, dynamic> metrics) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 768;
        final cardWidth = isMobile ? constraints.maxWidth : (constraints.maxWidth - 80) / 5;
        
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            // KPI 1: Total Blocks
            SizedBox(
              width: isMobile ? constraints.maxWidth : cardWidth,
              child: _buildKPICard(
                title: 'Total Blocks',
                icon: Icons.view_module,
                color: const Color(0xFF3B82F6),
                children: [
                  _buildKPIValue(
                    metrics['totalBlocks']?.toString() ?? '0',
                    subtitle: 'Blocks in Project',
                  ),
                ],
              ),
            ),
            
            // KPI 2: Stage Distribution
            SizedBox(
              width: isMobile ? constraints.maxWidth : cardWidth,
              child: _buildKPICard(
                title: 'Stage Distribution',
                icon: Icons.timeline,
                color: const Color(0xFF10B981),
                children: [
                  _buildKPIValue(
                    (metrics['stageDistribution'] as Map<String, int>? ?? {}).length.toString(),
                    subtitle: 'Active Stages',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatStageDistribution(metrics['stageDistribution'] as Map<String, int>? ?? {}),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            
            // KPI 3: Timing-Critical Blocks
            SizedBox(
              width: isMobile ? constraints.maxWidth : cardWidth,
              child: _buildKPICard(
                title: 'Timing-Critical Blocks',
                icon: Icons.warning_amber_rounded,
                color: const Color(0xFFF59E0B),
                children: [
                  _buildKPIValue(
                    metrics['timingCriticalCount']?.toString() ?? '0',
                    subtitle: 'Blocks with Negative WNS',
                  ),
                ],
              ),
            ),
            
            // KPI 4: Congestion Issues
            SizedBox(
              width: isMobile ? constraints.maxWidth : cardWidth,
              child: _buildKPICard(
                title: 'Congestion Issues',
                icon: Icons.error_outline,
                color: const Color(0xFFEF4444),
                children: [
                  _buildKPIValue(
                    metrics['congestionIssuesCount']?.toString() ?? '0',
                    subtitle: 'Blocks with DRC Violations',
                  ),
                ],
              ),
            ),
            
            // KPI 5: High Runtime Blocks
            SizedBox(
              width: isMobile ? constraints.maxWidth : cardWidth,
              child: _buildKPICard(
                title: 'High Runtime Blocks',
                icon: Icons.timer_off,
                color: const Color(0xFF8B5CF6),
                children: [
                  _buildKPIValue(
                    metrics['highRuntimeCount']?.toString() ?? '0',
                    subtitle: 'Blocks > 24h Runtime',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
  
  // Format stage distribution for display
  String _formatStageDistribution(Map<String, int> distribution) {
    if (distribution.isEmpty) return 'No stages';
    
    final sorted = distribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return sorted.take(3).map((e) => 
      '${e.key.toUpperCase()}: ${e.value}'
    ).join(', ');
  }
  
  // Build filter section for Lead View
  Widget _buildLeadFilterSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Text(
            'FILTER BY:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF94A3B8),
              letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 24),
          
          // Stage Filter
            Expanded(
            child: Row(
              children: [
                const Text(
                  'Stage:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: DropdownButton<String>(
                      value: _leadStageFilter.isEmpty ? null : _leadStageFilter,
                      isExpanded: true,
                      underline: const SizedBox(),
                      hint: const Text(
                        'All Stages',
                        style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('All Stages', style: TextStyle(fontSize: 13)),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'syn',
                          child: Text('Synthesis', style: TextStyle(fontSize: 13)),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'place',
                          child: Text('Placement', style: TextStyle(fontSize: 13)),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'cts',
                          child: Text('CTS', style: TextStyle(fontSize: 13)),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'route',
                          child: Text('Routing', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _leadStageFilter = value ?? '';
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          
            const SizedBox(width: 24),
          
          // Status Filter
            Expanded(
            child: Row(
              children: [
                const Text(
                  'Status:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: DropdownButton<String>(
                      value: _leadStatusFilter.isEmpty ? null : _leadStatusFilter,
                      isExpanded: true,
                      underline: const SizedBox(),
                      hint: const Text(
                        'All Status',
                        style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('All Status', style: TextStyle(fontSize: 13)),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'completed',
                          child: Text('Completed', style: TextStyle(fontSize: 13)),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'in_progress',
                          child: Text('In Progress', style: TextStyle(fontSize: 13)),
                        ),
                        const DropdownMenuItem<String>(
                          value: 'fail',
                          child: Text('Failed', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _leadStatusFilter = value ?? '';
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // Build comprehensive block summary table
  Widget _buildLeadBlockSummaryTable(List<Map<String, dynamic>> blockSummary) {
    if (blockSummary.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(48),
            decoration: BoxDecoration(
              color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Center(
          child: Text(
            'No blocks found matching the current filters',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF64748B),
            ),
          ),
        ),
      );
    }
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          // Table Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.table_chart_outlined, size: 20, color: Color(0xFF0F172A)),
                      SizedBox(width: 12),
                      Text(
                  'Block Summary',
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
          
          // Table
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: Table(
                columnWidths: const {
                  0: FixedColumnWidth(150), // Block Name
                  1: FixedColumnWidth(120), // Engineer
                  2: FixedColumnWidth(100), // Latest Stage
                  3: FixedColumnWidth(100), // Status
                  4: FixedColumnWidth(100), // WNS
                  5: FixedColumnWidth(100), // TNS
                  6: FixedColumnWidth(100), // Area
                  7: FixedColumnWidth(100), // Utilization
                  8: FixedColumnWidth(100), // DRC
                  9: FixedColumnWidth(100), // Runtime
                  10: FixedColumnWidth(80), // Trend
                  11: FixedColumnWidth(350), // Checklist (wider for long names and statuses)
                },
                border: TableBorder(
                  horizontalInside: BorderSide(color: Colors.grey.shade200),
                  verticalInside: BorderSide(color: Colors.grey.shade200),
                ),
                children: [
                  // Header Row
                  TableRow(
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F172A),
                    ),
                    children: [
                      _buildTableHeaderCell('Block Name'),
                      _buildTableHeaderCell('Engineer'),
                      _buildTableHeaderCell('Latest Stage'),
                      _buildTableHeaderCell('Status'),
                      _buildTableHeaderCell('WNS'),
                      _buildTableHeaderCell('TNS'),
                      _buildTableHeaderCell('Area'),
                      _buildTableHeaderCell('Utilization'),
                      _buildTableHeaderCell('DRC'),
                      _buildTableHeaderCell('Runtime'),
                      _buildTableHeaderCell('Trend'),
                      _buildChecklistHeaderCell(),
                    ],
                  ),
                  
                  // Data Rows
                  ...blockSummary.map((block) {
                    final wns = block['wns'];
                    final tns = block['tns'];
                    final area = block['area'];
                    final utilization = block['utilization']?.toString() ?? 'N/A';
                    final drc = block['drc_violations'] as int? ?? 0;
                    final runtime = block['runtime'];
                    final status = block['latest_stage_status']?.toString().toLowerCase() ?? 'unknown';
                    final trend = block['wns_trend']?.toString() ?? 'neutral';
                    
                    return TableRow(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                      ),
                      children: [
                        _buildClickableBlockNameCell(
                          block['block_name']?.toString() ?? 'N/A',
                          onTap: () {
                            final blockName = block['block_name']?.toString();
                            if (blockName != null && blockName.isNotEmpty) {
                              _updateCascadingFilters(b: blockName);
                              setState(() {
                                _viewType = 'engineer';
                              });
                            }
                          },
                        ),
                        _buildTableCell(block['engineer']?.toString() ?? 'TBD'),
                        _buildTableCell(block['latest_stage']?.toString() ?? 'N/A'),
                        _buildLeadStatusCell(status),
                        _buildTableCell(
                          wns != null ? wns.toStringAsFixed(3) : 'N/A',
                          textColor: wns != null && wns < 0 ? Colors.red[700] : null,
                          isBold: wns != null && wns < 0,
                        ),
                        _buildTableCell(tns != null ? tns.toStringAsFixed(2) : 'N/A'),
                        _buildTableCell(area != null ? area.toStringAsFixed(2) : 'N/A'),
                        _buildTableCell(utilization),
                        _buildTableCell(
                          drc.toString(),
                          textColor: drc > 0 ? Colors.red[700] : null,
                          isBold: drc > 0,
                        ),
                        _buildTableCell(
                          runtime != null ? _formatRuntime(runtime) : 'N/A',
                        ),
                        _buildTrendCell(trend),
                        _buildQmsChecklistCell(block),
                      ],
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // Build status cell with badge for Lead View
  Widget _buildLeadStatusCell(String status) {
    Color bgColor;
    Color textColor;
    String displayText;
    
    switch (status.toLowerCase()) {
      case 'completed':
      case 'pass':
        bgColor = const Color(0xFF10B981).withOpacity(0.1);
        textColor = const Color(0xFF10B981);
        displayText = 'Completed';
        break;
      case 'in_progress':
      case 'continue_with_error':
        bgColor = const Color(0xFFF59E0B).withOpacity(0.1);
        textColor = const Color(0xFFF59E0B);
        displayText = 'In Progress';
        break;
      case 'fail':
      case 'failed':
        bgColor = const Color(0xFFEF4444).withOpacity(0.1);
        textColor = const Color(0xFFEF4444);
        displayText = 'Failed';
        break;
      default:
        bgColor = const Color(0xFF94A3B8).withOpacity(0.1);
        textColor = const Color(0xFF94A3B8);
        displayText = 'Unknown';
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: textColor.withOpacity(0.3)),
      ),
      child: Text(
        displayText,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
  
  // Build checklist header cell with sub-headers
  Widget _buildChecklistHeaderCell() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Checklist',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 1,
                child: Text(
                  'Name',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Center(
                  child: Text(
                    'Status',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  // Build QMS checklist cell with all checklist names and statuses
  Widget _buildQmsChecklistCell(Map<String, dynamic> block) {
    final blockName = block['block_name']?.toString() ?? '';
    final qmsData = _blockQmsData[blockName];
    
    if (qmsData == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        alignment: Alignment.centerLeft,
        child: const Text(
          'N/A',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF94A3B8),
          ),
        ),
      );
    }
    
    final checklists = qmsData['checklists'] as List<dynamic>?;
    final blockId = qmsData['block_id'] as int?;
    
    if (checklists == null || checklists.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        alignment: Alignment.centerLeft,
        child: const Text(
          'N/A',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF94A3B8),
          ),
        ),
      );
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: blockId != null ? () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => QmsDashboardScreen(blockId: blockId),
            ),
          );
        } : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: checklists.map<Widget>((checklist) {
            final checklistName = checklist['name']?.toString() ?? 'N/A';
            final checklistStatus = checklist['status']?.toString() ?? 'draft';
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Name column - 50% width
                  Expanded(
                    flex: 1,
                    child: Text(
                      checklistName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: blockId != null ? const Color(0xFF3B82F6) : const Color(0xFF1E293B),
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Status column - 50% width with center alignment
                  Expanded(
                    flex: 1,
                    child: Center(
                      child: QmsStatusBadge(status: checklistStatus),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
  
  // Build trend indicator cell
  Widget _buildTrendCell(String trend) {
    IconData icon;
    Color color;
    
    switch (trend) {
      case 'up':
        icon = Icons.trending_up;
        color = const Color(0xFF10B981);
        break;
      case 'down':
        icon = Icons.trending_down;
        color = const Color(0xFFEF4444);
        break;
      default:
        icon = Icons.trending_flat;
        color = const Color(0xFF94A3B8);
    }
    
    return Container(
      padding: const EdgeInsets.all(8),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: color),
    );
  }
  
  // Format runtime for display
  String _formatRuntime(double seconds) {
    if (seconds < 60) {
      return '${seconds.toStringAsFixed(0)}s';
    } else if (seconds < 3600) {
      return '${(seconds / 60).toStringAsFixed(1)}m';
    } else if (seconds < 86400) {
      return '${(seconds / 3600).toStringAsFixed(1)}h';
    } else {
      return '${(seconds / 86400).toStringAsFixed(1)}d';
    }
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
  
  // Get only the latest stage for each block (for lead view)
  List<Map<String, dynamic>> _getLatestStagesForBlock() {
    if (_selectedProject == null || _selectedBlock == null) return [];
    
    final stageOrder = ['syn', 'init', 'floorplan', 'place', 'cts', 'postcts', 'route', 'postroute'];
    final latestStages = <Map<String, dynamic>>[];
    
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
          
          // Find the latest stage for this experiment
          Map<String, dynamic>? latestStage;
          int latestStageIndex = -1;
          
          for (var stageData in stagesMap.values) {
            if (stageData is! Map) continue;
            
            final stage = Map<String, dynamic>.from(stageData);
            final stageName = stage['stage']?.toString().toLowerCase() ?? '';
            final stageIndex = stageOrder.indexOf(stageName);
            
            // If this stage is later in the order, it's the latest so far
            if (stageIndex > latestStageIndex) {
              latestStageIndex = stageIndex;
              latestStage = stage;
            }
          }
          
          // Add the latest stage with context
          if (latestStage != null) {
            final stageWithContext = Map<String, dynamic>.from(latestStage);
            stageWithContext['block_name'] = _selectedBlock;
            stageWithContext['rtl_tag'] = rtlTag;
            stageWithContext['experiment'] = experiment;
            latestStages.add(stageWithContext);
          }
        }
      }
    } catch (e) {
      print('Error getting latest stages for block: $e');
    }
    
    return latestStages;
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

    // Calculate executive summary metrics
    final executiveMetrics = _calculateExecutiveMetrics(allProjectStages, blockStatuses, criticalBlocks);
    
    // Calculate project overview
    final projectOverview = _calculateProjectOverview(allProjectStages, blockStatuses);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Executive Summary Metrics - KPI Cards
        _buildExecutiveSummaryMetrics(executiveMetrics),
        const SizedBox(height: 24),
        
        // Project-Level Overview
        _buildProjectLevelOverview(projectOverview, blockStatuses),
        const SizedBox(height: 24),
        
        // Critical Issues Dashboard
        _buildCriticalIssuesDashboard(criticalBlocks, allProjectStages),
        const SizedBox(height: 24),
        
        // Budget and Timeline Tracking
        _buildBudgetAndTimelineTracking(allProjectStages, projectOverview),
        const SizedBox(height: 24),
        
        // Additional Charts Row
        Row(
          children: [
            Expanded(
              child: _buildManagerCard(
                'Block Status Distribution',
                _buildBlockStatusHistogram(blockStatuses),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _buildManagerCard(
                'Critical Blocks Analysis',
                _buildCriticalBlocksChart(criticalBlocks),
              ),
            ),
          ],
        ),
        if (allProjectStages.isNotEmpty && currentStage != null) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _buildManagerCard('Current Stage', _buildCurrentStageCard(currentStage))),
              const SizedBox(width: 24),
              Expanded(child: _buildManagerCard('Block Health Index', _buildHealthIndexCard(healthIndex))),
            ],
          ),
        ],
      ],
    );
  }

  // Management view state
  bool _isLoadingManagementData = false;
  List<dynamic> _managementProjects = [];

  // CAD engineer view state
  bool _isLoadingCadStatus = false;
  Map<String, dynamic>? _cadStatus;
  String? _cadStatusProject;
  int _cadTabIndex = 0; // 0 for Tasks, 1 for Issues

  Future<void> _loadManagementData() async {
    setState(() {
      _isLoadingManagementData = true;
    });

    try {
      final authState = ref.read(authProvider);
      final token = authState.token;
      
      final response = await _apiService.getManagementStatus(token: token);
      
      if (response['success'] == true) {
        setState(() {
          _managementProjects = List<dynamic>.from(response['projects'] ?? []);
          _isLoadingManagementData = false;
        });
      } else {
        setState(() {
          _isLoadingManagementData = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingManagementData = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading management data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildManagementView() {
    // Load data on first view
    if (_managementProjects.isEmpty && !_isLoadingManagementData) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadManagementData();
      });
    }

    if (_isLoadingManagementData) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Loading project status...',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    if (_managementProjects.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            'No projects found',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Wrap(
          spacing: 24,
          runSpacing: 24,
          children: _managementProjects.map<Widget>((project) {
            return _buildProjectCard(project as Map<String, dynamic>);
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _loadCadStatusForProject(String projectIdentifier) async {
    setState(() {
      _isLoadingCadStatus = true;
      _cadStatusProject = projectIdentifier;
    });

    try {
      final authState = ref.read(authProvider);
      final token = authState.token;

      final response = await _apiService.getCadStatus(
        projectIdentifier: projectIdentifier,
        token: token,
      );

      if (response['success'] == true) {
        setState(() {
          _cadStatus = Map<String, dynamic>.from(response['data'] ?? {});
          _isLoadingCadStatus = false;
        });
      } else {
        setState(() {
          _isLoadingCadStatus = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingCadStatus = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading CAD status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildCadView() {
    if (_selectedProject == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            'Please select a project to view CAD status.',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }

    // Auto-load CAD status for the selected project
    if (!_isLoadingCadStatus &&
        (_cadStatus == null || _cadStatusProject != _selectedProject)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedProject != null) {
          _loadCadStatusForProject(_selectedProject!);
        }
      });
    }

    if (_isLoadingCadStatus || _cadStatus == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Loading CAD status...',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    final tasks = _cadStatus?['tasks'] as Map<String, dynamic>? ?? {};
    final issues = _cadStatus?['issues'] as Map<String, dynamic>? ?? {};
    // tasksList and issuesList removed - not needed for now

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CAD Engineer View - ${_cadStatus?['projectName'] ?? _selectedProject}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildCadSummaryCard(
                  title: 'Tasks',
                  total: tasks['total'] ?? 0,
                  todo: tasks['todo'] ?? 0,
                  inProgress: tasks['in_progress'] ?? 0,
                  completed: tasks['completed'] ?? 0,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildCadSummaryCard(
                  title: 'Issues',
                  total: issues['total'] ?? 0,
                  todo: issues['todo'] ?? 0,
                  inProgress: issues['in_progress'] ?? 0,
                  completed: issues['completed'] ?? 0,
                  color: Colors.deepOrange,
                ),
              ),
            ],
          ),
          // Tabs removed - not needed for now
        ],
      ),
    );
  }

  Widget _buildCadSummaryCard({
    required String title,
    required int total,
    required int todo,
    required int inProgress,
    required int completed,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Total: $total',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'To Do: $todo',
            style: const TextStyle(fontSize: 13),
          ),
          Text(
            'In Progress: $inProgress',
            style: const TextStyle(fontSize: 13),
          ),
          Text(
            'Completed: $completed',
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildCadTaskList(List<dynamic> items, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index] as Map<String, dynamic>;
          
          // Safely convert all values to strings with null checks
          final nameValue = item['name'];
          final name = (nameValue != null) ? nameValue.toString() : 'Untitled';
          
          final statusValue = item['status'];
          final status = (statusValue != null) ? statusValue.toString() : 'Unknown';
          
          final ownerValue = item['owner'];
          final owner = (ownerValue != null) ? ownerValue.toString() : 'Unassigned';
          
          final idValue = item['id'];
          final id = (idValue != null) ? idValue.toString() : '';
          
          final keyValue = item['key'];
          final key = (keyValue != null) ? keyValue.toString() : '';
          
          final startDateValue = item['start_date'];
          final startDate = (startDateValue != null) ? startDateValue.toString() : null;
          
          final dueDateValue = item['due_date'];
          final dueDate = (dueDateValue != null) ? dueDateValue.toString() : null;
          
          final createdDateValue = item['created_date'];
          final createdDate = (createdDateValue != null) ? createdDateValue.toString() : null;
          
          final createdByValue = item['created_by'];
          final createdBy = (createdByValue != null) ? createdByValue.toString() : null;
          
          final tasklistNameValue = item['tasklist_name'];
          final tasklistName = (tasklistNameValue != null) ? tasklistNameValue.toString() : '';
          
          final priorityValue = item['priority'];
          final priority = (priorityValue != null) ? priorityValue.toString() : '';

          // Determine status color
          Color statusColor = Colors.grey;
          final statusLower = status.toLowerCase();
          if (statusLower.contains('completed') ||
              statusLower.contains('closed') ||
              statusLower.contains('done')) {
            statusColor = Colors.green;
          } else if (statusLower.contains('progress') ||
              statusLower.contains('review')) {
            statusColor = Colors.orange;
          } else if (statusLower.contains('open') ||
              statusLower.contains('todo')) {
            statusColor = Colors.blue;
          }

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and Status
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (key.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              key,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: statusColor),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 12,
                          color: statusColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Details Grid
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    if (owner != 'Unassigned') ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            'Assignee: $owner',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (createdBy != null) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_add, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            'Created by: $createdBy',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (tasklistName.isNotEmpty) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.folder, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            'Tasklist: $tasklistName',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (priority.isNotEmpty && priority != 'None') ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flag, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            'Priority: $priority',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                // Dates Row
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    if (startDate != null && startDate.isNotEmpty) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_circle_outline, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            'Start: $startDate',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (dueDate != null && dueDate.isNotEmpty) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            'Due: $dueDate',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (createdDate != null && createdDate.isNotEmpty) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            'Created: $createdDate',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProjectCard(Map<String, dynamic> project) {
    final projectDetails = project['project_details'] as Map<String, dynamic>?;
    final projectName = projectDetails?['name'] ?? project['project_name'] ?? 'N/A';
    final projectStatus = projectDetails?['status'] ?? 'N/A';
    final progressPercentage = projectDetails?['progress_percentage'] ?? 0;
    final ownerName = projectDetails?['owner_name'] ?? 'N/A';
    final startDate = projectDetails?['start_date'] ?? '';
    final endDate = projectDetails?['end_date'] ?? '';
    final tickets = project['tickets'] as Map<String, dynamic>?;
    final tasks = project['tasks'] as Map<String, dynamic>?;
    
    final stages = ['rtl', 'dv', 'pd', 'al', 'dft'];
    final stageLabels = {
      'rtl': 'RTL',
      'dv': 'DV',
      'pd': 'PD',
      'al': 'AL',
      'dft': 'DFT',
    };
    final stageColors = {
      'rtl': const Color(0xFFE53935), // Red
      'dv': const Color(0xFF43A047), // Green
      'pd': const Color(0xFF1E88E5), // Blue
      'al': const Color(0xFF7B1FA2), // Purple
      'dft': const Color(0xFFF57C00), // Orange
    };

    // Theme colors for headers
    final headerGradient = LinearGradient(
      colors: [
        const Color(0xFF667EEA), // Indigo
        const Color(0xFF764BA2), // Purple
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade300.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Project Name Header with Gradient
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: headerGradient,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            projectName,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  projectStatus,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              if (ownerName != 'N/A') ...[
                                const SizedBox(width: 8),
                                Text(
                                  'Owner: $ownerName',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Stats badges
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildStatBadge(
                          'Tickets',
                          '${tickets?['pending'] ?? 0}/${tickets?['total'] ?? 0}',
                          Colors.orange.shade300,
                        ),
                        const SizedBox(height: 6),
                        _buildStatBadge(
                          'Tasks',
                          '${tasks?['open'] ?? 0}/${tasks?['total'] ?? 0}',
                          Colors.cyan.shade300,
                        ),
                      ],
                    ),
                  ],
                ),
                if (progressPercentage > 0) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progressPercentage / 100,
                            backgroundColor: Colors.white.withOpacity(0.3),
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$progressPercentage%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
                if (startDate.isNotEmpty || endDate.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (startDate.isNotEmpty)
                        Text(
                          'Start: $startDate',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      if (startDate.isNotEmpty && endDate.isNotEmpty)
                        const SizedBox(width: 16),
                      if (endDate.isNotEmpty)
                        Text(
                          'End: $endDate',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // Current Stages Header with Theme Color
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.blue.shade50,
                  Colors.purple.shade50,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade300, width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.timeline,
                  size: 18,
                  color: Colors.blue.shade700,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Current Stages',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          // Stages Grid
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: stages.map<Widget>((stage) {
                final stageData = project[stage] as Map<String, dynamic>?;
                final currentStage = stageData?['current_stage'] ?? 'N/A';
                final milestoneStatus = stageData?['milestone_status'] as Map<String, dynamic>?;
                final overdue = milestoneStatus?['overdue'] ?? 0;
                final pending = milestoneStatus?['pending'] ?? 0;
                final total = milestoneStatus?['total'] ?? 0;
                final inProgressMilestones = (stageData?['in_progress_milestones'] as List<dynamic>?) ?? [];
                final hasInProgress = inProgressMilestones.isNotEmpty;
                final color = stageColors[stage] ?? Colors.black87;
                final label = stageLabels[stage] ?? stage.toUpperCase();

                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: stage == stages.last ? 0 : 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          color.withOpacity(0.1),
                          color.withOpacity(0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: color.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Stage Label with icon
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: hasInProgress ? FontWeight.w900 : FontWeight.bold,
                                color: hasInProgress ? color : color,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Current Stage Value - show in-progress milestones in bold
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: hasInProgress ? color : color.withOpacity(0.2),
                              width: hasInProgress ? 2 : 1,
                            ),
                          ),
                          child: Text(
                            hasInProgress ? inProgressMilestones.join(', ') : currentStage,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: hasInProgress ? FontWeight.w900 : FontWeight.w600,
                              color: hasInProgress ? color : color,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Milestone Status
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Milestone Status',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '$overdue/$pending/$total',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: overdue > 0 ? Colors.red.shade700 : Colors.black87,
                                ),
                              ),
                              Text(
                                'overdue/pending/total',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerView() {
    // For customers, show loading if project is not selected yet
    if (_selectedProject == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Loading project data...',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // Auto-select first domain if not selected yet (for customers)
    if (_selectedDomain == null) {
      if (_availableDomainsForProject.isNotEmpty) {
        // Auto-select first domain
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _selectedDomain == null) {
            setState(() {
              _selectedDomain = _availableDomainsForProject.first;
            });
            _loadInitialData();
          }
        });
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Loading domains...',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ],
            ),
          ),
        );
      } else {
        // Domains are loading, wait for them
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Loading domains...',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ],
            ),
          ),
        );
      }
    }

    // Show loading if data is being loaded
    if (_isLoading || _groupedData.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Loading project data...',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // Get all stages for the selected project
    final allStages = _getAllStagesForProject();
    
    // If no stages found, show message
    if (allStages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            'No data available for this project',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }
    
    // Group by block to get unique blocks with their latest stage info
    final blockDataMap = <String, Map<String, dynamic>>{};
    
    for (var stage in allStages) {
      final blockName = stage['block_name']?.toString() ?? '';
      final rtlTag = stage['rtl_tag']?.toString() ?? '';
      final userName = stage['user_name']?.toString() ?? 'N/A';
      final currentStage = stage['stage']?.toString().toUpperCase() ?? 'N/A';
      final aiSummary = stage['ai_summary']?.toString() ?? 'N/A';
      
      if (blockName.isEmpty) continue;
      
      // Get or create block entry
      if (!blockDataMap.containsKey(blockName)) {
        blockDataMap[blockName] = {
          'block_name': blockName,
          'rtl_tag': rtlTag,
          'user_name': userName,
          'current_stage': currentStage,
          'ai_summary': aiSummary,
          'stages': <Map<String, dynamic>>[],
        };
      }
      
      // Add stage to block's stages list
      blockDataMap[blockName]!['stages']!.add(stage);
      
      // Update to latest stage if this one is more recent
      final stageOrder = ['syn', 'init', 'floorplan', 'place', 'cts', 'postcts', 'route', 'postroute'];
      final currentStageLower = currentStage.toLowerCase();
      final currentIndex = stageOrder.indexOf(currentStageLower);
      final existingStageLower = (blockDataMap[blockName]!['current_stage'] as String).toLowerCase();
      final existingIndex = stageOrder.indexOf(existingStageLower);
      
      if (currentIndex > existingIndex) {
        blockDataMap[blockName]!['current_stage'] = currentStage;
        blockDataMap[blockName]!['rtl_tag'] = rtlTag;
        blockDataMap[blockName]!['user_name'] = userName;
        blockDataMap[blockName]!['ai_summary'] = aiSummary;
      }
    }
    
    // Calculate health index for each block
    for (var blockEntry in blockDataMap.entries) {
      final stages = blockEntry.value['stages'] as List<Map<String, dynamic>>;
      final healthIndex = _calculateBlockHealthIndex(stages);
      blockDataMap[blockEntry.key]!['health_index'] = healthIndex;
      
      // Determine milestone based on current stage
      final currentStage = (blockEntry.value['current_stage'] as String).toUpperCase();
      String milestone = 'N/A';
      if (currentStage.contains('SYN')) {
        milestone = 'Synthesis';
      } else if (currentStage.contains('INIT') || currentStage.contains('FLOORPLAN')) {
        milestone = 'Floorplan';
      } else if (currentStage.contains('PLACE')) {
        milestone = 'Placement';
      } else if (currentStage.contains('CTS')) {
        milestone = 'Clock Tree';
      } else if (currentStage.contains('ROUTE')) {
        milestone = 'Routing';
      } else if (currentStage.contains('POSTROUTE')) {
        milestone = 'Post-Route';
      }
      blockDataMap[blockEntry.key]!['milestone'] = milestone;
    }
    
    final blockList = blockDataMap.values.toList();
    
    // Build table with header
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Project Header Section
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
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
                  color: const Color(0xFF2563EB).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.folder_special,
                  color: Color(0xFF2563EB),
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedProject ?? 'Project',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    if (_selectedDomain != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Domain: $_selectedDomain',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${blockList.length} Block${blockList.length != 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Data Table
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              columnWidths: const {
                0: FixedColumnWidth(180), // Block name
                1: FixedColumnWidth(140), // user_name
                2: FixedColumnWidth(140), // RTL Tag
                3: FixedColumnWidth(140), // current_stage
                4: FixedColumnWidth(180), // Block health index
                5: FixedColumnWidth(300), // Brief summary - fixed width instead of flex
                6: FixedColumnWidth(140), // Milestone
              },
              border: TableBorder(
                horizontalInside: BorderSide(color: Colors.grey.shade200),
                verticalInside: BorderSide(color: Colors.grey.shade200),
              ),
              children: [
                // Header row
                TableRow(
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E293B),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  children: [
                    // Block Name
                    _buildCustomerHeaderCell('Block Name', Alignment.centerLeft),
                    // User Name
                    _buildCustomerHeaderCell('User Name', Alignment.center),
                    // RTL Tag
                    _buildCustomerHeaderCell('RTL Tag', Alignment.center),
                    // Current Stage
                    _buildCustomerHeaderCell('Current Stage', Alignment.center),
                    // Block Health Index
                    _buildCustomerHeaderCell('Block Health Index', Alignment.center),
                    // Brief Summary
                    _buildCustomerHeaderCell('Brief Summary', Alignment.centerLeft),
                    // Milestone
                    _buildCustomerHeaderCell('Milestone', Alignment.center),
                  ],
                ),
                // Data rows
                ...blockList.map((block) {
                    final healthIndex = block['health_index'] as double? ?? 0.0;
                    Color healthColor;
                    if (healthIndex >= 80) {
                      healthColor = const Color(0xFF10B981);
                    } else if (healthIndex >= 60) {
                      healthColor = const Color(0xFFF59E0B);
                    } else {
                      healthColor = const Color(0xFFEF4444);
                    }
                    
                    return TableRow(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                      ),
                      children: [
                        // Block Name
                        _buildCustomerDataCell(
                          block['block_name']?.toString() ?? 'N/A',
                          Alignment.centerLeft,
                          fontWeight: FontWeight.w600,
                        ),
                        // User Name
                        _buildCustomerDataCell(
                          block['user_name']?.toString() ?? 'N/A',
                          Alignment.center,
                        ),
                        // RTL Tag
                        _buildCustomerDataCell(
                          block['rtl_tag']?.toString() ?? 'N/A',
                          Alignment.center,
                        ),
                        // Current Stage
                        _buildCustomerDataCell(
                          block['current_stage']?.toString() ?? 'N/A',
                          Alignment.center,
                          fontWeight: FontWeight.w600,
                        ),
                        // Block Health Index
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: healthColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                healthIndex.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: healthColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Brief Summary
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          alignment: Alignment.centerLeft,
                          child: Text(
                            block['ai_summary']?.toString() ?? 'N/A',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Milestone
                        _buildCustomerDataCell(
                          block['milestone']?.toString() ?? 'N/A',
                          Alignment.center,
                        ),
                      ],
                    );
                  }).toList(),
              ],
            ),
          ),
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
          criticalScore += ((maxWns.abs() * 10).toInt()).clamp(0, 30).toInt();
        }
        criticalScore += ((totalErrors * 2).toInt()).clamp(0, 20).toInt();
        criticalScore += ((totalWarnings * 0.5).toInt()).clamp(0, 10).toInt();
        
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

  // ========================================================================
  // ENHANCED MANAGER VIEW METHODS
  // ========================================================================

  // Calculate Executive Summary Metrics
  Map<String, dynamic> _calculateExecutiveMetrics(
    List<Map<String, dynamic>> allStages,
    Map<String, String> blockStatuses,
    List<Map<String, dynamic>> criticalBlocks,
  ) {
    int totalBlocks = blockStatuses.length;
    int completedBlocks = blockStatuses.values.where((s) => s.toLowerCase() == 'pass').length;
    int failedBlocks = blockStatuses.values.where((s) => s.toLowerCase() == 'fail').length;
    int inProgressBlocks = totalBlocks - completedBlocks - failedBlocks;
    
    int totalStages = allStages.length;
    int completedStages = allStages.where((s) => 
      (s['run_status']?.toString().toLowerCase() ?? '') == 'pass'
    ).length;
    int failedStages = allStages.where((s) => 
      (s['run_status']?.toString().toLowerCase() ?? '') == 'fail'
    ).length;
    
    double avgHealthIndex = allStages.isNotEmpty 
        ? _calculateBlockHealthIndex(allStages) 
        : 0.0;
    
    int criticalIssues = criticalBlocks.length;
    int totalErrors = allStages.fold<int>(0, (int sum, stage) {
      final errors = (_parseNumeric(stage['log_errors']) as num?)?.toInt() ?? 0;
      return sum + errors;
    });
    int totalWarnings = allStages.fold<int>(0, (int sum, stage) {
      final warnings = (_parseNumeric(stage['log_warnings']) as num?)?.toInt() ?? 0;
      return sum + warnings;
    });
    
    double completionRate = totalBlocks > 0 ? (completedBlocks / totalBlocks) * 100 : 0.0;
    
    return {
      'totalBlocks': totalBlocks,
      'completedBlocks': completedBlocks,
      'failedBlocks': failedBlocks,
      'inProgressBlocks': inProgressBlocks,
      'totalStages': totalStages,
      'completedStages': completedStages,
      'failedStages': failedStages,
      'avgHealthIndex': avgHealthIndex,
      'criticalIssues': criticalIssues,
      'totalErrors': totalErrors,
      'totalWarnings': totalWarnings,
      'completionRate': completionRate,
    };
  }

  // Calculate Project Overview
  Map<String, dynamic> _calculateProjectOverview(
    List<Map<String, dynamic>> allStages,
    Map<String, String> blockStatuses,
  ) {
    // Get unique blocks
    final uniqueBlocks = <String>{};
    for (var stage in allStages) {
      final blockName = stage['block_name']?.toString();
      if (blockName != null && blockName.isNotEmpty) {
        uniqueBlocks.add(blockName);
      }
    }
    
    // Calculate stage distribution
    final stageDistribution = <String, int>{};
    for (var stage in allStages) {
      final stageName = stage['stage']?.toString() ?? 'Unknown';
      stageDistribution[stageName] = (stageDistribution[stageName] ?? 0) + 1;
    }
    
    // Calculate timing metrics
    double worstWns = 0.0;
    double bestWns = 0.0;
    double avgWns = 0.0;
    int wnsCount = 0;
    
    for (var stage in allStages) {
      final wns = _parseNumeric(stage['internal_timing_r2r_wns']);
      if (wns != null) {
        if (wnsCount == 0) {
          worstWns = wns;
          bestWns = wns;
        } else {
          if (wns < worstWns) worstWns = wns;
          if (wns > bestWns) bestWns = wns;
        }
        avgWns += wns;
        wnsCount++;
      }
    }
    if (wnsCount > 0) avgWns /= wnsCount;
    
    // Calculate area metrics
    double totalArea = 0.0;
    int areaCount = 0;
    for (var stage in allStages) {
      final area = _parseNumeric(stage['area']);
      if (area != null && area > 0) {
        totalArea += area;
        areaCount++;
      }
    }
    final avgArea = areaCount > 0 ? totalArea / areaCount : 0.0;
    
    return {
      'uniqueBlocks': uniqueBlocks.length,
      'stageDistribution': stageDistribution,
      'worstWns': worstWns,
      'bestWns': bestWns,
      'avgWns': avgWns,
      'avgArea': avgArea,
      'totalStages': allStages.length,
    };
  }

  // Build Executive Summary Metrics (KPI Cards)
  Widget _buildExecutiveSummaryMetrics(Map<String, dynamic> metrics) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'EXECUTIVE SUMMARY',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Color(0xFF1E293B),
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildExecutiveKPICard(
                'Project Health',
                metrics['avgHealthIndex'].toStringAsFixed(1),
                '%',
                metrics['avgHealthIndex'] >= 80 
                    ? const Color(0xFF10B981)
                    : metrics['avgHealthIndex'] >= 60
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFFEF4444),
                Icons.health_and_safety,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildExecutiveKPICard(
                'Completion Rate',
                metrics['completionRate'].toStringAsFixed(1),
                '%',
                metrics['completionRate'] >= 80 
                    ? const Color(0xFF10B981)
                    : metrics['completionRate'] >= 60
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFFEF4444),
                Icons.check_circle,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildExecutiveKPICard(
                'Total Blocks',
                metrics['totalBlocks'].toString(),
                '',
                const Color(0xFF3B82F6),
                Icons.view_module,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildExecutiveKPICard(
                'Critical Issues',
                metrics['criticalIssues'].toString(),
                '',
                metrics['criticalIssues'] > 0 
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF10B981),
                Icons.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildExecutiveKPICard(
                'Completed Blocks',
                metrics['completedBlocks'].toString(),
                '/${metrics['totalBlocks']}',
                const Color(0xFF10B981),
                Icons.done_all,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildExecutiveKPICard(
                'Failed Blocks',
                metrics['failedBlocks'].toString(),
                '',
                metrics['failedBlocks'] > 0 
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF94A3B8),
                Icons.error,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildExecutiveKPICard(
                'Total Errors',
                metrics['totalErrors'].toString(),
                '',
                metrics['totalErrors'] > 0 
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF94A3B8),
                Icons.bug_report,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildExecutiveKPICard(
                'Total Stages',
                metrics['totalStages'].toString(),
                '',
                const Color(0xFF3B82F6),
                Icons.layers,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Build Executive KPI Card
  Widget _buildExecutiveKPICard(String label, String value, String suffix, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF1E293B),
                ),
              ),
              if (suffix.isNotEmpty) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    suffix,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // Build Project-Level Overview
  Widget _buildProjectLevelOverview(Map<String, dynamic> overview, Map<String, String> blockStatuses) {
    return _buildManagerCard(
      'Project-Level Overview',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Statistics Grid
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Unique Blocks',
                  overview['uniqueBlocks'].toString(),
                  Icons.view_module,
                  const Color(0xFF3B82F6),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatItem(
                  'Total Stages',
                  overview['totalStages'].toString(),
                  Icons.layers,
                  const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatItem(
                  'Avg WNS',
                  overview['avgWns'].toStringAsFixed(2),
                  Icons.speed,
                  overview['avgWns'] < 0 
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatItem(
                  'Avg Area',
                  overview['avgArea'].toStringAsFixed(0),
                  'μm²',
                  const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Stage Distribution Chart
          if (overview['stageDistribution'] is Map) ...[
            const Text(
              'Stage Distribution',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: _buildStageDistributionChart(overview['stageDistribution'] as Map<String, int>),
            ),
          ],
          
          const SizedBox(height: 24),
          
          // Timing Metrics Summary
          Row(
            children: [
              Expanded(
                child: Container(
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
                        'Worst WNS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        overview['worstWns'].toStringAsFixed(2),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: overview['worstWns'] < 0 
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Container(
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
                        'Best WNS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        overview['bestWns'].toStringAsFixed(2),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Build Stat Item
  Widget _buildStatItem(String label, String value, dynamic iconOrUnit, Color color) {
    IconData iconData;
    String? unit;
    
    if (iconOrUnit is IconData) {
      iconData = iconOrUnit;
      unit = null;
    } else {
      iconData = Icons.info;
      unit = iconOrUnit.toString();
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
          Row(
            children: [
              Icon(iconData, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E293B),
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    unit,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // Build Stage Distribution Chart
  Widget _buildStageDistributionChart(Map<String, int> distribution) {
    if (distribution.isEmpty) {
      return const Center(
        child: Text(
          'No stage data available',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
      );
    }
    
    final entries = distribution.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    
    final maxValue = entries.isNotEmpty 
        ? entries.map((e) => e.value).reduce((a, b) => a > b ? a : b)
        : 1;
    
    final barGroups = <BarChartGroupData>[];
    final bottomTitles = <String>[];
    
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: entry.value.toDouble(),
              color: _getStageColor(entry.key),
              width: 30,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ],
        ),
      );
      bottomTitles.add(entry.key.toUpperCase());
    }
    
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxValue.toDouble() * 1.2,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: Colors.grey[800]!,
            tooltipRoundedRadius: 8,
            tooltipPadding: const EdgeInsets.all(8),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${bottomTitles[groupIndex]}: ${rod.toY.toInt()}',
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
                        fontSize: 10,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }
                return const Text('');
              },
              reservedSize: 50,
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
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
    );
  }

  Color _getStageColor(String stage) {
    final stageLower = stage.toLowerCase();
    if (stageLower.contains('syn')) return const Color(0xFF3B82F6);
    if (stageLower.contains('place')) return const Color(0xFF10B981);
    if (stageLower.contains('cts')) return const Color(0xFFF59E0B);
    if (stageLower.contains('route')) return const Color(0xFFEF4444);
    return const Color(0xFF94A3B8);
  }

  // Build Critical Issues Dashboard
  Widget _buildCriticalIssuesDashboard(
    List<Map<String, dynamic>> criticalBlocks,
    List<Map<String, dynamic>> allStages,
  ) {
    // Get critical issues from stages
    final criticalIssues = <Map<String, dynamic>>[];
    
    for (var stage in allStages) {
      final status = stage['run_status']?.toString().toLowerCase() ?? '';
      final wns = _parseNumeric(stage['internal_timing_r2r_wns']);
      final errors = _parseNumeric(stage['log_errors']) ?? 0;
      final warnings = _parseNumeric(stage['log_warnings']) ?? 0;
      
      bool isCritical = false;
      String issueType = '';
      
      if (status == 'fail') {
        isCritical = true;
        issueType = 'Failed Stage';
      } else if (wns != null && wns < -0.1) {
        isCritical = true;
        issueType = 'Timing Violation';
      } else if (errors > 10) {
        isCritical = true;
        issueType = 'High Error Count';
      }
      
      if (isCritical) {
        criticalIssues.add({
          'block': stage['block_name']?.toString() ?? 'Unknown',
          'stage': stage['stage']?.toString() ?? 'Unknown',
          'type': issueType,
          'status': status,
          'wns': wns,
          'errors': errors,
          'warnings': warnings,
          'severity': status == 'fail' ? 'high' : (wns != null && wns < -0.5) ? 'high' : 'medium',
        });
      }
    }
    
    // Sort by severity
    criticalIssues.sort((a, b) {
      final severityOrder = {'high': 0, 'medium': 1, 'low': 2};
      final aSev = severityOrder[a['severity']] ?? 2;
      final bSev = severityOrder[b['severity']] ?? 2;
      if (aSev != bSev) return aSev.compareTo(bSev);
      return (b['errors'] as num).compareTo(a['errors'] as num);
    });
    
    return _buildManagerCard(
      'Critical Issues Dashboard',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Row
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFEE2E2)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        criticalIssues.length.toString(),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Critical Issues',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        criticalBlocks.length.toString(),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Critical Blocks',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Critical Issues List
          if (criticalIssues.isNotEmpty) ...[
            const Text(
              'Recent Critical Issues',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 12),
            ...criticalIssues.take(10).map((issue) => _buildCriticalIssueItem(issue)),
          ] else ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Text(
                  'No critical issues found',
                  style: TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Build Critical Issue Item
  Widget _buildCriticalIssueItem(Map<String, dynamic> issue) {
    final severity = issue['severity']?.toString() ?? 'medium';
    final color = severity == 'high' 
        ? const Color(0xFFEF4444)
        : const Color(0xFFF59E0B);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                bottomLeft: Radius.circular(8),
              ),
              color: color,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      severity == 'high' ? Icons.error : Icons.warning,
                      color: color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${issue['block']} - ${issue['stage']}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          issue['type']?.toString() ?? 'Unknown Issue',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (issue['wns'] != null) ...[
                        Text(
                          'WNS: ${(issue['wns'] as num).toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: (issue['wns'] as num) < 0 
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF10B981),
                          ),
                        ),
                      ],
                      if (issue['errors'] != null && (issue['errors'] as num) > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Errors: ${issue['errors']}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build Budget and Timeline Tracking
  Widget _buildBudgetAndTimelineTracking(
    List<Map<String, dynamic>> allStages,
    Map<String, dynamic> projectOverview,
  ) {
    // Calculate timeline metrics
    final stages = <String, DateTime?>{};
    DateTime? earliestDate;
    DateTime? latestDate;
    
    for (var stage in allStages) {
      final timestamp = stage['timestamp']?.toString();
      if (timestamp != null && timestamp.isNotEmpty) {
        try {
          final date = DateTime.parse(timestamp);
          final stageName = stage['stage']?.toString() ?? 'Unknown';
          if (stages[stageName] == null || date.isBefore(stages[stageName]!)) {
            stages[stageName] = date;
          }
          if (earliestDate == null || date.isBefore(earliestDate)) {
            earliestDate = date;
          }
          if (latestDate == null || date.isAfter(latestDate)) {
            latestDate = date;
          }
        } catch (e) {
          // Ignore parse errors
        }
      }
    }
    
    // Calculate progress
    final totalDays = earliestDate != null && latestDate != null
        ? latestDate.difference(earliestDate).inDays
        : 0;
    final daysElapsed = earliestDate != null
        ? DateTime.now().difference(earliestDate).inDays
        : 0;
    final progressPercent = totalDays > 0 
        ? ((daysElapsed / totalDays) * 100).clamp(0, 100)
        : 0.0;
    
    // Mock budget data (would come from actual budget system)
    final budgetData = {
      'allocated': 1000000.0,
      'spent': 750000.0,
      'remaining': 250000.0,
      'utilization': 75.0,
    };
    
    return Row(
      children: [
        Expanded(
          child: _buildManagerCard(
            'Timeline Tracking',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (earliestDate != null && latestDate != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildTimelineItem('Start Date', _formatDate(earliestDate)),
                      _buildTimelineItem('End Date', _formatDate(latestDate)),
                      _buildTimelineItem('Duration', '$totalDays days'),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Project Progress',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          Text(
                            '${progressPercent.toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF3B82F6),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: progressPercent / 100,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          progressPercent >= 75 
                              ? const Color(0xFF10B981)
                              : progressPercent >= 50
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFFEF4444),
                        ),
                        minHeight: 8,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$daysElapsed days elapsed',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Text(
                        'No timeline data available',
                        style: TextStyle(color: Color(0xFF94A3B8)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: _buildManagerCard(
            'Budget Tracking',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildBudgetItem('Allocated', '\$${(budgetData['allocated']! / 1000).toStringAsFixed(0)}K', const Color(0xFF3B82F6)),
                    _buildBudgetItem('Spent', '\$${(budgetData['spent']! / 1000).toStringAsFixed(0)}K', const Color(0xFFF59E0B)),
                    _buildBudgetItem('Remaining', '\$${(budgetData['remaining']! / 1000).toStringAsFixed(0)}K', const Color(0xFF10B981)),
                  ],
                ),
                const SizedBox(height: 24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Budget Utilization',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        Text(
                          '${budgetData['utilization']!.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: budgetData['utilization']! >= 90
                                ? const Color(0xFFEF4444)
                                : budgetData['utilization']! >= 75
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: budgetData['utilization']! / 100,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        budgetData['utilization']! >= 90
                            ? const Color(0xFFEF4444)
                            : budgetData['utilization']! >= 75
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFF10B981),
                      ),
                      minHeight: 8,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              Text(
                                '\$${(budgetData['spent']! / budgetData['allocated']! * 100).toStringAsFixed(1)}%',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              const Text(
                                'Spent',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: const Color(0xFFE2E8F0),
                          ),
                          Column(
                            children: [
                              Text(
                                '\$${(budgetData['remaining']! / budgetData['allocated']! * 100).toStringAsFixed(1)}%',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              const Text(
                                'Remaining',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Build Timeline Item
  Widget _buildTimelineItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }

  // Build Budget Item
  Widget _buildBudgetItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }

  // Format Date
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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

