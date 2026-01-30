import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

List<dynamic> _projectsFromMap(Map<dynamic, dynamic> m) {
  final raw = m['all'] ?? m['local'] ?? <dynamic>[];
  return raw is List ? List<dynamic>.from(raw) : <dynamic>[];
}

final dashboardProvider = StateNotifierProvider<DashboardNotifier, AsyncValue<Map<String, dynamic>>>(
  (ref) {
    final apiService = ref.read(apiServiceProvider);
    final authState = ref.watch(authProvider);
    final notifier = DashboardNotifier(apiService, token: authState.token);
    // Keep the provider alive to cache data
    ref.keepAlive();
    return notifier;
  },
);

class DashboardNotifier extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  final ApiService _apiService;
  final String? _token;
  bool _isLoading = false;

  DashboardNotifier(this._apiService, {String? token}) 
      : _token = token,
        super(const AsyncValue.data({})) {
    // Don't load immediately - lazy load when first accessed
  }

  Future<void> loadStats({bool force = false}) async {
    // Prevent duplicate loads
    if (_isLoading && !force) return;
    if (!force && state.hasValue && state.value != null && state.value!.isNotEmpty) {
      return; // Already loaded
    }
    
    _isLoading = true;
    state = const AsyncValue.loading();
    try {
      // Fetch data from real endpoints in parallel (including users with error handling)
      final results = await Future.wait([
        _apiService.getProjects(token: _token),
        _apiService.getDomains(token: _token),
        _apiService.getDesigns(),
        _apiService.getChips(),
        // Fetch users in parallel with error handling
        _apiService.getUsers(token: _token).catchError((e) {
          print('Could not fetch users: $e');
          return <dynamic>[]; // Return empty list on error
        }),
      ]);
      
      // Projects API may return List or Map (e.g. { all, local, zoho } for Zoho integration; admin gets Zoho only)
      final projectsRaw = results[0];
      final List<dynamic> projects = projectsRaw is List
          ? List<dynamic>.from(projectsRaw as List)
          : (projectsRaw is Map)
              ? _projectsFromMap(projectsRaw as Map)
              : <dynamic>[];
      final domainsRaw = results[1];
      final domains = domainsRaw is List ? List<dynamic>.from(domainsRaw) : <dynamic>[];
      final designs = results[2] as List<dynamic>;
      final chips = results[3] as List<dynamic>;
      final users = results[4] as List<dynamic>;

      // Filter to only engineers
      final engineers = users.where((user) => 
        user['role']?.toString().toLowerCase() == 'engineer'
      ).toList();
      final totalEngineers = engineers.length;

      // Calculate Project Stats
      final totalProjects = projects.length;
      
      // Calculate project status counts (running, completed, failed)
      int running = 0;
      int completed = 0;
      int failed = 0;
      
      for (var project in projects) {
        final status = (project['status'] ?? '').toString().toUpperCase();
        if (status == 'RUNNING') {
          running++;
        } else if (status == 'COMPLETED') {
          completed++;
        } else if (status == 'FAILED') {
          failed++;
        }
      }
      
      // Calculate Domain Stats - count unique active domains (normalize to handle typos)
      final uniqueDomains = <String>{};
      final domainDebugList = <String>[];
      for (var d in domains) {
        final name = d['name'] as String?;
        final isActive = d['is_active'] as bool? ?? true;
        if (name != null && name.isNotEmpty && isActive) {
          // Normalize domain name to group typos together
          final normalized = _normalizeDomainName(name);
          // Only add if normalization returned a valid domain (not empty)
          if (normalized.isNotEmpty) {
            uniqueDomains.add(normalized);
            domainDebugList.add('"$name" -> "$normalized"');
          } else {
            domainDebugList.add('"$name" -> SKIPPED (invalid)');
          }
        }
      }
      final totalDomains = uniqueDomains.length;
      
      // Debug: Print all domains for troubleshooting
      print('📊 [DOMAIN COUNT] Total domains from API: ${domains.length}');
      print('📊 [DOMAIN COUNT] Unique normalized domains: $totalDomains');
      print('📊 [DOMAIN COUNT] Domain mappings: ${domainDebugList.join(", ")}');
      print('📊 [DOMAIN COUNT] Unique normalized list: ${uniqueDomains.toList()}');

      // Construct the stats object expected by the UI
      final stats = {
        'projects': {
          'total': totalProjects,
          'running': running,
          'completed': completed,
          'failed': failed,
          'list': projects, // Pass the full list for displaying Recent Projects
        },
        'domains': {
          'total': totalDomains,
        },
        'engineers': {
          'total': totalEngineers,
          'list': engineers, // Expose only engineers list
        },
        'chips': {
          'total': chips.length,
          'byStatus': _calculateStatusCounts(chips),
        },
        'designs': {
          'total': designs.length,
          'byStatus': _calculateStatusCounts(designs),
        }
      };

      state = AsyncValue.data(stats);
    } catch (e, stack) {
      // Fallback to getDashboardStats if individual calls fail, or just show error
      print('Error calculating dashboard stats: $e');
      try {
         // Attempt to use the backend aggregator as fallback
         final stats = await _apiService.getDashboardStats();
         state = AsyncValue.data(stats);
      } catch (fallbackError) {
         state = AsyncValue.error(e, stack);
      }
    }
  }

  Map<String, int> _calculateStatusCounts(List<dynamic> items) {
    final counts = <String, int>{};
    for (var item in items) {
      final status = (item['status'] as String?)?.toLowerCase() ?? 'unknown';
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> refresh() async {
    await loadStats();
  }
}

final chipsProvider = FutureProvider<List<dynamic>>((ref) async {
  final apiService = ref.read(apiServiceProvider);
  return await apiService.getChips();
});

final designsProvider = FutureProvider<List<dynamic>>((ref) async {
  final apiService = ref.read(apiServiceProvider);
  return await apiService.getDesigns();
});









final dashboardChartDataProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final authState = ref.watch(authProvider);
  final token = authState.token;
  final apiService = ref.read(apiServiceProvider);

  if (token == null && authState.isAuthenticated == false) {
    return {
      'domainDistribution': <String, int>{},
      'projectTrend': <Map<String, dynamic>>[],
    };
  }
  
  try {
    // Fetch projects and domains in parallel
    final results = await Future.wait([
      apiService.getProjects(token: token),
      apiService.getDomains(token: token),
    ]);
    
    // Projects API may return List or Map (e.g. { all, local, zoho }; admin gets Zoho only)
    final projectsRaw = results[0];
    final List<dynamic> projects = projectsRaw is List
        ? List<dynamic>.from(projectsRaw as List)
        : (projectsRaw is Map)
            ? _projectsFromMap(projectsRaw as Map)
            : <dynamic>[];
    final domainsRaw = results[1];
    final domains = domainsRaw is List ? List<dynamic>.from(domainsRaw) : <dynamic>[];
    
    // Only fetch EDA files if domain distribution from projects is empty
    // This significantly reduces load time by avoiding unnecessary large fetches
    Map<String, int> edaDomainCounts = <String, int>{};
    
    // First, try to calculate domain distribution from projects
    final domainCountsFromProjects = <String, int>{};
    final domainNames = {for (var d in domains) d['id']: d['name']};
    
    for (var p in projects) {
      final pDomains = p['domain_ids'];
      if (pDomains is List && pDomains.isNotEmpty) {
        for (var id in pDomains) {
          final name = domainNames[id] ?? '';
          if (name.isNotEmpty) {
            domainCountsFromProjects[name] = (domainCountsFromProjects[name] ?? 0) + 1;
          }
        }
      } else if (p['domains'] is List && (p['domains'] as List).isNotEmpty) {
        for (var d in p['domains']) {
          final name = d['name']?.toString() ?? '';
          if (name.isNotEmpty) {
            domainCountsFromProjects[name] = (domainCountsFromProjects[name] ?? 0) + 1;
          }
        }
      }
    }
    
    // Only fetch EDA files if we don't have enough domain data from projects
    // Use a much smaller limit (100 instead of 1000) for faster loading
    if (domainCountsFromProjects.isEmpty) {
      try {
        final edaFilesResponse = await apiService.getEdaFiles(token: token, limit: 100);
        final edaFiles = edaFilesResponse['files'] ?? [];
        
        // Count domains from EDA files (will be normalized in _calculateChartData)
        for (var file in edaFiles) {
          final domainName = file['domain_name'] as String?;
          if (domainName != null && domainName.isNotEmpty) {
            edaDomainCounts[domainName] = (edaDomainCounts[domainName] ?? 0) + 1;
          }
        }
        
        if (edaDomainCounts.isNotEmpty) {
          print('✅ [DOMAIN CHART] Found ${edaDomainCounts.length} domains from EDA files: $edaDomainCounts');
        }
      } catch (e) {
        print('⚠️ [DOMAIN CHART] Could not fetch EDA files for domain distribution: $e');
      }
    } else {
      print('✅ [DOMAIN CHART] Using domain data from projects (${domainCountsFromProjects.length} domains)');
    }
    
    return _calculateChartData(projects, domains, edaDomainCounts);
  } catch (e) {
    print('Error loading chart data: $e');
    // Return empty data on error to avoid breaking the UI
    return {
      'domainDistribution': <String, int>{},
      'projectTrend': <Map<String, dynamic>>[],
    };
  }
}, dependencies: [authProvider]); // Cache automatically by Riverpod, only refetch when auth changes

// Map normalized domain names to standard domain names
String _mapToStandardDomain(String normalized) {
  // Handle numeric/invalid domains (like timestamps) - skip them
  if (RegExp(r'^\d+$').hasMatch(normalized)) {
    return ''; // Return empty to skip invalid numeric domains
  }
  
  // Map "pd" abbreviation to Physical Design
  if (normalized == 'pd' || normalized == 'physical') {
    return 'physical design';
  }
  
  // Map all variations to the standard domains (order matters - check more specific first)
  
  // Physical Design variations (check first as it's most common)
  if (normalized.contains('physical') && (normalized.contains('design') || normalized.contains('domain'))) {
    return 'physical design';
  }
  
  // Design Verification variations
  if (normalized.contains('design') && normalized.contains('verification')) {
    return 'design verification';
  }
  
  // Register Transfer Level / RTL variations
  if ((normalized.contains('register') && normalized.contains('transfer') && normalized.contains('level')) || 
      normalized.contains('rtl')) {
    return 'register transfer level';
  }
  
  // Design for Testability / DFT variations
  if (normalized.contains('testability') || normalized.contains('dft')) {
    return 'design for testability';
  }
  
  // Analog Layout variations
  if (normalized.contains('analog') && normalized.contains('layout')) {
    return 'analog layout';
  }
  
  // If no match found, return empty to skip invalid domains
  return '';
}

// Normalize domain name to handle typos and variations
String _normalizeDomainName(String name) {
  // Remove extra spaces and convert to lowercase
  String normalized = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  
  // Fix common typos
  normalized = normalized
      .replaceAll('phyiscal', 'physical')      // Fix: phyiscal -> physical
      .replaceAll('deisgn', 'design')          // Fix: deisgn -> design
      .replaceAll('desing', 'design')          // Fix: desing -> design
      .replaceAll('desgin', 'design')          // Fix: desgin -> design
      .replaceAll('verifcation', 'verification')  // Fix: verifcation -> verification
      .replaceAll('verificaton', 'verification')  // Fix: verificaton -> verification
      .replaceAll('verificaiton', 'verification'); // Fix: verificaiton -> verification
  
  // Handle "physical domain" -> "physical design" (common typo)
  if (normalized.contains('physical') && normalized.contains('domain')) {
    normalized = normalized.replaceAll('domain', 'design');
  }
  
  // Handle "design _verification" -> "design verification" (extra space/underscore)
  normalized = normalized.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ');
  
  // Map to standard domain names
  normalized = _mapToStandardDomain(normalized.trim());
  
  return normalized.trim();
}

Map<String, dynamic> _calculateChartData(List<dynamic> projects, List<dynamic> domains, [Map<String, int>? edaDomainCounts]) {
  // 1. Domain Distribution
  // Create a map of normalized domain names to their canonical (display) names
  final domainNameMap = <String, String>{}; // normalized -> canonical
  final domainNames = {for (var d in domains) d['id']: d['name']};
  
  // Build normalized name mapping from domains table
  for (var d in domains) {
    final canonicalName = d['name'] as String?;
    if (canonicalName != null && canonicalName.isNotEmpty) {
      final normalized = _normalizeDomainName(canonicalName);
      // Use the first occurrence as canonical name (prefer proper case from database)
      if (!domainNameMap.containsKey(normalized)) {
        domainNameMap[normalized] = canonicalName.trim();
      }
    }
  }
  
  final domainCounts = <String, int>{}; // Use normalized keys for counting
  
  // First, try to get domains from projects
  for (var p in projects) {
    // Handle both List<int> and List<dynamic> for domain_ids
    final pDomains = p['domain_ids'];
    if (pDomains is List && pDomains.isNotEmpty) {
       for (var id in pDomains) {
         final name = domainNames[id] ?? 'Unknown';
         if (name != 'Unknown' && name.isNotEmpty) {
           final normalized = _normalizeDomainName(name);
           final canonical = domainNameMap[normalized] ?? name.trim();
           domainNameMap[normalized] = canonical; // Ensure canonical name is set
           domainCounts[normalized] = (domainCounts[normalized] ?? 0) + 1;
         }
       }
    } else if (p['domains'] is List && (p['domains'] as List).isNotEmpty) {
      // Handle the case where domains are already populated (from backend)
      for (var d in p['domains']) {
         final name = d['name'] ?? 'Unknown';
         if (name != null && name != 'Unknown' && name.toString().isNotEmpty) {
           final normalized = _normalizeDomainName(name.toString());
           final canonical = domainNameMap[normalized] ?? name.toString().trim();
           domainNameMap[normalized] = canonical; // Ensure canonical name is set
           domainCounts[normalized] = (domainCounts[normalized] ?? 0) + 1;
         }
      }
    }
  }
  
  // Merge EDA file domain counts (normalize them first)
  if (edaDomainCounts != null && edaDomainCounts.isNotEmpty) {
    for (var entry in edaDomainCounts.entries) {
      // Normalize the domain name from EDA files to handle typos
      final normalized = _normalizeDomainName(entry.key);
      // Find canonical name from domains table or use the normalized key
      final canonical = domainNameMap[normalized] ?? normalized;
      domainNameMap[normalized] = canonical;
      domainCounts[normalized] = (domainCounts[normalized] ?? 0) + entry.value;
    }
  }
  
  // Convert back to canonical names for display (remove duplicates)
  final finalDomainCounts = <String, int>{};
  for (var entry in domainCounts.entries) {
    final canonical = domainNameMap[entry.key] ?? entry.key;
    // Use canonical name, but if multiple normalized names map to same canonical, sum them
    finalDomainCounts[canonical] = (finalDomainCounts[canonical] ?? 0) + entry.value;
  }
  
  // Debug: Print domain counts for troubleshooting
  if (finalDomainCounts.isEmpty) {
    print('⚠️ [DOMAIN CHART] No domains found. Projects: ${projects.length}, EDA domains: ${edaDomainCounts?.length ?? 0}');
  } else {
    print('✅ [DOMAIN CHART] Domain distribution (deduplicated): $finalDomainCounts');
  }

  // 2. Project Trend (Last 6 months)
  // Group by month
  final now = DateTime.now();
  final trendData = <Map<String, dynamic>>[];
  
  for (int i = 5; i >= 0; i--) {
    final monthStart = DateTime(now.year, now.month - i, 1);
    
    int count = 0;
    for (var p in projects) {
        // Try start_date, then created_at
        String? dateStr = p['start_date'] ?? p['created_at'];
        if (dateStr != null) {
          try {
            final date = DateTime.parse(dateStr);
            if (date.year == monthStart.year && date.month == monthStart.month) {
              count++;
            }
          } catch (e) {
             // ignore date parse error
          }
        }
    }
    
    trendData.add({
      'month': _getMonthName(monthStart.month),
      'count': count,
      'monthIndex': i, // 0 is 5 months ago, 5 is current month (wait, loop is 5 to 0)
                       // Actually, let's just use index 0-5 for the chart
    });
  }

  return {
    'domainDistribution': finalDomainCounts,
    'projectTrend': trendData,
  };
}

String _getMonthName(int month) {
  const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  if (month >= 1 && month <= 12) {
    return months[month - 1];
  }
  return '';
}
