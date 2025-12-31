import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import 'dashboard_screen.dart';
import 'user_management_screen.dart';
import 'project_management_screen.dart';
import 'engineer_projects_screen.dart';
import 'view_screen.dart';
import 'login_screen.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _selectedIndex = 0;
  bool _isSidebarOpen = true;

  List<Widget> _getScreens(String? role) {
    if (role == 'engineer') {
      return [
        const DashboardScreen(),
        const EngineerProjectsScreen(),
        const ViewScreen(),
      ];
    }
    return [
      const DashboardScreen(),
      const ProjectManagementScreen(),
      const ViewScreen(),
      const UserManagementScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final userRole = user?['role'];
    final isAdmin = userRole == 'admin';
    final isEngineer = userRole == 'engineer';
    final screens = _getScreens(userRole);

    return Scaffold(
      body: Row(
        children: [
          // Professional Sidebar Navigation
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            width: _isSidebarOpen ? 280 : 0,
            child: _isSidebarOpen
                ? Container(
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.grey.shade900,
                          Colors.grey.shade800,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(2, 0),
                        ),
                      ],
                    ),
                    child: Column(
              children: [
                // Logo/Brand Section
                Container(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.purple.shade400,
                              Colors.purple.shade600,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.purple.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.dashboard,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'ASI Dashboard',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            Text(
                              'Control Panel',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w300,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(
                  color: Colors.white12,
                  height: 1,
                  thickness: 1,
                ),
                // Navigation Items
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        _buildNavItem(
                          context: context,
                          icon: Icons.dashboard_outlined,
                          selectedIcon: Icons.dashboard,
                          label: 'Dashboard',
                          index: 0,
                          isSelected: _selectedIndex == 0,
                          isAdmin: isAdmin,
                          isEngineer: isEngineer,
                        ),
                        const SizedBox(height: 8),
                        _buildNavItem(
                          context: context,
                          icon: Icons.folder_outlined,
                          selectedIcon: Icons.folder,
                          label: isEngineer ? 'My Projects' : 'Projects',
                          index: 1,
                          isSelected: _selectedIndex == 1,
                          isAdmin: isAdmin,
                          isEngineer: isEngineer,
                        ),
                        const SizedBox(height: 8),
                        _buildNavItem(
                          context: context,
                          icon: Icons.visibility_outlined,
                          selectedIcon: Icons.visibility,
                          label: 'View',
                          index: isEngineer ? 2 : 2,
                          isSelected: _selectedIndex == (isEngineer ? 2 : 2),
                          isAdmin: isAdmin,
                          isEngineer: isEngineer,
                        ),
                        if (isAdmin) ...[
                          const SizedBox(height: 8),
                          _buildNavItem(
                            context: context,
                            icon: Icons.people_outline,
                            selectedIcon: Icons.people,
                            label: 'Users',
                            index: 3,
                            isSelected: _selectedIndex == 3,
                            isAdmin: isAdmin,
                            isEngineer: isEngineer,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // User Profile Section at Bottom
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.purple.shade600,
                        child: Text(
                          user?['username']?.substring(0, 1).toUpperCase() ?? 'U',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              user?['full_name'] ?? user?['username'] ?? 'User',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            Text(
                              user?['role']?.toUpperCase() ?? 'USER',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            if (user?['domain_name'] != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Active Domain: ${user?['domain_name']}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w400,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
                  )
                : const SizedBox.shrink(),
          ),
          // Main Content
          Expanded(
            child: screens[_selectedIndex],
          ),
        ],
      ),
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            _isSidebarOpen ? Icons.menu_open : Icons.menu,
            color: Colors.grey.shade900,
          ),
          onPressed: () {
            setState(() {
              _isSidebarOpen = !_isSidebarOpen;
            });
          },
          tooltip: _isSidebarOpen ? 'Close sidebar' : 'Open sidebar',
        ),
        title: Text(
          _getAppBarTitle(_selectedIndex),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.grey.shade900,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh, color: Colors.grey.shade700),
              onPressed: () {
                // Refresh current screen by refreshing the current screen's data
                // This will be handled by individual screens if needed
              },
              tooltip: 'Refresh',
            ),
          ),
          PopupMenuButton<dynamic>(
            icon: Container(
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.purple.shade400,
                    Colors.purple.shade600,
                  ],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.purple.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: Colors.transparent,
                child: Text(
                  user?['username']?.substring(0, 1).toUpperCase() ?? 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 8,
            itemBuilder: (BuildContext context) => <PopupMenuEntry<dynamic>>[
              PopupMenuItem(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.person,
                        size: 20,
                        color: Colors.purple.shade600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            user?['full_name'] ?? user?['username'] ?? 'User',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user?['role']?.toUpperCase() ?? 'USER',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          if (user?['domain_name'] != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Active Domain: ${user?['domain_name']}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w400,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                child: Row(
                  children: [
                    Icon(Icons.settings, size: 20, color: Colors.grey.shade700),
                    const SizedBox(width: 12),
                    Text(
                      'Settings',
                      style: TextStyle(color: Colors.grey.shade800),
                    ),
                  ],
                ),
                onTap: () {
                  // TODO: Navigate to settings
                },
              ),
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
                  if (context.mounted) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required int index,
    required bool isSelected,
    required bool isAdmin,
    required bool isEngineer,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // Only allow admin to access user management (index 3)
            if (index == 3 && !isAdmin) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Access denied. Admin role required.'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
            // Engineers can only access index 0 (Dashboard), 1 (Projects), and 2 (View)
            if (isEngineer && index > 2) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Access denied. This section is not available for engineers.'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
            setState(() {
              _selectedIndex = index;
              _isSidebarOpen = false; // Close sidebar when item is selected
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.purple.shade600.withOpacity(0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(
                      color: Colors.purple.shade400.withOpacity(0.3),
                      width: 1,
                    )
                  : null,
            ),
            child: Row(
              children: [
                // Active Indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.purple.shade400,
                              Colors.purple.shade600,
                            ],
                          )
                        : null,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 16),
                // Icon - simplified without AnimatedSwitcher
                Icon(
                  isSelected ? selectedIcon : icon,
                  color: isSelected
                      ? Colors.purple.shade300
                      : Colors.white.withOpacity(0.7),
                  size: 24,
                ),
                const SizedBox(width: 16),
                // Label
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : Colors.white.withOpacity(0.8),
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                // Selection Indicator
                if (isSelected)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.purple.shade400,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.purple.withOpacity(0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
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

  String _getAppBarTitle(int index) {
    final userRole = ref.read(authProvider).user?['role'];
    final isEngineer = userRole == 'engineer';
    
    if (isEngineer) {
      switch (index) {
        case 0:
          return 'Dashboard';
        case 1:
          return 'My Projects';
        case 2:
          return 'View';
        default:
          return 'ASI Dashboard';
      }
    }
    
    switch (index) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'Project Management';
      case 2:
        return 'View';
      case 3:
        return 'User Management';
      default:
        return 'ASI Dashboard';
    }
  }
}

