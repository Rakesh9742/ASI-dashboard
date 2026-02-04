import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/semicon_project_state_provider.dart';
import '../providers/tab_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/auth_wrapper.dart';
import 'projects_screen.dart';
import 'user_management_screen.dart';
import 'semicon_dashboard_screen.dart';
import 'view_screen.dart';

// Provider to track current navigation tab
final currentNavTabProvider = StateProvider<String>((ref) => 'Projects');

// Semicon OS brand colors (indigo) – logo, app name "OS", main nav chips
const Color _kBrandPrimary = Color(0xFF6366F1);
const Color _kBrandSecondary = Color(0xFF4F46E5);
// Project tab chip accent (amber) – distinct from main nav
const Color _kProjectChipAccent = Color(0xFFF59E0B);
const Color _kProjectChipAccentDark = Color(0xFFD97706);

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

    // Determine which screen to show based on current navigation
    // Chrome-like: keep all project tab screens mounted and switch visibility (IndexedStack)
    Widget currentScreen;
    if (tabState.tabs.isNotEmpty && currentNav == 'project_tab') {
      final activeIndex = tabState.activeTabId != null
          ? tabState.tabs.indexWhere((t) => t.id == tabState.activeTabId)
          : -1;
      final index = activeIndex >= 0 ? activeIndex : 0;
      final tabScreens = tabState.tabs.map((tab) {
        if (isCustomer) {
          final projectName = tab.project['name']?.toString();
          if (projectName != null) {
            return ViewScreen(
              key: ValueKey('view-${tab.id}'),
              initialProject: projectName,
              initialViewType: 'customer',
            );
          }
          return SemiconDashboardScreen(
            key: ValueKey('project-${tab.id}'),
            project: tab.project,
          );
        }
        return SemiconDashboardScreen(
          key: ValueKey('project-${tab.id}'),
          project: tab.project,
        );
      }).toList();
      currentScreen = IndexedStack(
        index: index,
        children: tabScreens,
      );
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
            // Unified Navigation Header (top)
            _buildNavigationHeader(user, isAdmin, isEngineer, isCustomer),
            // Project tabs (top-left)
            _buildProjectTabsBar(),
            // Current Screen Content — AnimatedSwitcher only when switching nav (Projects/Users/tabs)
            Expanded(
              child: Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: currentScreen,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationHeader(dynamic user, bool isAdmin, bool isEngineer, bool isCustomer) {
    final currentNav = ref.watch(currentNavTabProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Theme.of(context).scaffoldBackgroundColor,
                  Theme.of(context).scaffoldBackgroundColor.withOpacity(0.98),
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
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top accent strip – Semicon OS brand
          Container(
            height: 3,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [_kBrandPrimary, _kBrandSecondary],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Row(
              children: [
                // Logo – new icon and Semicon OS colors
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_kBrandPrimary, _kBrandSecondary],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: _kBrandPrimary.withOpacity(0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.developer_board,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                              letterSpacing: 0.3,
                            ),
                            children: [
                              TextSpan(
                                text: 'Semicon',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              TextSpan(
                                text: ' OS',
                                style: TextStyle(
                                  color: _kBrandPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
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
                // Navigation Tabs – new pill design
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
                  Tooltip(message: 'Go to Projects. View and manage your chip design projects.', child: _buildNavTab('Projects', isSelected: currentNav == 'Projects')),
                  if (isAdmin) ...[
                    const SizedBox(width: 6),
                    Tooltip(message: 'Go to User management. Add users and assign them to projects (admin only).', child: _buildNavTab('Users', isSelected: currentNav == 'Users')),
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
                  Tooltip(message: 'Go to Projects. View and manage your chip design projects.', child: _buildNavTab('Projects', isSelected: currentNav == 'Projects')),
                ],
              ),
            ),
          const SizedBox(width: 20),
          // Action Icons - Enhanced
          Row(
            children: [
              // Theme Toggle Button
              Tooltip(
                message: 'Switch between light and dark mode.',
                child: Container(
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
              ),
              const SizedBox(width: 12),
              // User menu – professional dropdown
              Tooltip(
                message: 'Open account menu. View your profile or sign out.',
                child: _buildUserMenuButton(user, isDark),
              ),
            ],
          ),
        ],
      ),
    ),
    ],
  ),
);
  }

  void _showUserMenu(BuildContext context, dynamic user, bool isDark) {
    final email = user?['email']?.toString() ?? user?['username']?.toString() ?? 'Signed in';
    final name = user?['name']?.toString();
    final role = user?['role']?.toString();

    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
        context.size!.width - 280,
        80,
        24,
        0,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: Colors.transparent,
      elevation: 0,
      items: [
        PopupMenuItem(
          enabled: false,
          padding: EdgeInsets.zero,
          child: Container(
            width: 272,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade900 : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.4 : 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [_kBrandPrimary, _kBrandSecondary],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name ?? email,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (name != null && name != email) ...[
                              const SizedBox(height: 2),
                              Text(
                                email,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.65),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ] else if (role != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                role.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _kBrandPrimary,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  color: Theme.of(context).dividerColor.withOpacity(0.5),
                ),
                InkWell(
                  onTap: () async {
                    Navigator.of(context).pop();
                    await ref.read(authProvider.notifier).logout();
                    // Reset project tabs and nav so next login shows Projects list, not a previously opened project
                    ref.read(semiconProjectStateProvider.notifier).clearAll();
                    ref.read(semiconBlocksCacheProvider.notifier).clearAll();
                    ref.read(tabProvider.notifier).closeAllTabs();
                    ref.read(currentNavTabProvider.notifier).state = 'Projects';
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const AuthWrapper()),
                        (route) => false,
                      );
                    }
                  },
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50.withOpacity(isDark ? 0.5 : 1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.logout_rounded,
                            size: 20,
                            color: Colors.red.shade600,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Sign out',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Exit your account',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 12,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUserMenuButton(dynamic user, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.white,
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
          onTap: () => _showUserMenu(context, user, isDark),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              Icons.person_outline_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProjectTabsBar() {
    final tabState = ref.watch(tabProvider);
    final currentNav = ref.watch(currentNavTabProvider);
    final hasTabs = tabState.tabs.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.8), width: 1),
          left: hasTabs
              ? BorderSide(color: _kProjectChipAccent.withOpacity(0.4), width: 3)
              : BorderSide.none,
        ),
      ),
      child: tabState.tabs.isEmpty
          ? const SizedBox.shrink()
          : Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...tabState.tabs.map((tab) {
                        final isSelected = currentNav == 'project_tab' && tab.id == tabState.activeTabId;
                        return Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: _buildProjectTabPill(tab, isSelected),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildProjectTabPill(ProjectTab tab, bool isSelected) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ref.read(tabProvider.notifier).switchTab(tab.id);
          ref.read(currentNavTabProvider.notifier).state = 'project_tab';
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? _kProjectChipAccent.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? _kProjectChipAccent : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_rounded,
                size: 16,
                color: isSelected ? _kProjectChipAccent : onSurface.withOpacity(0.6),
              ),
              const SizedBox(width: 8),
              Text(
                tab.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? _kProjectChipAccentDark : onSurface.withOpacity(0.75),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  ref.read(semiconProjectStateProvider.notifier).clearState(tab.id);
                  ref.read(semiconBlocksCacheProvider.notifier).clearCache(tab.id);
                  ref.read(tabProvider.notifier).closeTab(tab.id);
                  if (isSelected) {
                    ref.read(currentNavTabProvider.notifier).state = 'Projects';
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: onSurface.withOpacity(0.65),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavTab(String label, {required bool isSelected}) {
    IconData icon;
    if (label == 'Projects') {
      icon = Icons.folder_rounded;
    } else {
      icon = Icons.people_rounded;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ref.read(currentNavTabProvider.notifier).state = label;
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _kBrandPrimary,
                      _kBrandSecondary,
                    ],
                  )
                : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: _kBrandPrimary.withOpacity(0.35),
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
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
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

}
