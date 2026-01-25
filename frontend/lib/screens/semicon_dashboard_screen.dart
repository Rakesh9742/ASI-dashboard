import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../services/qms_service.dart';
import '../widgets/qms_history_dialog.dart';
import '../widgets/qms_status_badge.dart';
import 'qms_dashboard_screen.dart';
import 'qms_checklist_detail_screen.dart';

class SemiconDashboardScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> project;
  final String? initialTab;

  const SemiconDashboardScreen({
    super.key,
    required this.project,
    this.initialTab,
  });

  @override
  ConsumerState<SemiconDashboardScreen> createState() => _SemiconDashboardScreenState();
}

class _SemiconDashboardScreenState extends ConsumerState<SemiconDashboardScreen> {
  final _apiService = ApiService();
  String _selectedBlock = 'Select a block';
  String _selectedExperiment = 'Select an experiment';
  String? _currentRunDirectory;
  final TextEditingController _commandController = TextEditingController();
  final List<Map<String, dynamic>> _activityLog = [];
  late String _selectedTab;
  
  List<String> _availableBlocks = [];
  List<String> _availableExperiments = [];
  bool _isLoadingBlocks = false;
  
  // Store block data with IDs for QMS navigation
  Map<String, int> _blockNameToId = {};
  
  // Command output storage
  String? _lastCommandOutput;
  String? _lastCommandError;
  String? _lastCommand;
  bool _isExecutingCommand = false;
  
  // Metrics data
  Map<String, dynamic>? _metricsData;
  bool _isLoadingMetrics = false;
  
  // QMS data
  final QmsService _qmsService = QmsService();
  bool _isLoadingQms = false;
  List<dynamic> _qmsChecklists = [];
  Map<String, dynamic>? _qmsBlockStatus;
  
  // Run history data
  List<Map<String, dynamic>> _runHistory = [];
  bool _isLoadingRunHistory = false;
  
  // Development Tools expansion state
  bool _isDevelopmentToolsExpanded = false;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab ?? 'Dashboard';
    _loadBlocksAndExperiments();
    _loadRunHistory();
  }

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  Future<void> _loadBlocksAndExperiments() async {
    setState(() {
      _isLoadingBlocks = true;
    });

    try {
      final token = ref.read(authProvider).token;
      if (token == null) {
        throw Exception('No authentication token');
      }

      final projectName = widget.project['name'] ?? '';
      if (projectName.isEmpty) {
        setState(() {
          _isLoadingBlocks = false;
        });
        return;
      }

      // Load EDA files for this project - use smaller limit for faster loading
      // We only need unique block and experiment names, not all file data
      final filesResponse = await _apiService.getEdaFiles(
        token: token,
        projectName: projectName,
        limit: 200, // Reduced from 1000 to 200 for faster loading
      );

      final files = filesResponse['files'] ?? [];
      
      // Extract unique blocks and experiments
      final blockSet = <String>{};
      final experimentSet = <String>{};
      
      for (var file in files) {
        final blockName = file['block_name']?.toString();
        final experiment = file['experiment']?.toString();
        
        if (blockName != null && blockName.isNotEmpty) {
          blockSet.add(blockName);
        }
        
        if (experiment != null && experiment.isNotEmpty) {
          experimentSet.add(experiment);
        }
      }

      // Load block IDs from API
      _loadBlockIds(projectName, token);

      setState(() {
        _availableBlocks = blockSet.toList()..sort();
        _availableExperiments = experimentSet.toList()..sort();
        _isLoadingBlocks = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingBlocks = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load blocks and experiments: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  Future<void> _loadBlockIds(String projectName, String token) async {
    try {
      // Get project ID first
      final projects = await _apiService.getProjects(token: token);
      Map<String, dynamic>? project;
      try {
        project = projects.firstWhere(
          (p) => (p['name']?.toString().toLowerCase() ?? '') == projectName.toLowerCase(),
        ) as Map<String, dynamic>?;
      } catch (e) {
        // Project not found
        return;
      }
      
      if (project == null || project['id'] == null) {
        return;
      }
      
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
        }
      }
    } catch (e) {
      // Silently fail - block IDs won't be available for QMS navigation
      print('Failed to load block IDs: $e');
    }
  }

  Future<void> _loadRunHistory() async {
    setState(() {
      _isLoadingRunHistory = true;
    });

    try {
      final token = ref.read(authProvider).token;
      if (token == null) {
        throw Exception('No authentication token');
      }

      // Get project ID
      final projects = await _apiService.getProjects(token: token);
      final projectName = widget.project['name'] ?? '';
      if (projectName.isEmpty) {
        setState(() {
          _isLoadingRunHistory = false;
          _runHistory = [];
        });
        return;
      }

      Map<String, dynamic>? project;
      try {
        project = projects.firstWhere(
          (p) => (p['name']?.toString().toLowerCase() ?? '') == projectName.toLowerCase(),
        ) as Map<String, dynamic>?;
      } catch (e) {
        // Project not found
        setState(() {
          _isLoadingRunHistory = false;
          _runHistory = [];
        });
        return;
      }

      if (project == null || project['id'] == null) {
        setState(() {
          _isLoadingRunHistory = false;
          _runHistory = [];
        });
        return;
      }

      final projectId = project['id'] as int;

      // Load run history with optional filters
      final runHistory = await _apiService.getRunHistory(
        projectId: projectId,
        blockName: _selectedBlock != 'Select a block' ? _selectedBlock : null,
        experiment: _selectedExperiment != 'Select an experiment' ? _selectedExperiment : null,
        limit: 20,
        token: token,
      );

      if (mounted) {
        setState(() {
          _runHistory = runHistory.map((item) => item as Map<String, dynamic>).toList();
          _isLoadingRunHistory = false;
        });
      }
    } catch (e) {
      print('Error loading run history: $e');
      if (mounted) {
        setState(() {
          _runHistory = [];
          _isLoadingRunHistory = false;
        });
      }
    }
  }

  void _onBlockChanged(String? value) {
    setState(() {
      _selectedBlock = value ?? 'Select a block';
      _selectedExperiment = 'Select an experiment'; // Reset experiment when block changes
      _metricsData = null; // Reset metrics when block changes
      _currentRunDirectory = null; // Reset run directory when block changes
      _qmsChecklists = [];
      _qmsBlockStatus = null;
    });
    
    // Load experiments for the selected block
    if (_selectedBlock != 'Select a block') {
      _loadExperimentsForBlock(_selectedBlock);
      
      // Load QMS data if QMS tab is selected
      if (_selectedTab == 'QMS') {
        _loadQmsData();
      }
    } else {
      setState(() {
        _availableExperiments = [];
      });
    }
    
    // Reload run history with new block filter
    _loadRunHistory();
  }
  
  void _onExperimentChanged(String? value) {
    setState(() {
      _selectedExperiment = value ?? 'Select an experiment';
      _currentRunDirectory = null; // Reset run directory when experiment changes
    });
    
    // Load metrics and run directory when experiment is selected
    if (_selectedBlock != 'Select a block' && _selectedExperiment != 'Select an experiment') {
      _loadMetricsData(); // This will also load the run directory
      _loadRunDirectory(); // Also try to load it directly
    }
    
    // Reload run history with new experiment filter
    _loadRunHistory();
  }

  Future<void> _loadRunDirectory() async {
    if (_selectedBlock == 'Select a block' || _selectedExperiment == 'Select an experiment') {
      return;
    }

    try {
      final token = ref.read(authProvider).token;
      if (token == null) {
        return;
      }

      final projectName = widget.project['name'] ?? '';
      if (projectName.isEmpty) {
        return;
      }

      // Load EDA files to get run directory
      final filesResponse = await _apiService.getEdaFiles(
        token: token,
        projectName: projectName,
        limit: 100,
      );

      final files = filesResponse['files'] ?? [];
      
      // Find first matching file for this block and experiment
      final matchingFile = files.firstWhere(
        (file) {
          final fileBlock = file['block_name']?.toString();
          final fileExperiment = file['experiment']?.toString();
          return fileBlock == _selectedBlock && fileExperiment == _selectedExperiment;
        },
        orElse: () => null,
      );

      if (matchingFile != null && mounted) {
        final runDirectory = matchingFile['run_directory']?.toString();
        setState(() {
          _currentRunDirectory = runDirectory;
        });
      }
    } catch (e) {
      // Silently fail - run directory will remain null
      print('Error loading run directory: $e');
    }
  }
  
  Future<void> _loadMetricsData() async {
    if (_selectedBlock == 'Select a block' || _selectedExperiment == 'Select an experiment') {
      return;
    }

    setState(() {
      _isLoadingMetrics = true;
    });

    try {
      final token = ref.read(authProvider).token;
      if (token == null) {
        throw Exception('No authentication token');
      }

      final projectName = widget.project['name'] ?? '';
      if (projectName.isEmpty) {
        setState(() {
          _isLoadingMetrics = false;
        });
        return;
      }

      // Load EDA files for this project, block, and experiment
      // Use smaller limit since we're filtering by block and experiment anyway
      final filesResponse = await _apiService.getEdaFiles(
        token: token,
        projectName: projectName,
        limit: 200, // Reduced from 1000 to 200 for faster loading
      );

      final files = filesResponse['files'] ?? [];
      
      // Filter files by block and experiment, then get the latest stage
      final matchingFiles = files.where((file) {
        final fileBlock = file['block_name']?.toString();
        final fileExperiment = file['experiment']?.toString();
        return fileBlock == _selectedBlock && fileExperiment == _selectedExperiment;
      }).toList();

      if (matchingFiles.isEmpty) {
        setState(() {
          _metricsData = null;
          _currentRunDirectory = null;
          _isLoadingMetrics = false;
        });
        return;
      }

      // Extract run directory from the first matching file
      final runDirectory = matchingFiles.first['run_directory']?.toString();
      setState(() {
        _currentRunDirectory = runDirectory;
      });

      // Get the latest stage (by timestamp or stage order)
      final stageOrder = ['syn', 'init', 'floorplan', 'place', 'cts', 'postcts', 'route', 'postroute'];
      Map<String, dynamic>? latestStage;
      int latestIndex = -1;

      for (var file in matchingFiles) {
        final stageName = file['stage']?.toString().toLowerCase() ?? '';
        final stageIndex = stageOrder.indexOf(stageName);
        
        if (stageIndex > latestIndex) {
          latestIndex = stageIndex;
          latestStage = file;
        }
      }

      if (latestStage != null) {
        setState(() {
          _metricsData = latestStage;
          _isLoadingMetrics = false;
        });
      } else {
        setState(() {
          _metricsData = null;
          _isLoadingMetrics = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingMetrics = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load metrics: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }
  
  String _formatArea(dynamic area) {
    if (area == null) return 'N/A';
    final areaNum = double.tryParse(area.toString());
    if (areaNum == null) return 'N/A';
    if (areaNum >= 1000000) {
      return '${(areaNum / 1000000).toStringAsFixed(2)} mm²';
    } else if (areaNum >= 1000) {
      return '${(areaNum / 1000).toStringAsFixed(2)} μm²';
    }
    return '${areaNum.toStringAsFixed(2)} μm²';
  }
  
  String _formatPower(dynamic power) {
    if (power == null) return 'N/A';
    final powerNum = double.tryParse(power.toString());
    if (powerNum == null) return 'N/A';
    if (powerNum >= 1000) {
      return '${(powerNum / 1000).toStringAsFixed(2)} W';
    }
    return '${powerNum.toStringAsFixed(2)} mW';
  }
  
  String _formatFrequency(dynamic minPeriod) {
    if (minPeriod == null || minPeriod.toString().toUpperCase() == 'N/A') return 'N/A';
    final periodNum = double.tryParse(minPeriod.toString());
    if (periodNum == null || periodNum <= 0) return 'N/A';
    // Frequency = 1 / period (in GHz if period is in ns)
    final freqGHz = 1.0 / periodNum;
    return '${freqGHz.toStringAsFixed(2)} GHz';
  }
  
  String _formatTimingSlack(dynamic wns) {
    if (wns == null || wns.toString().toUpperCase() == 'N/A') return 'N/A';
    final wnsNum = double.tryParse(wns.toString());
    if (wnsNum == null) return 'N/A';
    final sign = wnsNum >= 0 ? '+' : '';
    return '$sign${wnsNum.toStringAsFixed(2)} ps';
  }
  
  double? _parseUtilization(dynamic util) {
    if (util == null || util.toString().toUpperCase() == 'N/A') return null;
    final utilStr = util.toString().replaceAll('%', '');
    return double.tryParse(utilStr);
  }
  
  String _formatInterfaceTiming(Map<String, dynamic>? data) {
    if (data == null) return 'N/A';
    final i2r = data['interface_timing_i2r_wns'];
    final r2o = data['interface_timing_r2o_wns'];
    
    if (i2r != null && i2r.toString().toUpperCase() != 'N/A') {
      final i2rNum = double.tryParse(i2r.toString());
      if (i2rNum != null) {
        final sign = i2rNum >= 0 ? '+' : '';
        return 'I2R: $sign${i2rNum.toStringAsFixed(2)} ps';
      }
    }
    
    if (r2o != null && r2o.toString().toUpperCase() != 'N/A') {
      final r2oNum = double.tryParse(r2o.toString());
      if (r2oNum != null) {
        final sign = r2oNum >= 0 ? '+' : '';
        return 'R2O: $sign${r2oNum.toStringAsFixed(2)} ps';
      }
    }
    
    return 'N/A';
  }

  Future<void> _loadExperimentsForBlock(String blockName) async {
    try {
      final token = ref.read(authProvider).token;
      if (token == null) return;

      final projectName = widget.project['name'] ?? '';
      if (projectName.isEmpty) return;

      // Load EDA files for this project and block
      final filesResponse = await _apiService.getEdaFiles(
        token: token,
        projectName: projectName,
        limit: 1000,
      );

      final files = filesResponse['files'] ?? [];
      final experimentSet = <String>{};
      
      for (var file in files) {
        final fileBlockName = file['block_name']?.toString();
        final experiment = file['experiment']?.toString();
        
        if (fileBlockName == blockName && experiment != null && experiment.isNotEmpty) {
          experimentSet.add(experiment);
        }
      }

      setState(() {
        _availableExperiments = experimentSet.toList()..sort();
      });
    } catch (e) {
      // Silently fail - experiments list will remain empty
    }
  }
  
  Future<void> _openQMSInNewWindow() async {
    try {
      // Check if a block is selected
      final blockId = _blockNameToId[_selectedBlock];
      if (blockId == null || _selectedBlock == null || _selectedBlock == 'Select a block') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select a block to view QMS dashboard'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Store blockId in localStorage for the new window
      html.window.localStorage['standalone_qms_blockId'] = blockId.toString();
      
      // Get current URL and construct new window URL
      final currentUrl = html.window.location.href;
      final baseUrl = currentUrl.split('?')[0].split('#')[0];
      
      // Open new window with QMS dashboard route
      String newWindowUrl = '$baseUrl#/qms-dashboard?blockId=$blockId';
      
      html.window.open(
        newWindowUrl,
        'qms_dashboard_$blockId',
        'width=1600,height=1000,scrollbars=yes,resizable=yes',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open QMS dashboard: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  Future<void> _openTerminalInNewWindow() async {
    try {
      final token = ref.read(authProvider).token;
      final user = ref.read(authProvider).user;
      
      if (token == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Not authenticated. Please login again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Store auth data in localStorage for the new window
      html.window.localStorage['terminal_auth_token'] = token;
      if (user != null) {
        html.window.localStorage['terminal_auth_user'] = jsonEncode(user);
      }
      
      // Get current URL and construct new window URL
      final currentUrl = html.window.location.href;
      final baseUrl = currentUrl.split('?')[0].split('#')[0];
      
      // Open new window with terminal route
      String newWindowUrl = '$baseUrl#/terminal';
      
      html.window.open(
        newWindowUrl,
        'terminal',
        'width=1200,height=800,scrollbars=no,resizable=yes',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open terminal: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  Future<void> _openVncInNewWindow() async {
    try {
      final token = ref.read(authProvider).token;
      final user = ref.read(authProvider).user;
      
      if (token == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Not authenticated. Please login again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Store auth data in localStorage for the new window
      html.window.localStorage['vnc_auth_token'] = token;
      if (user != null) {
        html.window.localStorage['vnc_auth_user'] = jsonEncode(user);
      }
      
      // Get current URL and construct new window URL
      final currentUrl = html.window.location.href;
      final baseUrl = currentUrl.split('?')[0].split('#')[0];
      
      // Open new window with VNC route
      String newWindowUrl = '$baseUrl#/vnc';
      
      html.window.open(
        newWindowUrl,
        'vnc',
        'width=1400,height=900,scrollbars=no,resizable=yes',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open VNC viewer: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }
  
  Future<void> _openViewScreenInNewWindow() async {
    try {
      final projectName = widget.project['name'] ?? '';
      if (projectName.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Project name not available'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Get first domain for the project (if available)
      // Use minimal limit since we only need one file to get domain name
      String? domainName;
      try {
        final token = ref.read(authProvider).token;
        if (token != null) {
          final filesResponse = await _apiService.getEdaFiles(
            token: token,
            projectName: projectName,
            limit: 10, // Reduced from 100 to 10 - we only need first file for domain name
          );
          final files = filesResponse['files'] ?? [];
          if (files.isNotEmpty) {
            final firstFile = files[0];
            domainName = firstFile['domain_name']?.toString();
          }
        }
      } catch (e) {
        // Ignore domain loading errors - domain is optional
      }

      // Determine view type based on user role
      final userRole = ref.read(authProvider).user?['role'];
      final viewType = userRole == 'customer' ? 'customer' : 'engineer';

      // Store data in localStorage for the new window
      final viewData = {
        'project': projectName,
        if (domainName != null && domainName.isNotEmpty) 'domain': domainName,
        'viewType': viewType,
      };
      html.window.localStorage['standalone_view'] = jsonEncode(viewData);
      
      // Get current URL and construct new window URL
      final currentUrl = html.window.location.href;
      final baseUrl = currentUrl.split('?')[0].split('#')[0];
      final projectNameEncoded = Uri.encodeComponent(projectName);
      final domainNameEncoded = domainName != null && domainName.isNotEmpty 
          ? Uri.encodeComponent(domainName) 
          : '';
      
      // Open new window with view route
      String newWindowUrl = '$baseUrl#/view?project=$projectNameEncoded';
      if (domainNameEncoded.isNotEmpty) {
        newWindowUrl += '&domain=$domainNameEncoded';
      }
      newWindowUrl += '&viewType=$viewType';
      
      html.window.open(
        newWindowUrl,
        'view_${projectName.replaceAll(' ', '_')}',
        'width=1600,height=1000,scrollbars=yes,resizable=yes',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open view window: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show Project Dashboard (navigation and tabs are handled by MainNavigationScreen)
    return Row(
          children: [
            // Left Panel - Command Console + Activity Log (45%)
        Expanded(
          flex: 45,
          child: Container(
              decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                border: Border(
                right: BorderSide(color: Theme.of(context).dividerColor, width: 1),
                ),
              ),
                    child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      // Block and Experiment Selectors
                          _buildSelectionSection(),
                      _buildRunDirectoryInfo(),
                          const SizedBox(height: 24),
                          // Command Console
                          _buildCommandConsole(),
                      const SizedBox(height: 24),
                      // Command Output (if available)
                      if (_lastCommand != null || _isExecutingCommand)
                        _buildCommandOutput(),
                      if (_lastCommand != null || _isExecutingCommand)
                          const SizedBox(height: 24),
                          // Activity Log
                          _buildActivityLog(),
                        ],
                      ),
                    ),
                      ),
                    ),
            // Right Panel - Dashboard Tabs (55%)
            Expanded(
              flex: 55,
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Column(
                  children: [
                    // Fixed Tabs Header
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1)),
                      ),
                      child: Row(
                        children: [
                          _buildDashboardTab('Dashboard', Icons.grid_view, isSelected: _selectedTab == 'Dashboard'),
                          const SizedBox(width: 0),
                          _buildDashboardTab('QMS', Icons.check_circle_outline, isSelected: _selectedTab == 'QMS'),
                          const SizedBox(width: 0),
                          _buildDashboardTab('<> Dev', Icons.code, isSelected: _selectedTab == '<> Dev'),
                ],
              ),
              ),
                    
                    // Main Content (Scrollable)
                  Expanded(
                    child: _buildMainContent(),
                  ),
                ],
                ),
              ),
            ),
          ],
    );
  }

  Widget _buildSelectionSection() {
    return Row(
      children: [
        // Block Selector
        Expanded(
          child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Block',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
              const SizedBox(height: 4),
        Container(
          width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: _isLoadingBlocks
              ? const Center(
                  child: Padding(
                          padding: EdgeInsets.all(4.0),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
                    : DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
            value: _selectedBlock,
            isExpanded: true,
                          isDense: true,
                          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                  dropdownColor: Theme.of(context).cardColor,
                  items: [
                    DropdownMenuItem(
                      value: 'Select a block',
                      child: Text('Select a block', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
                    ),
                    ..._availableBlocks.map((block) => DropdownMenuItem(
                      value: block,
                          child: Text(block, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                        )),
                  ],
                  onChanged: _onBlockChanged,
          ),
        ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Experiment Selector
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
        Text(
          'Experiment',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
              const SizedBox(height: 4),
        Container(
          width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
                child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedExperiment,
            isExpanded: true,
                    isDense: true,
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
            dropdownColor: Theme.of(context).cardColor,
            items: [
              DropdownMenuItem(
                value: 'Select an experiment',
                child: Text('Select an experiment', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
              ),
              ..._availableExperiments.map((exp) => DropdownMenuItem(
                      value: exp,
                    child: Text(exp, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                  )),
            ],
            onChanged: _onExperimentChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRunDirectoryInfo() {
    if (_selectedBlock == 'Select a block' || _selectedExperiment == 'Select an experiment') {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_open,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
                  'Run Directory',
          style: TextStyle(
                    fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
                const SizedBox(height: 4),
                SelectableText(
                  _currentRunDirectory ?? 'Loading...',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          if (_currentRunDirectory != null)
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () {
                // Copy to clipboard
                Clipboard.setData(ClipboardData(text: _currentRunDirectory!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Run directory copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              tooltip: 'Copy path',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  Widget _buildCommandConsole() {
    return Container(
      padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Command Console',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: TextField(
            controller: _commandController,
            maxLines: 6,
            maxLength: 500,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: 'e.g., Run RTL validation, Execute synthesis, Check QMS gates...',
              hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(12),
                counterText: '', // Hide counter inside field, maybe show below or just hide
            ),
          ),
        ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
               Text(
                '${_commandController.text.length}/500',
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4)),
              ),
              ElevatedButton.icon(
                onPressed: _isExecutingCommand ? null : () {
              if (_commandController.text.isNotEmpty) {
                _executeCommand(_commandController.text);
                _commandController.clear();
                    setState(() {}); // Update counter
                  }
                },
                icon: _isExecutingCommand 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_arrow, size: 16),
                label: Text(_isExecutingCommand ? 'Executing...' : 'Execute'),
            style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5CCBDB), // Light cyan from image
              foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  minimumSize: const Size(0, 36),
              shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommandOutput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.terminal,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Command Output',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              if (_lastCommand != null)
                TextButton.icon(
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Clear'),
                  onPressed: () {
                    setState(() {
                      _lastCommand = null;
                      _lastCommandOutput = null;
                      _lastCommandError = null;
                    });
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          if (_lastCommand != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withOpacity(0.5),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '\$ ',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      _lastCommand!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface,
                        fontFamily: 'monospace',
            ),
          ),
        ),
      ],
              ),
            ),
          ],
          if (_isExecutingCommand) ...[
            const SizedBox(height: 16),
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            ),
          ] else if (_lastCommandOutput != null && _lastCommandOutput!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade700),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _lastCommandOutput!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ],
          if (_lastCommandError != null && _lastCommandError!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade900.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade700),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _lastCommandError!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red.shade200,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ],
          if (!_isExecutingCommand && 
              (_lastCommandOutput == null || _lastCommandOutput!.isEmpty) &&
              (_lastCommandError == null || _lastCommandError!.isEmpty) &&
              _lastCommand != null) ...[
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Command executed successfully (no output)',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActivityLog() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
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
              Row(
                children: [
                  Icon(
                    Icons.history,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
            Text(
                    'Command History',
              style: TextStyle(
                      fontSize: 15,
                fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                icon: Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
                label: Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              onPressed: () {
                setState(() {
                  _activityLog.clear();
                });
              },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ),
          ],
        ),
          const SizedBox(height: 12),
          // Log List Container with better styling
        Container(
            height: 300,
          decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).dividerColor.withOpacity(0.3),
              ),
          ),
          child: _activityLog.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                        Icon(
                          Icons.terminal_outlined,
                          size: 48,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                        ),
                        const SizedBox(height: 12),
                      Text(
                          'No commands executed',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                          'Command output will appear in the terminal',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _activityLog.length,
                  itemBuilder: (context, index) {
                    final log = _activityLog[index];
                      final isSuccess = log['status'] == 'success';
                      final isError = log['status'] == 'error';
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSuccess
                              ? Colors.green.withOpacity(0.1)
                              : isError
                                  ? Colors.red.withOpacity(0.1)
                                  : Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSuccess
                                ? Colors.green.withOpacity(0.3)
                                : isError
                                    ? Colors.red.withOpacity(0.3)
                                    : Theme.of(context).colorScheme.primary.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isSuccess
                                    ? Colors.green.withOpacity(0.2)
                                    : isError
                                        ? Colors.red.withOpacity(0.2)
                                        : Theme.of(context).colorScheme.primary.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Icon(
                                isSuccess
                                ? Icons.check_circle
                                    : isError
                                        ? Icons.error
                                        : Icons.play_arrow,
                            size: 16,
                                color: isSuccess
                                    ? Colors.green.shade700
                                    : isError
                                        ? Colors.red.shade700
                                        : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    log['message'].toString(),
                              style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: isSuccess
                                          ? Colors.green.shade700
                                          : isError
                                              ? Colors.red.shade700
                                              : Theme.of(context).colorScheme.onSurface.withOpacity(0.9),
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatTimestamp(log['timestamp'] as DateTime),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                    ),
                                  ),
                                ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  Widget _buildMainHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Project Name
                    Text(
            '${widget.project['name'] ?? 'Project'}',
                      style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title Section
          Row(
             mainAxisAlignment: MainAxisAlignment.spaceBetween,
             children: [
               Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
          Text(
            'Design Dashboard',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Project: ${widget.project['name'] ?? 'Unknown'}',
            style: TextStyle(
              fontSize: 14,
                        color: const Color(0xFF1E96B1), // Cyan-ish color from image
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                 ],
               ),
               // Pop Out Button
               if (_selectedTab != '<> Dev')
                 Container(
                   decoration: BoxDecoration(
                     border: Border.all(color: Theme.of(context).dividerColor),
                     borderRadius: BorderRadius.circular(4),
                   ),
            child: TextButton.icon(
              onPressed: () {
                       if (_selectedTab == 'Dashboard') {
                _openViewScreenInNewWindow();
                       } else if (_selectedTab == 'QMS') {
                         _openQMSInNewWindow();
                       }
              },
                     icon: const Icon(Icons.open_in_new, size: 14),
                     label: const Text('Pop Out', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                       foregroundColor: Theme.of(context).colorScheme.onSurface,
                       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
            ],
          ),
          const SizedBox(height: 24),

          // Content based on selected tab
          if (_selectedTab == 'Dashboard') ...[
          // Key Metrics Cards
          _buildMetricsCards(),
          const SizedBox(height: 32),
          // Run History
          _buildRunHistory(),
          ] else if (_selectedTab == 'QMS') ...[
            _buildQmsContent(),
          ] else if (_selectedTab == '<> Dev') ...[
            _buildDevContent(),
          ],
        ],
      ),
    );
  }

  Future<void> _loadQmsData() async {
    if (_selectedBlock == 'Select a block') {
      return;
    }
    
    final blockId = _blockNameToId[_selectedBlock];
    if (blockId == null) {
      return;
    }
    
    setState(() {
      _isLoadingQms = true;
    });
    
    try {
      final token = ref.read(authProvider).token;
      if (token == null) {
        throw Exception('No authentication token');
      }
      
      final checklists = await _qmsService.getChecklistsForBlock(blockId, token: token);
      final status = await _qmsService.getBlockStatus(blockId, token: token);
      
      setState(() {
        _qmsChecklists = checklists;
        _qmsBlockStatus = status;
        _isLoadingQms = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingQms = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load QMS data: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  Widget _buildDashboardTab(String label, IconData icon, {required bool isSelected}) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedTab = label;
        });
        
        // Load QMS data when QMS tab is selected
        if (label == 'QMS' && _selectedBlock != 'Select a block') {
          _loadQmsData();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.transparent : Colors.transparent,
          border: isSelected 
              ? Border(bottom: BorderSide(color: const Color(0xFF1E96B1), width: 2))
              : null,
          boxShadow: isSelected 
              ? [BoxShadow(color: const Color(0xFF1E96B1).withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? const Color(0xFF1E96B1) : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
            const SizedBox(width: 8),
            Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
                color: isSelected ? const Color(0xFF1E96B1) : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsCards() {
    if (_isLoadingMetrics) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_metricsData == null || _selectedBlock == 'Select a block' || _selectedExperiment == 'Select an experiment') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            'Please select a block and experiment to view metrics',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ),
      );
    }

    final data = _metricsData!;
    final area = _formatArea(data['area']);
    final power = _formatPower(data['ir_dynamic'] ?? data['ir_static']);
    final minPeriod = data['min_period'];
    final frequency = _formatFrequency(minPeriod);
    final utilization = _parseUtilization(data['utilization']);
    final timingSlack = _formatTimingSlack(data['internal_timing_r2r_wns']);
    final interfaceTiming = _formatInterfaceTiming(data);
    final gateCount = data['inst_count']?.toString() ?? 'N/A';
    final tech = widget.project['technology'] ?? widget.project['technology_node'] ?? 'N/A';

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.4,
      children: [
        _buildMetricCard(
          'Gate Count',
          gateCount,
          Icons.memory,
          subtitle: tech,
        ),
        _buildMetricCard(
          'Area',
          area,
          Icons.square_foot,
          subtitle: utilization != null ? 'Utilization: ${utilization.toStringAsFixed(1)}%' : 'Utilization: N/A',
        ),
        _buildMetricCard(
          'Power',
          power,
          Icons.power,
          subtitle: frequency != 'N/A' ? '@ $frequency' : 'N/A',
        ),
        _buildMetricCard(
          'Frequency',
          frequency,
          Icons.speed,
          subtitle: timingSlack != 'N/A' ? 'Timing: $timingSlack' : 'Timing: N/A',
        ),
        _buildMetricCardWithProgress(
          'Utilization',
          utilization != null ? '${utilization.toStringAsFixed(1)}%' : 'N/A',
          Icons.pie_chart,
          utilization != null ? (utilization / 100).clamp(0.0, 1.0) : 0.0,
        ),
        _buildMetricCard(
          'Timing Slack',
          timingSlack,
          Icons.timer,
          subtitle: 'WNS (Worst Negative Slack)',
        ),
        _buildMetricCard(
          'Interface Timing',
          interfaceTiming,
          Icons.swap_horiz,
          subtitle: 'I2R / R2O WNS',
        ),
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, {String? subtitle}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
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
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricCardWithProgress(String title, String value, IconData icon, double progress) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
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
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildRunHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Run History',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Recent execution history for this design',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 16),
        if (_isLoadingRunHistory)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_runHistory.isEmpty)
          Container(
            padding: const EdgeInsets.all(32.0),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Center(
              child: Text(
                'No run history available',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ),
          )
        else
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(2.5),
              2: FlexColumnWidth(1.5),
              3: FlexColumnWidth(1),
            },
            children: [
              // Header
              TableRow(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                children: [
                  _buildTableHeader('Timestamp'),
                  _buildTableHeader('Command'),
                  _buildTableHeader('Status'),
                  _buildTableHeader('Duration'),
                ],
              ),
              // Rows
                ..._runHistory.map((run) => TableRow(
                    children: [
                        _buildTableCell(run['timestamp']?.toString() ?? 'Unknown'),
                        _buildTableCell(run['command']?.toString() ?? 'Unknown'),
                        _buildTableStatus(run['status']?.toString() ?? 'UNKNOWN'),
                        _buildTableCell(run['duration']?.toString() ?? 'N/A'),
                    ],
                  )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
        ),
      ),
    );
  }

  Widget _buildTableCell(String text) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
        ),
      ),
    );
  }

  Widget _buildTableStatus(String status) {
    final isCompleted = status == 'COMPLETED';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isCompleted
              ? const Color(0xFF10B981).withOpacity(0.1)
              : const Color(0xFFEF4444).withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          status,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isCompleted ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          ),
        ),
      ),
    );
  }

  Future<void> _executeCommand(String command) async {
    // Store the command and clear previous output
    setState(() {
      _lastCommand = command;
      _lastCommandOutput = null;
      _lastCommandError = null;
      _isExecutingCommand = true;
      
      // Show command with directory info if available
      String logMessage = '→ $command';
      if (_currentRunDirectory != null && _currentRunDirectory!.isNotEmpty) {
        logMessage += ' (in: $_currentRunDirectory)';
      }
      _activityLog.add({
        'timestamp': DateTime.now(),
        'message': logMessage,
        'status': 'info',
      });
    });

    try {
      final token = ref.read(authProvider).token;
      if (token == null) {
        throw Exception('Not authenticated');
      }

      // Check if we have a run directory and block/experiment selected
      String? workingDirectory;
      if (_currentRunDirectory != null && 
          _currentRunDirectory!.isNotEmpty &&
          _selectedBlock != 'Select a block' &&
          _selectedExperiment != 'Select an experiment') {
        workingDirectory = _currentRunDirectory;
      }

      final result = await _apiService.executeSSHCommand(
        command: command,
        token: token,
        workingDirectory: workingDirectory,
      );

      if (mounted) {
        setState(() {
          _isExecutingCommand = false;
          
          // Store output for display
          _lastCommandOutput = result['stdout']?.toString();
          _lastCommandError = result['stderr']?.toString();
          
          // Check if error is about directory not existing
          final errorText = _lastCommandError?.toLowerCase() ?? '';
          if (errorText.contains('directory') && errorText.contains('does not exist')) {
            // Show specific error for missing directory
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: Run directory not found on server: $_currentRunDirectory'),
                backgroundColor: Colors.red.shade600,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          
          // Only log command completion status in activity log
          final exitCode = result['exitCode'];
          if (exitCode != null && exitCode != 0) {
            String errorMsg = '✗ Command failed (exit code: $exitCode)';
            if (errorText.contains('directory') && errorText.contains('does not exist')) {
              errorMsg = '✗ Directory not found';
            }
          _activityLog.add({
            'timestamp': DateTime.now(),
              'message': errorMsg,
              'status': 'error',
            });
          } else {
            // Update the last log entry to show success
            if (_activityLog.isNotEmpty) {
              final lastIndex = _activityLog.length - 1;
              _activityLog[lastIndex] = {
                'timestamp': _activityLog[lastIndex]['timestamp'],
                'message': '✓ ${_activityLog[lastIndex]['message'].toString().replaceFirst('→ ', '')}',
            'status': 'success',
              };
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExecutingCommand = false;
          _lastCommandError = e.toString();
          
          // Check if error mentions directory
          final errorText = e.toString().toLowerCase();
          if (errorText.contains('directory') || errorText.contains('not found')) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: ${e.toString()}'),
                backgroundColor: Colors.red.shade600,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          
          // Update the last log entry to show error
          if (_activityLog.isNotEmpty) {
            final lastIndex = _activityLog.length - 1;
            _activityLog[lastIndex] = {
              'timestamp': _activityLog[lastIndex]['timestamp'],
              'message': '✗ ${_activityLog[lastIndex]['message'].toString().replaceFirst('→ ', '')}',
              'status': 'error',
            };
          }
        });
      }
    }
  }

  Widget _buildQmsContent() {
    if (_selectedBlock == 'Select a block') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            'Please select a block to view QMS dashboard',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ),
      );
    }

    if (_isLoadingQms) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with QMS Dashboard title
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'QMS Dashboard',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        
        // Block Status Summary
        if (_qmsBlockStatus != null) ...[
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Row(
              children: [
                Icon(
                  _qmsBlockStatus!['all_checklists_approved'] == true
                      ? Icons.check_circle
                      : (_qmsBlockStatus!['all_checklists_submitted'] == true
                          ? Icons.pending_actions
                          : Icons.info_outline),
                  color: _qmsBlockStatus!['all_checklists_approved'] == true
                      ? Colors.green
                      : (_qmsBlockStatus!['all_checklists_submitted'] == true
                          ? const Color(0xFF14B8A6)
                          : Colors.orange.shade700),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Block Status',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        _qmsBlockStatus!['all_checklists_approved'] == true
                            ? 'Block Completed'
                            : (_qmsBlockStatus!['all_checklists_submitted'] == true
                                ? 'Block Submitted'
                                : 'Some checklists pending'),
                        style: TextStyle(
                          color: _qmsBlockStatus!['all_checklists_approved'] == true
                              ? Colors.green
                              : (_qmsBlockStatus!['all_checklists_submitted'] == true
                                  ? const Color(0xFF14B8A6)
                                  : Colors.orange.shade700),
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        
        // Checklists List
        Row(
          children: [
            Icon(Icons.folder_open, color: const Color(0xFF14B8A6), size: 24),
            const SizedBox(width: 8),
            Text(
              'Checklists',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF14B8A6).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_qmsChecklists.length}',
                style: TextStyle(
                  color: const Color(0xFF14B8A6),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        if (_qmsChecklists.isEmpty)
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
          ..._qmsChecklists.asMap().entries.map((entry) {
            final checklist = entry.value;
            final status = checklist['status'] ?? 'draft';
            final checklistName = checklist['name'] ?? 'Unnamed Checklist';
            
            // Get approved date - use updated_at when status is approved
            String approvedDateText = 'N/A';
            if (status == 'approved') {
              final updatedAt = checklist['updated_at'];
              if (updatedAt != null) {
                try {
                  final date = updatedAt is DateTime ? updatedAt : DateTime.parse(updatedAt.toString());
                  approvedDateText = DateFormat('MMM dd, yyyy').format(date);
                } catch (e) {
                  approvedDateText = 'N/A';
                }
              }
            }
            
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
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
                  // Checklist Name - Expanded for column alignment
                  Expanded(
                    flex: 3,
                    child: Text(
                      checklistName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8), 
                  // Status - Expanded column
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: QmsStatusBadge(status: status),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Approver Name - Expanded column
                  Expanded(
                    flex: 3,
                    child: Text(
                      checklist['approver_name'] ?? 'N/A',
                      style: TextStyle(
                        fontSize: 12,
                        color: checklist['approver_name'] != null 
                            ? Theme.of(context).colorScheme.onSurface.withOpacity(0.7)
                            : Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                        fontStyle: checklist['approver_name'] != null ? FontStyle.normal : FontStyle.italic,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Approved Date - Expanded column
                  Expanded(
                    flex: 2,
                    child: Text(
                      approvedDateText,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // View Action - Fixed size
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.visibility,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => QmsChecklistDetailScreen(
                            checklistId: checklist['id'],
                          ),
                        ),
                      );
                    },
                    tooltip: 'View Checklist',
                  ),
                ],
              ),
            );
          }).toList(),
      ],
    );
  }

  Widget _buildDevContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Development Environment',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Project: ${widget.project['name'] ?? 'Unknown'}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
            // No Pop Out button for Dev tab
          ],
        ),
        const SizedBox(height: 32),
        // Xterm and GUI Cards
        Row(
          children: [
            Expanded(
              child: _buildDevCard(
                title: 'Xterm',
                description: 'Open inline terminal for command execution',
                icon: Icons.terminal,
                iconColor: const Color(0xFF14B8A6),
                buttonText: 'Click to open',
                onPressed: () {
                  _openTerminalInNewWindow();
                },
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _buildDevCard(
                title: 'GUI',
                description: 'Open remote desktop (VNC) viewer',
                icon: Icons.desktop_windows,
                iconColor: Colors.green,
                buttonText: 'Click to open',
                onPressed: () {
                  _openVncInNewWindow();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        // Development Tools Section
        _buildDevelopmentToolsSection(),
      ],
    );
  }

  Widget _buildDevCard({
    required String title,
    required String description,
    required IconData icon,
    required Color iconColor,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              size: 64,
              color: iconColor,
            ),
          ),
          const SizedBox(height: 24),
          // Title
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          // Description
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 24),
          // Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF87CEEB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(buttonText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDevelopmentToolsSection() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isDevelopmentToolsExpanded = !_isDevelopmentToolsExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _isDevelopmentToolsExpanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Development Tools',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isDevelopmentToolsExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 0, 16, 16),
              child: Text(
                'Access command-line tools for RTL design and verification workflows. The terminal provides access to Yosys for synthesis and OpenROAD for place and route. The GUI viewer displays your design layout and hierarchy visualization.',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showQmsHistoryDialog(int blockId) {
    showDialog(
      context: context,
      builder: (context) => QmsHistoryDialog(blockId: blockId),
    );
  }
}


