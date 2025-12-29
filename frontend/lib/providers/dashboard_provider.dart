import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

final dashboardProvider = StateNotifierProvider<DashboardNotifier, AsyncValue<Map<String, dynamic>>>(
  (ref) {
    final apiService = ref.read(apiServiceProvider);
    final authState = ref.watch(authProvider);
    return DashboardNotifier(apiService, token: authState.token);
  },
);

class DashboardNotifier extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  final ApiService _apiService;
  final String? _token;

  DashboardNotifier(this._apiService, {String? token}) 
      : _token = token,
        super(const AsyncValue.loading()) {
    loadStats();
  }

  Future<void> loadStats() async {
    state = const AsyncValue.loading();
    try {
      // Fetch data from real endpoints in parallel
      final results = await Future.wait([
        _apiService.getProjects(token: _token),
        _apiService.getDomains(token: _token),
        _apiService.getDesigns(),
        _apiService.getChips(),
        // Attempt to fetch users, separate try/catch inside might be cleaner but Future.wait fails if one fails.
        // Let's assume getProjects/Domains work. For users, we might need a separate call or handle failure.
        // Actually, if getUsers fails (403), Future.wait will throw.
        // So we should wrap it or allow it to fail gracefully?
        // Let's do a safe fetch for users.
      ]);
      
      final projects = results[0] as List<dynamic>;
      final domains = results[1] as List<dynamic>;
      final designs = results[2] as List<dynamic>;
      final chips = results[3] as List<dynamic>;

      // Fetch users (accessible to engineers now)
      List<dynamic> users = [];
      List<dynamic> engineers = [];
      int totalEngineers = 0;
      try {
        users = await _apiService.getUsers(token: _token);
        // Filter to only engineers
        engineers = users.where((user) => 
          user['role']?.toString().toLowerCase() == 'engineer'
        ).toList();
        totalEngineers = engineers.length;
      } catch (e) {
        print('Could not fetch users: $e');
      }

      // Calculate Project Stats
      final totalProjects = projects.length;
      
      // Calculate Domain Stats
      final totalDomains = domains.length;

      // Construct the stats object expected by the UI
      final stats = {
        'projects': {
          'total': totalProjects,
          'active': totalProjects, // Placeholder
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
    final projects = await apiService.getProjects(token: token);
    final domains = await apiService.getDomains(token: token);
    return _calculateChartData(projects, domains);
  } catch (e) {
    print('Error loading chart data: $e');
    // Return empty data on error to avoid breaking the UI
    return {
      'domainDistribution': <String, int>{},
      'projectTrend': <Map<String, dynamic>>[],
    };
  }
});

Map<String, dynamic> _calculateChartData(List<dynamic> projects, List<dynamic> domains) {
  // 1. Domain Distribution
  final domainNames = {for (var d in domains) d['id']: d['name']};
  final domainCounts = <String, int>{};
  
  for (var p in projects) {
    // Handle both List<int> and List<dynamic> for domain_ids
    final pDomains = p['domain_ids'];
    if (pDomains is List) {
       for (var id in pDomains) {
         final name = domainNames[id] ?? 'Unknown';
         domainCounts[name] = (domainCounts[name] ?? 0) + 1;
       }
    } else if (p['domains'] is List) {
      // Handle the case where domains are already populated (from backend)
      for (var d in p['domains']) {
         final name = d['name'] ?? 'Unknown';
         domainCounts[name] = (domainCounts[name] ?? 0) + 1;
      }
    }
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
    'domainDistribution': domainCounts,
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
