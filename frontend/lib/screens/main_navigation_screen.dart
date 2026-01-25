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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Theme.of(context).scaffoldBackgroundColor,
                  Theme.of(context).scaffoldBackgroundColor.withOpacity(0.95),
                ]
              : [
                  Colors.white,
                  Colors.grey.shade50,
                ],
        ),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.5),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo Section - Enhanced
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF14B8A6),
                      Color(0xFF0D9488),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF14B8A6).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.memory,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                      children: [
                        TextSpan(
                          text: 'Semicon',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        TextSpan(
                          text: 'OS',
                          style: TextStyle(
                            color: const Color(0xFF14B8A6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'AI-Driven RTL-to-GDS Orchestration',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          // Navigation Tabs - Enhanced Design
          if (!isCustomer)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.grey.shade900
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withOpacity(0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildNavTab('Projects', isSelected: currentNav == 'Projects'),
                  const SizedBox(width: 6),
                  _buildNavTab('Project Management', isSelected: currentNav == 'Project Management'),
                  if (isAdmin) ...[
                    const SizedBox(width: 6),
                    _buildNavTab('Users', isSelected: currentNav == 'Users'),
                  ],
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.grey.shade900
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withOpacity(0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildNavTab('Projects', isSelected: currentNav == 'Projects'),
                ],
              ),
            ),
          const SizedBox(width: 20),
          // Action Icons - Enhanced
          Row(
            children: [
              // Theme Toggle Button
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.grey.shade800
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withOpacity(0.3),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      ref.read(themeModeProvider.notifier).toggleTheme();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        ref.watch(themeModeProvider) == ThemeMode.dark
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // User Menu Button
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.grey.shade800
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withOpacity(0.3),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: PopupMenuButton<dynamic>(
                  icon: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      Icons.person_outline_rounded,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                    ),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  offset: const Offset(0, 10),
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<dynamic>>[
                    PopupMenuItem(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.logout_rounded,
                              size: 18,
                              color: Colors.red.shade600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Logout',
                            style: TextStyle(
                              color: Colors.red.shade600,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      onTap: () async {
                        await Future.delayed(const Duration(milliseconds: 100));
                        await ref.read(authProvider.notifier).logout();
                      },
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ref.read(currentNavTabProvider.notifier).state = label;
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF14B8A6).withOpacity(0.15),
                      const Color(0xFF0D9488).withOpacity(0.1),
                    ],
                  )
                : null,
            color: isSelected
                ? null
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(
                    color: const Color(0xFF14B8A6).withOpacity(0.3),
                    width: 1,
                  )
                : null,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF14B8A6).withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? const Color(0xFF14B8A6)
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? const Color(0xFF14B8A6)
                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
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
