import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../providers/error_handler_provider.dart';
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
  late String _selectedTab;
  
  List<String> _availableBlocks = [];
  List<String> _availableExperiments = [];
  bool _isLoadingBlocks = false;
  
  // Store block data with IDs for QMS navigation
  Map<String, int> _blockNameToId = {};
  // Cache: block name -> experiment names (from DB, filled on project open; no extra call when block selected)
  Map<String, List<String>> _blockToExperiments = {};
  
  // Command execution state
  bool _isExecutingCommand = false;
  
  // Chat messages for command console (ChatGPT-like interface)
  final List<Map<String, dynamic>> _chatMessages = [];
  final ScrollController _chatScrollController = ScrollController();
  
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

  // Run directory: loading state so we show "Loading..." only while fetching, not when result is null
  bool _isLoadingRunDirectory = false;
  
  /// Persistent working directory in Command Console (so cd persists across commands like real SSH).
  /// When null, use _currentRunDirectory when block/experiment selected; else home on server.
  String? _consoleWorkingDirectory;
  
  // Development Tools expansion state
  bool _isDevelopmentToolsExpanded = false;

  /// Local project identifier for API calls (DB only, no Zoho). Prefer local id, else project name.
  dynamic get _localProjectIdentifier {
    final rawId = widget.project['id'];
    final source = widget.project['source']?.toString();
    final zohoProjectId = widget.project['zoho_project_id']?.toString();
    final name = widget.project['name']?.toString() ?? '';
    if (rawId is String && rawId.startsWith('zoho_')) return rawId;
    if (source == 'zoho' || (zohoProjectId != null && zohoProjectId.isNotEmpty)) {
      return 'zoho_${zohoProjectId ?? rawId}';
    }
    final isLocalId = rawId is int ||
        (rawId is String && rawId.toString().isNotEmpty && !rawId.toString().startsWith('zoho_'));
    return isLocalId ? rawId : (name.isNotEmpty ? name : rawId);
  }

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab ?? 'Dashboard';
    // Log when project tab is opened (user clicked project card)
    final role = ref.read(authProvider).user?['role']?.toString();
    final projectName = widget.project['name']?.toString();
    print('═══════════════════════════════════════════════════════════');
    print('📂 [PROJECT OPENED] User clicked project card');
    print('   Project: $projectName');
    print('   User role: $role');
    print('═══════════════════════════════════════════════════════════');
    // On project open: only load blocks from DB (one call). Run history and EDA load when user selects block/experiment.
    _loadBlocksAndExperiments();
  }

  @override
  void dispose() {
    _commandController.dispose();
    _chatScrollController.dispose();
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

      final projectIdOrName = _localProjectIdentifier;
      print('🔵 [BLOCKS] Loading blocks from DB only (one call). projectIdOrName: $projectIdOrName');

      // Single DB call: blocks + experiments per block. No EDA, no run history at open.
      final blocksDataList = await _apiService.getBlocksAndExperiments(
        projectIdOrName: projectIdOrName,
        token: token,
      );
      print('🔵 [BLOCKS] API returned ${blocksDataList.length} blocks from DB');

      final blockSet = <String>{};
      final blockToExperiments = <String, List<String>>{};
      for (var blockData in blocksDataList) {
        final blockName = blockData['block_name']?.toString();
        if (blockName == null || blockName.isEmpty) continue;
        blockSet.add(blockName);
        final experiments = blockData['experiments'];
        final expList = <String>[];
        if (experiments is List) {
          for (var exp in experiments) {
            final experiment = exp['experiment']?.toString();
            if (experiment != null && experiment.isNotEmpty) expList.add(experiment);
          }
        }
        expList.sort();
        blockToExperiments[blockName] = expList;
      }

      final finalBlocks = blockSet.toList()..sort();
      print('🔵 [BLOCKS] Block dropdown: ${finalBlocks.length} blocks. Run history / EDA load when user selects block or experiment.');
      print('═══════════════════════════════════════════════════════════');
      setState(() {
        _availableBlocks = finalBlocks;
        _blockToExperiments = blockToExperiments;
        _availableExperiments = []; // Experiments show after user selects a block (from cache)
        _isLoadingBlocks = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingBlocks = false;
      });
      if (mounted) {
        ref.read(errorHandlerProvider.notifier).showError(e, title: 'Failed to load blocks and experiments');
      }
    }
  }

  List<dynamic> _normalizeProjectsResponse(dynamic response) {
    if (response is List) return response;
    if (response is Map) {
      if (response['all'] is List) return response['all'] as List<dynamic>;
      if (response['local'] is List) return response['local'] as List<dynamic>;
    }
    return [];
  }

  Future<void> _loadBlockIds(String projectName, String token) async {
    try {
      // Always request filterByAssigned=true; backend uses project-specific role from user_projects
      // to decide whether to actually filter (engineers get assigned blocks only, admin/manager/lead get all).
      final projectIdOrName = _localProjectIdentifier;
      final blocks = await _apiService.getProjectBlocks(
        projectIdOrName: projectIdOrName,
        filterByAssigned: true,
        token: token,
      );
      if (mounted) {
        final blockMap = <String, int>{};
        for (var block in blocks) {
          if (block is! Map<String, dynamic>) continue;
          final blockName = block['block_name']?.toString() ?? block['name']?.toString();
          final blockId = block['id'];
          if (blockName != null && blockName.isNotEmpty && blockId != null) {
            blockMap[blockName] = blockId is int ? blockId : (int.tryParse(blockId.toString()) ?? 0);
          }
        }
        setState(() {
          _blockNameToId = blockMap;
        });
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

      // Use project ID from card (DB) to avoid extra getProjects round trip
      int? projectId;
      final rawId = widget.project['id'];
      if (rawId != null) {
        if (rawId is int) {
          projectId = rawId;
        } else if (rawId is String && rawId.isNotEmpty && !rawId.toString().startsWith('zoho_')) {
          projectId = int.tryParse(rawId.toString());
        }
      }
      if (projectId == null) {
        // Fallback: resolve by name (e.g. Zoho project)
        final projectName = widget.project['name'] ?? '';
        if (projectName.isEmpty) {
          setState(() {
            _isLoadingRunHistory = false;
            _runHistory = [];
          });
          return;
        }
        final projectsRaw = await _apiService.getProjects(token: token);
        final projects = _normalizeProjectsResponse(projectsRaw);
        try {
          final project = projects.firstWhere(
            (p) => (p['name']?.toString().toLowerCase() ?? '') == projectName.toLowerCase(),
          ) as Map<String, dynamic>?;
          if (project != null && project['id'] != null) {
            projectId = project['id'] is int ? project['id'] as int : int.tryParse(project['id'].toString());
          }
        } catch (_) {}
      }

      if (projectId == null) {
        setState(() {
          _isLoadingRunHistory = false;
          _runHistory = [];
        });
        return;
      }

      // Load run history from DB (single call)
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

  void _onBlockChanged(String? value) async {
    setState(() {
      _selectedBlock = value ?? 'Select a block';
      _selectedExperiment = 'Select an experiment'; // Reset experiment when block changes
      _metricsData = null; // Reset metrics when block changes
      _currentRunDirectory = null;
      _isLoadingRunDirectory = false;
      _qmsChecklists = [];
      _qmsBlockStatus = null;
      _consoleWorkingDirectory = null; // Reset so next commands use new run directory
    });
    
    // Show experiments for the selected block (from DB cache; no extra API call)
    if (_selectedBlock != 'Select a block') {
      final experiments = _blockToExperiments[_selectedBlock] ?? [];
      setState(() {
        _availableExperiments = List<String>.from(experiments);
      });
      // Load block IDs for QMS only when needed (first time a block is selected)
      final token = ref.read(authProvider).token;
      if (_blockNameToId.isEmpty && token != null) {
        final projectName = widget.project['name']?.toString() ?? '';
        if (projectName.isNotEmpty) _loadBlockIds(projectName, token);
      }
      if (_selectedTab == 'QMS') _loadQmsData();
    } else {
      setState(() {
        _availableExperiments = [];
      });
    }
    // Load run history only when user selects block (DB only)
    _loadRunHistory();
  }
  
  void _onExperimentChanged(String? value) async {
    setState(() {
      _selectedExperiment = value ?? 'Select an experiment';
      _currentRunDirectory = null;
      _isLoadingRunDirectory = false; // Will be set true when _loadRunDirectory runs
      _consoleWorkingDirectory = null; // Reset so next commands use new run directory
    });
    
    // Load metrics and run directory when experiment is selected
    if (_selectedBlock != 'Select a block' && _selectedExperiment != 'Select an experiment') {
      // Load run directory first so it's available for command console
      await _loadRunDirectory();
      _loadMetricsData(); // This will also load the run directory
    }
    
    // Reload run history with new experiment filter
    _loadRunHistory();
  }

  Future<void> _loadRunDirectory() async {
    if (_selectedBlock == 'Select a block' || _selectedExperiment == 'Select an experiment') {
      return;
    }

    final token = ref.read(authProvider).token;
    if (token == null) return;

    final projectName = widget.project['name'] ?? '';
    if (projectName.isEmpty) return;

    if (mounted) setState(() => _isLoadingRunDirectory = true);

    try {
      String? runDirectoryFromBlockUser;
      String? runDirectoryFromExperiment;

      // Run directory from DB only: block_users (per block per user) then runs (per experiment). No EDA files.
      try {
        final blocksData = await _apiService.getBlocksAndExperiments(
          projectIdOrName: _localProjectIdentifier,
          token: token,
        );

        for (var blockData in blocksData) {
          final blockName = blockData['block_name']?.toString();
          if (blockName != _selectedBlock) continue;

          // 1) block_users.run_directory (set when engineer completes setup)
          final blockUserRunDir = blockData['block_user_run_directory']?.toString();
          if (blockUserRunDir != null && blockUserRunDir.isNotEmpty) {
            runDirectoryFromBlockUser = blockUserRunDir;
          }

          // 2) runs.run_directory for this experiment (fallback)
          final experiments = blockData['experiments'];
          if (experiments is List) {
            for (var exp in experiments) {
              final experiment = exp['experiment']?.toString();
              if (experiment == _selectedExperiment) {
                final runDir = exp['run_directory']?.toString();
                if (runDir != null && runDir.isNotEmpty) {
                  runDirectoryFromExperiment = runDir;
                  break;
                }
              }
            }
          }
          break;
        }
      } catch (e) {
        print('Error loading run directory from DB: $e');
      }

      final finalRunDirectory = runDirectoryFromBlockUser ?? runDirectoryFromExperiment;
      if (mounted) {
        setState(() {
          _currentRunDirectory = (finalRunDirectory != null && finalRunDirectory.isNotEmpty) ? finalRunDirectory : null;
          _isLoadingRunDirectory = false;
        });
      }
    } catch (e) {
      print('Error loading run directory: $e');
      if (mounted) {
        setState(() {
          _currentRunDirectory = null;
          _isLoadingRunDirectory = false;
        });
      }
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
          _isLoadingMetrics = false;
        });
        return;
      }

      // Get the latest stage (by timestamp or stage order). Run directory comes only from DB (_loadRunDirectory), not EDA.
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
        ref.read(errorHandlerProvider.notifier).showError(e, title: 'Failed to load metrics');
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

  Future<void> _openQMSInNewWindow() async {
    try {
      // Check if a block is selected
      final blockId = _blockNameToId[_selectedBlock];
      if (blockId == null || _selectedBlock == null || _selectedBlock == 'Select a block') {
        if (mounted) {
          ref.read(errorHandlerProvider.notifier).showInfo('Please select a block to view QMS dashboard');
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
        ref.read(errorHandlerProvider.notifier).showError(e, title: 'Failed to open QMS dashboard');
      }
    }
  }

  Future<void> _openTerminalInNewWindow() async {
    try {
      final token = ref.read(authProvider).token;
      final user = ref.read(authProvider).user;
      
      if (token == null) {
        if (mounted) {
          ref.read(errorHandlerProvider.notifier).showInfo(
            'Not authenticated. Please login again.',
            title: 'Login required',
          );
        }
        return;
      }

      // Store auth data in localStorage so the new window can read it (must happen before open)
      html.window.localStorage['terminal_auth_token'] = token;
      if (user != null) {
        html.window.localStorage['terminal_auth_user'] = jsonEncode(user);
      }
      
      final currentUrl = html.window.location.href;
      final baseUrl = currentUrl.split('?')[0].split('#')[0];
      final terminalUrl = '$baseUrl#/terminal';
      
      // Reuse existing terminal window if already open (same name 'terminal')
      html.window.open(
        terminalUrl,
        'terminal',
        'width=1200,height=800,scrollbars=no,resizable=yes',
      );
    } catch (e) {
      if (mounted) {
        ref.read(errorHandlerProvider.notifier).showError(e, title: 'Failed to open terminal');
      }
    }
  }

  Future<void> _openVncInNewWindow() async {
    try {
      final token = ref.read(authProvider).token;
      final user = ref.read(authProvider).user;
      
      if (token == null) {
        if (mounted) {
          ref.read(errorHandlerProvider.notifier).showInfo(
            'Not authenticated. Please login again.',
            title: 'Login required',
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
        ref.read(errorHandlerProvider.notifier).showError(e, title: 'Failed to open VNC viewer');
      }
    }
  }
  
  Future<void> _openViewScreenInNewWindow() async {
    try {
      // Project and domain from DB only (no Zoho, no EDA files)
      final projectName = widget.project['name'] ?? '';
      if (projectName.isEmpty) {
        if (mounted) {
          ref.read(errorHandlerProvider.notifier).showInfo(
            'Project name not available.',
            title: 'Info',
          );
        }
        return;
      }

      // Use domain of the selected block/run when available (e.g. from metrics/EDA), else first project domain.
      // Passing wrong domain (e.g. first project domain) would show wrong domain in popout until user changes it.
      String? domainName;
      if (_selectedBlock != 'Select a block' &&
          _metricsData != null &&
          _metricsData!['domain_name'] != null &&
          _metricsData!['domain_name'].toString().trim().isNotEmpty) {
        domainName = _metricsData!['domain_name']?.toString();
      }
      if ((domainName == null || domainName.isEmpty) &&
          _selectedBlock != 'Select a block' &&
          _selectedExperiment != 'Select an experiment') {
        try {
          final token = ref.read(authProvider).token;
          if (token != null) {
            final filesResponse = await _apiService.getEdaFiles(
              token: token,
              projectName: projectName,
              limit: 100,
            );
            final files = filesResponse['files'] ?? [];
            for (var file in files) {
              if (file['block_name']?.toString() == _selectedBlock &&
                  file['experiment']?.toString() == _selectedExperiment) {
                final d = file['domain_name']?.toString();
                if (d != null && d.trim().isNotEmpty) {
                  domainName = d;
                  break;
                }
              }
            }
          }
        } catch (_) {}
      }
      if (domainName == null || domainName.isEmpty) {
        final domains = widget.project['domains'];
        if (domains is List && domains.isNotEmpty) {
          final firstDomain = domains.first;
          if (firstDomain is Map) {
            domainName = firstDomain['name']?.toString();
          }
        }
      }

      // Default view type by role: admin -> manager, customer -> customer, else engineer
      final userRole = ref.read(authProvider).user?['role']?.toString();
      final viewType = userRole == 'admin'
          ? 'manager'
          : (userRole == 'customer' ? 'customer' : 'engineer');

      // Pass selected block and experiment so popout auto-selects them in engineer view
      final blockName = (_selectedBlock != null && _selectedBlock != 'Select a block' && _selectedBlock.isNotEmpty)
          ? _selectedBlock
          : null;
      final experimentName = (_selectedExperiment != null && _selectedExperiment != 'Select an experiment' && _selectedExperiment.isNotEmpty)
          ? _selectedExperiment
          : null;

      // Store data in localStorage for the new window
      final viewData = {
        'project': projectName,
        if (domainName != null && domainName.isNotEmpty) 'domain': domainName,
        'viewType': viewType,
        if (blockName != null) 'block': blockName,
        if (experimentName != null) 'experiment': experimentName,
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
      if (blockName != null) {
        newWindowUrl += '&block=${Uri.encodeComponent(blockName)}';
      }
      if (experimentName != null) {
        newWindowUrl += '&experiment=${Uri.encodeComponent(experimentName)}';
      }
      
      html.window.open(
        newWindowUrl,
        'view_${projectName.replaceAll(' ', '_')}',
        'width=1600,height=1000,scrollbars=yes,resizable=yes',
      );
    } catch (e) {
      if (mounted) {
        ref.read(errorHandlerProvider.notifier).showError(e, title: 'Failed to open view window');
      }
    }
  }

  /// Fixed ratio: 50% left, 50% right.
  static const int _kLeftPanelFlex = 50;
  static const int _kRightPanelFlex = 50;
  /// Max width for the whole two-panel layout so it stays centered on very wide screens.
  static const double _kLayoutMaxWidth = 1600.0;
  /// Minimum width for each panel so content stays usable.
  static const double _kPanelMinWidth = 320.0;
  /// Horizontal margin so both sections sit in the middle with visible space on left and right.
  static const double _kHorizontalPadding = 32.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - (_kHorizontalPadding * 2);
        final layoutWidth = availableWidth > _kLayoutMaxWidth
            ? _kLayoutMaxWidth
            : availableWidth;

        // Use flex ratio so left and right share space 50/50
        final totalFlex = _kLeftPanelFlex + _kRightPanelFlex;
        var leftWidth = layoutWidth * (_kLeftPanelFlex / totalFlex);
        var rightWidth = layoutWidth * (_kRightPanelFlex / totalFlex);
        if (leftWidth < _kPanelMinWidth) {
          leftWidth = _kPanelMinWidth;
          rightWidth = layoutWidth - leftWidth;
        } else if (rightWidth < _kPanelMinWidth) {
          rightWidth = _kPanelMinWidth;
          leftWidth = layoutWidth - rightWidth;
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kHorizontalPadding),
          child: Center(
            child: SizedBox(
              width: layoutWidth,
              child: Row(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left Panel — Context & Command Console (50%)
                  SizedBox(
                    width: leftWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLowest,
                      border: Border(
                        right: BorderSide(
                          color: theme.dividerColor.withOpacity(0.8),
                          width: 1.5,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(2, 0),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Section header for left panel
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.tune,
                                size: 20,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Context & Console',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface.withOpacity(0.85),
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildSelectionSection(),
                                _buildRunDirectoryInfo(),
                                const SizedBox(height: 20),
                                _buildCommandConsole(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Right Panel — Dashboard / QMS / Dev (50%)
                SizedBox(
                  width: rightWidth,
                  child: Container(
                    color: theme.scaffoldBackgroundColor,
                    child: Column(
                      children: [
                        // Tabs bar with clear separation
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            border: Border(
                              bottom: BorderSide(
                                color: theme.dividerColor,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              _buildDashboardTab('Dashboard', Icons.grid_view, isSelected: _selectedTab == 'Dashboard'),
                              _buildDashboardTab('QMS', Icons.check_circle_outline, isSelected: _selectedTab == 'QMS'),
                              _buildDashboardTab('<> Dev', Icons.code, isSelected: _selectedTab == '<> Dev'),
                            ],
                          ),
                        ),
                        Expanded(
                          child: _buildMainContent(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        );
      },
    );
  }

  Widget _buildSelectionSection() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Block & Experiment',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withOpacity(0.75),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Block',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: _isLoadingBlocks
                          ? const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedBlock,
                                isExpanded: true,
                                isDense: true,
                                style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
                                dropdownColor: theme.cardColor,
                                items: [
                                  DropdownMenuItem(
                                    value: 'Select a block',
                                    child: Text('Select a block', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6))),
                                  ),
                                  ..._availableBlocks.map((block) => DropdownMenuItem(
                                        value: block,
                                        child: Text(block, style: TextStyle(color: theme.colorScheme.onSurface)),
                                      )),
                                ],
                                onChanged: _onBlockChanged,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Experiment',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedExperiment,
                          isExpanded: true,
                          isDense: true,
                          style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
                          dropdownColor: theme.cardColor,
                          items: [
                            DropdownMenuItem(
                              value: 'Select an experiment',
                              child: Text('Select an experiment', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6))),
                            ),
                            ..._availableExperiments.map((exp) => DropdownMenuItem(
                                  value: exp,
                                  child: Text(exp, style: TextStyle(color: theme.colorScheme.onSurface)),
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
          ),
        ],
      ),
    );
  }

  Widget _buildRunDirectoryInfo() {
    if (_selectedBlock == 'Select a block' || _selectedExperiment == 'Select an experiment') {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.folder_open,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Run Directory',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withOpacity(0.75),
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  _isLoadingRunDirectory
                      ? 'Loading...'
                      : (_currentRunDirectory ?? 'No run directory set'),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface,
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
              style: IconButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
              ),
            ),
        ],
      ),
    );
  }

  // Mac terminal / block UI colors for Command Console
  static const Color _kConsoleBg = Color(0xFF1E1E2E);
  static const Color _kConsoleHeader = Color(0xFF2D2D3A);
  static const Color _kConsoleText = Color(0xFFE6EDF3);
  static const Color _kConsoleTextMuted = Color(0xFF8B949E);
  static const Color _kConsoleAccent = Color(0xFF7EE787);
  static const Color _kConsoleError = Color(0xFFF85149);
  static const Color _kConsoleBubbleBot = Color(0xFF2D2D3A);
  static const Color _kConsoleInputBg = Color(0xFF252526);

  Widget _buildCommandConsole() {
    final theme = Theme.of(context);
    return Container(
      height: 560,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: _kConsoleBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kConsoleTextMuted.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildChatHeader(theme),
          Expanded(
            child: Container(
              width: double.infinity,
              color: _kConsoleBg,
              child: _chatMessages.isEmpty
                  ? _buildChatEmptyState(theme)
                  : ListView.builder(
                      controller: _chatScrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: _chatMessages.length,
                      itemBuilder: (context, index) {
                        return _buildChatMessage(context, theme, _chatMessages[index]);
                      },
                    ),
            ),
          ),
          _buildChatInput(theme),
        ],
      ),
    );
  }

  Widget _buildChatHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: _kConsoleHeader,
        border: Border(bottom: BorderSide(color: Color(0xFF3D3D4A), width: 1)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: _kConsoleAccent.withOpacity(0.2),
            child: Icon(Icons.terminal, size: 20, color: _kConsoleAccent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Command Console',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: _kConsoleText,
                  ),
                ),
                Text(
                  'Remote SSH · Commands run on server',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _kConsoleTextMuted,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            icon: Icon(Icons.open_in_new, size: 16, color: _kConsoleAccent),
            label: Text('Full terminal', style: TextStyle(fontSize: 12, color: _kConsoleAccent)),
            onPressed: _openTerminalInNewWindow,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          if (_chatMessages.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_outline, size: 20, color: _kConsoleTextMuted),
              onPressed: () => setState(() => _chatMessages.clear()),
              tooltip: 'Clear chat',
              style: IconButton.styleFrom(
                padding: const EdgeInsets.all(8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChatEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 56,
              color: _kConsoleAccent.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Send a command to run on the remote server',
              style: theme.textTheme.titleSmall?.copyWith(
                color: _kConsoleText,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Select block & experiment to run in that directory,\nor type a command below (runs in home if not set).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _kConsoleTextMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatMessage(BuildContext context, ThemeData theme, Map<String, dynamic> message) {
    final isUser = message['type'] == 'user';
    final isExecuting = message['isExecuting'] == true;
    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _kConsoleAccent.withOpacity(0.25),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(4),
                  ),
                  border: Border.all(color: _kConsoleAccent.withOpacity(0.4)),
                ),
                child: SelectableText(
                  message['command'] ?? '',
                  style: const TextStyle(
                    fontSize: 13,
                    color: _kConsoleText,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 14,
              backgroundColor: _kConsoleAccent.withOpacity(0.3),
              child: Icon(Icons.person, size: 16, color: _kConsoleAccent),
            ),
          ],
        ),
      );
    }
    if (isExecuting) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: _kConsoleBubbleBot,
              child: Icon(Icons.terminal, size: 16, color: _kConsoleAccent),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _kConsoleBubbleBot,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _kConsoleAccent),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Running on server...',
                    style: theme.textTheme.bodySmall?.copyWith(color: _kConsoleTextMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final hasError = message['hasError'] == true;
    final output = message['output']?.toString() ?? '';
    final error = message['error']?.toString() ?? '';
    final noOutput = output.isEmpty && error.isEmpty && !hasError;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: _kConsoleBubbleBot,
            child: Icon(
              hasError ? Icons.error_outline : Icons.terminal,
              size: 16,
              color: hasError ? _kConsoleError : _kConsoleAccent,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _kConsoleBubbleBot,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
                border: hasError
                    ? Border.all(color: _kConsoleError.withOpacity(0.6), width: 1)
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (output.isNotEmpty)
                    SelectableText(
                      output,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: hasError ? _kConsoleError : _kConsoleText,
                      ),
                    ),
                  if (error.isNotEmpty)
                    SelectableText(
                      error,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: _kConsoleError,
                      ),
                    ),
                  if (noOutput)
                    Text(
                      'Command completed (no output)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: _kConsoleTextMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatInput(ThemeData theme) {
    final effectiveCwd = _consoleWorkingDirectory ??
        (_currentRunDirectory != null &&
                _currentRunDirectory!.isNotEmpty &&
                _selectedBlock != 'Select a block' &&
                _selectedExperiment != 'Select an experiment'
            ? _currentRunDirectory
            : null);
    final workingDirLabel = effectiveCwd != null
        ? (effectiveCwd.length > 45 ? '...${effectiveCwd.substring(effectiveCwd.length - 45)}' : effectiveCwd)
        : 'Home on server';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: _kConsoleBg,
        border: Border(top: BorderSide(color: Color(0xFF3D3D4A), width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Working directory: $workingDirLabel',
              style: theme.textTheme.labelSmall?.copyWith(color: _kConsoleTextMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _commandController,
                  maxLines: 3,
                  minLines: 1,
                  maxLength: 500,
                  style: const TextStyle(color: _kConsoleText, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Message Command Console...',
                    hintStyle: TextStyle(color: _kConsoleTextMuted.withOpacity(0.8)),
                    filled: true,
                    fillColor: _kConsoleInputBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: _kConsoleTextMuted.withOpacity(0.3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: _kConsoleTextMuted.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: _kConsoleAccent, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    counterText: '',
                  ),
                  onChanged: (value) => setState(() {}),
                  onSubmitted: (value) {
                    if (value.isNotEmpty && !_isExecutingCommand) {
                      _executeCommand(value);
                      _commandController.clear();
                      setState(() {});
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: _commandController.text.isNotEmpty && !_isExecutingCommand
                    ? _kConsoleAccent
                    : _kConsoleBubbleBot,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _isExecutingCommand
                      ? null
                      : () {
                          if (_commandController.text.isNotEmpty) {
                            _executeCommand(_commandController.text);
                            _commandController.clear();
                            setState(() {});
                          }
                        },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _isExecutingCommand
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _kConsoleText,
                            ),
                          )
                        : Icon(
                            Icons.send_rounded,
                            size: 24,
                            color: _commandController.text.isNotEmpty
                                ? _kConsoleBg
                                : _kConsoleTextMuted,
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
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pop Out button (no title section)
          if (_selectedTab != '<> Dev')
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: TextButton.icon(
                      onPressed: () {
                        if (_selectedTab == 'Dashboard') {
                          if (_selectedBlock == 'Select a block' || _selectedExperiment == 'Select an experiment') {
                            ref.read(errorHandlerProvider.notifier).showInfo(
                              'Please select a block and experiment to pop out the dashboard',
                            );
                            return;
                          }
                          if (_metricsData == null && _runHistory.isEmpty) {
                            ref.read(errorHandlerProvider.notifier).showInfo(
                              'No data to show. Pop out is only available when there is dashboard data for the selected block and experiment.',
                            );
                            return;
                          }
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
            ),

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
        ref.read(errorHandlerProvider.notifier).showError(e, title: 'Failed to load QMS data');
      }
    }
  }

  Widget _buildDashboardTab(String label, IconData icon, {required bool isSelected}) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedTab = label;
        });
        if (label == 'QMS' && _selectedBlock != 'Select a block') {
          _loadQmsData();
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: isSelected ? primary.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border(bottom: BorderSide(color: primary, width: 2.5))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? primary : theme.colorScheme.onSurface.withOpacity(0.65),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: isSelected ? primary : theme.colorScheme.onSurface.withOpacity(0.75),
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
      crossAxisSpacing: 20,
      mainAxisSpacing: 20,
      childAspectRatio: 1.35,
      children: [
        _buildMetricCard(
          'Gate Count',
          gateCount,
          Icons.memory,
          subtitle: tech,
          accentColor: _metricCardColors[0],
        ),
        _buildMetricCard(
          'Area',
          area,
          Icons.square_foot,
          subtitle: utilization != null ? 'Utilization: ${utilization.toStringAsFixed(1)}%' : 'Utilization: N/A',
          accentColor: _metricCardColors[1],
        ),
        _buildMetricCard(
          'Power',
          power,
          Icons.power,
          subtitle: frequency != 'N/A' ? '@ $frequency' : 'N/A',
          accentColor: _metricCardColors[2],
        ),
        _buildMetricCard(
          'Frequency',
          frequency,
          Icons.speed,
          subtitle: timingSlack != 'N/A' ? 'Timing: $timingSlack' : 'Timing: N/A',
          accentColor: _metricCardColors[3],
        ),
        _buildMetricCardWithProgress(
          'Utilization',
          utilization != null ? '${utilization.toStringAsFixed(1)}%' : 'N/A',
          Icons.pie_chart,
          utilization != null ? (utilization / 100).clamp(0.0, 1.0) : 0.0,
          accentColor: _metricCardColors[4],
        ),
        _buildMetricCard(
          'Timing Slack',
          timingSlack,
          Icons.timer,
          subtitle: 'WNS (Worst Negative Slack)',
          accentColor: _metricCardColors[5],
        ),
        _buildMetricCard(
          'Interface Timing',
          interfaceTiming,
          Icons.swap_horiz,
          subtitle: 'I2R / R2O WNS',
          accentColor: _metricCardColors[6],
        ),
      ],
    );
  }

  static const List<Color> _metricCardColors = [
    Color(0xFF2563EB), // Gate Count - blue
    Color(0xFF0D9488), // Area - teal
    Color(0xFFD97706), // Power - amber
    Color(0xFF7C3AED), // Frequency - violet
    Color(0xFF059669), // Utilization - emerald
    Color(0xFFEA580C), // Timing Slack - orange
    Color(0xFF0891B2), // Interface Timing - cyan
  ];

  Widget _buildMetricCard(String title, String value, IconData icon, {String? subtitle, Color? accentColor}) {
    final color = accentColor ?? Theme.of(context).colorScheme.primary;
    final dividerColor = Theme.of(context).dividerColor.withOpacity(0.5);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dividerColor),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          letterSpacing: 0.2,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, size: 20, color: color),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                      letterSpacing: -0.5,
                      height: 1.2,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCardWithProgress(String title, String value, IconData icon, double progress, {Color? accentColor}) {
    final color = accentColor ?? Theme.of(context).colorScheme.primary;
    final dividerColor = Theme.of(context).dividerColor.withOpacity(0.5);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dividerColor),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          letterSpacing: 0.2,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, size: 20, color: color),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                      letterSpacing: -0.5,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: color.withOpacity(0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            ),
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
    final runDirectory = _currentRunDirectory;
    
    setState(() {
      _isExecutingCommand = true;
      
      // Add user message (command) to chat
      _chatMessages.add({
        'type': 'user',
        'command': command,
        'directory': runDirectory,
        'timestamp': DateTime.now(),
      });
      
          // Add assistant message (executing) to chat
      _chatMessages.add({
        'type': 'assistant',
        'isExecuting': true,
        'timestamp': DateTime.now(),
      });
    });
    
    // Scroll to bottom after adding message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    try {
      final token = ref.read(authProvider).token;
      if (token == null) {
        throw Exception('Not authenticated');
      }

      // Effective cwd: console state, or run directory when block/experiment selected (like real SSH)
      String? effectiveWorkingDir = _consoleWorkingDirectory;
      if (effectiveWorkingDir == null &&
          _currentRunDirectory != null &&
          _currentRunDirectory!.isNotEmpty &&
          _selectedBlock != 'Select a block' &&
          _selectedExperiment != 'Select an experiment') {
        effectiveWorkingDir = _currentRunDirectory;
      }

      final trimmedCmd = command.trim();
      final isCdCommand = trimmedCmd.startsWith('cd ') && trimmedCmd.length > 3;
      final commandToRun = isCdCommand ? '$trimmedCmd && pwd' : command;

      final result = await _apiService.executeSSHCommand(
        command: commandToRun,
        token: token,
        workingDirectory: effectiveWorkingDir,
      );

      if (mounted) {
        setState(() {
          _isExecutingCommand = false;
          final stdout = result['stdout']?.toString();
          final stderr = result['stderr']?.toString();

          // If user ran "cd ...", persist the new directory (last line of pwd output) so next commands run there
          if (isCdCommand && stdout != null && stdout.trim().isNotEmpty) {
            final lines = stdout.trim().split(RegExp(r'\r?\n'));
            final lastLine = lines.isNotEmpty ? lines.last.trim() : '';
            if (lastLine.isNotEmpty && lastLine.startsWith('/')) {
              _consoleWorkingDirectory = lastLine;
            }
          }

          final errorText = stderr?.toLowerCase() ?? '';
          if (errorText.contains('directory') && errorText.contains('does not exist')) {
            ref.read(errorHandlerProvider.notifier).show(
              'Run directory not found',
              'Run directory not found on server: $_currentRunDirectory',
            );
          }

          final exitCode = result['exitCode'];
          final hasError = exitCode != null && exitCode != 0;
          final displayOutput = isCdCommand && stdout != null && stdout.trim().isNotEmpty
              ? stdout.trim().split(RegExp(r'\r?\n')).last
              : stdout;

          if (_chatMessages.isNotEmpty && _chatMessages.last['isExecuting'] == true) {
            _chatMessages[_chatMessages.length - 1] = {
              'type': 'assistant',
              'isExecuting': false,
              'output': displayOutput,
              'error': stderr,
              'hasError': hasError,
              'exitCode': exitCode,
              'timestamp': DateTime.now(),
            };
          }
        });
        
        // Scroll to bottom after updating message
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_chatScrollController.hasClients) {
            _chatScrollController.animateTo(
              _chatScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExecutingCommand = false;
          final errorText = e.toString().toLowerCase();
          if (errorText.contains('directory') || errorText.contains('not found')) {
            ref.read(errorHandlerProvider.notifier).showError(e, title: 'Error');
          } else if (errorText.contains('ssh') || errorText.contains('connection') || errorText.contains('credentials') || errorText.contains('not configured')) {
            ref.read(errorHandlerProvider.notifier).showError(e, title: 'Remote SSH — configure server, user, and password in your profile');
          }
          String displayError = e.toString();
          if (errorText.contains('credentials not configured') || errorText.contains('ssh credentials')) {
            displayError = '$displayError\n\nConfigure SSH server, user, and password in your profile so commands run on the remote server.';
          }
          if (_chatMessages.isNotEmpty && _chatMessages.last['isExecuting'] == true) {
            _chatMessages[_chatMessages.length - 1] = {
              'type': 'assistant',
              'isExecuting': false,
              'output': null,
              'error': displayError,
              'hasError': true,
              'timestamp': DateTime.now(),
            };
          }
        });
        
        // Scroll to bottom after updating message
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_chatScrollController.hasClients) {
            _chatScrollController.animateTo(
              _chatScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
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


