import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProjectTab {
  final String id;
  final String name;
  final Map<String, dynamic> project;

  ProjectTab({
    required this.id,
    required this.name,
    required this.project,
  });
}

class TabState {
  final List<ProjectTab> tabs;
  final String? activeTabId;

  TabState({
    required this.tabs,
    this.activeTabId,
  });

  TabState copyWith({
    List<ProjectTab>? tabs,
    String? activeTabId,
  }) {
    return TabState(
      tabs: tabs ?? this.tabs,
      activeTabId: activeTabId ?? this.activeTabId,
    );
  }
}

class TabNotifier extends StateNotifier<TabState> {
  TabNotifier() : super(TabState(tabs: []));

  void openProject(Map<String, dynamic> project) {
    final projectName = project['name'] ?? 'Unnamed Project';
    final projectKey = project['id']?.toString() ?? project['name']?.toString() ?? '';
    // Unique tab id per tab instance so the same project can be opened in multiple tabs
    final tabId = '${projectKey}_${DateTime.now().millisecondsSinceEpoch}';

    final newTab = ProjectTab(
      id: tabId,
      name: projectName,
      project: project,
    );
    state = state.copyWith(
      tabs: [...state.tabs, newTab],
      activeTabId: tabId,
    );
  }

  void closeTab(String tabId) {
    final newTabs = state.tabs.where((tab) => tab.id != tabId).toList();
    String? newActiveTabId;
    
    if (state.activeTabId == tabId) {
      // If closing active tab, switch to another tab
      if (newTabs.isNotEmpty) {
        newActiveTabId = newTabs.last.id;
      } else {
        newActiveTabId = null;
      }
    } else {
      newActiveTabId = state.activeTabId;
    }

    state = state.copyWith(
      tabs: newTabs,
      activeTabId: newActiveTabId,
    );
  }

  void switchTab(String tabId) {
    state = state.copyWith(activeTabId: tabId);
  }

  void closeAllTabs() {
    state = TabState(tabs: []);
  }
}

final tabProvider = StateNotifierProvider<TabNotifier, TabState>((ref) {
  return TabNotifier();
});

