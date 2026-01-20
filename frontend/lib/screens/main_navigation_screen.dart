import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/tab_provider.dart';
import '../providers/theme_provider.dart';
import 'projects_screen.dart';
import 'project_management_screen.dart';
import 'user_management_screen.dart';
import 'semicon_dashboard_screen.dart';
import 'view_screen.dart';

// Provider to track current navigation tab
final currentNavTabProvider = StateProvider<String>((ref) => 'Projects');

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final userRole = user?['role'];
    final isAdmin = userRole == 'admin';
    final isEngineer = userRole == 'engineer';
    final isCustomer = userRole == 'customer';
    final currentNav = ref.watch(currentNavTabProvider);
    final tabState = ref.watch(tabProvider);
    final activeTab = tabState.tabs.firstWhere(
      (tab) => tab.id == tabState.activeTabId,
      orElse: () => ProjectTab(id: '', name: '', project: {}),
    );

    // Determine which screen to show based on current navigation
    Widget currentScreen;
    if (tabState.activeTabId != null && activeTab.id.isNotEmpty && currentNav == 'project_tab') {
      // For customers, show ViewScreen with customer view instead of SemiconDashboardScreen
      if (isCustomer) {
        final projectName = activeTab.project['name']?.toString();
        if (projectName != null) {
          // Import ViewScreen at top if not already imported
          currentScreen = ViewScreen(
            initialProject: projectName,
            initialViewType: 'customer',
          );
        } else {
          currentScreen = SemiconDashboardScreen(project: activeTab.project);
        }
      } else {
        // Show active project tab (SemiconDashboardScreen) for non-customers
        currentScreen = SemiconDashboardScreen(project: activeTab.project);
      }
    } else if (currentNav == 'Project Management' && !isCustomer) {
      currentScreen = const ProjectManagementScreen();
    } else if (currentNav == 'Users' && isAdmin) {
      currentScreen = const UserManagementScreen();
    } else {
      // Default: Show Projects - Use new UI for all roles including engineers
      currentScreen = const ProjectsScreen();
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
        children: [
            // Unified Navigation Header
            _buildNavigationHeader(isAdmin, isEngineer, isCustomer),
            // Project Tabs Bar (below navigation)
            _buildProjectTabsBar(),
            // Current Screen Content
            Expanded(
              child: Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: currentScreen,
              ),
                        ),
                      ],
                    ),
      ),
    );
  }

  Widget _buildNavigationHeader(bool isAdmin, bool isEngineer, bool isCustomer) {
    final currentNav = ref.watch(currentNavTabProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
                  child: Row(
        children: [
          // Logo
          Row(
                    children: [
                      Container(
                width: 32,
                height: 32,
                        decoration: BoxDecoration(
                  color: const Color(0xFF14B8A6),
                  borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                  Icons.memory,
                          color: Colors.white,
                  size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                            RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                children: [
                    TextSpan(
                      text: 'Semicon',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                    ),
                                  TextSpan(
                                    text: 'OS',
                                    style: TextStyle(color: const Color(0xFF14B8A6)),
                                  ),
                                ],
                              ),
                            ),
              const SizedBox(width: 8),
                            Text(
                              'AI-Driven RTL-to-GDS Orchestration',
                              style: TextStyle(
                                fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          const Spacer(),
          // Navigation Tabs (Main only) - Hide Project Management for customers
          if (!isCustomer)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _buildNavTab('Projects', isSelected: currentNav == 'Projects'),
                  const SizedBox(width: 4),
                  _buildNavTab('Project Management', isSelected: currentNav == 'Project Management'),
                  if (isAdmin) ...[
                    const SizedBox(width: 4),
                    _buildNavTab('Users', isSelected: currentNav == 'Users'),
                  ],
                ],
              ),
            )
          else
            // For customers, only show Projects tab
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _buildNavTab('Projects', isSelected: currentNav == 'Projects'),
                ],
              ),
            ),
          const SizedBox(width: 16),
          // Status and User Icons
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                    const SizedBox(width: 6),
                          Text(
                      'IDLE',
                            style: TextStyle(
                        fontSize: 12,
                              fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  ref.watch(themeModeProvider) == ThemeMode.dark
                      ? Icons.light_mode
                      : Icons.dark_mode_outlined,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
                onPressed: () {
                  ref.read(themeModeProvider.notifier).toggleTheme();
                },
                tooltip: ref.watch(themeModeProvider) == ThemeMode.dark
                    ? 'Switch to light mode'
                    : 'Switch to dark mode',
              ),
              PopupMenuButton<dynamic>(
                icon: Icon(Icons.person_outline, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                itemBuilder: (BuildContext context) => <PopupMenuEntry<dynamic>>[
              PopupMenuItem(
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20, color: Colors.red.shade600),
                    const SizedBox(width: 12),
                    Text(
                      'Logout',
                      style: TextStyle(
                        color: Colors.red.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                onTap: () async {
                  await ref.read(authProvider.notifier).logout();
                },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProjectTabsBar() {
    final tabState = ref.watch(tabProvider);
    final currentNav = ref.watch(currentNavTabProvider);

    if (tabState.tabs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ...tabState.tabs.map((tab) {
              final isSelected = currentNav == 'project_tab' && tab.id == tabState.activeTabId;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _buildProjectTab(tab, isSelected),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildNavTab(String label, {required bool isSelected}) {
    IconData icon;
    if (label == 'Projects') {
      icon = Icons.folder_outlined;
    } else if (label == 'Project Management') {
      icon = Icons.settings_outlined;
    } else {
      icon = Icons.people_outline;
    }

    return InkWell(
      onTap: () {
        ref.read(currentNavTabProvider.notifier).state = label;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF14B8A6).withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
              border: isSelected
              ? Border(
                  bottom: BorderSide(color: const Color(0xFF14B8A6), width: 2),
                    )
                  : null,
            ),
            child: Row(
              children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectTab(ProjectTab tab, bool isSelected) {
    return InkWell(
      onTap: () {
        ref.read(tabProvider.notifier).switchTab(tab.id);
        ref.read(currentNavTabProvider.notifier).state = 'project_tab';
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.surface : Colors.transparent,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(8),
            topRight: Radius.circular(8),
          ),
          border: isSelected
              ? Border.all(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                )
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, -1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder,
              size: 14,
              color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
            const SizedBox(width: 6),
            Text(
              tab.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                ref.read(tabProvider.notifier).closeTab(tab.id);
                // If closing the active tab, switch back to Projects
                if (isSelected) {
                  ref.read(currentNavTabProvider.notifier).state = 'Projects';
                }
              },
              child: Container(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close,
                  size: 12,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ),
              ],
        ),
      ),
    );
  }
}
