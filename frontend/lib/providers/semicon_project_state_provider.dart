import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Persisted UI state per project so that when you switch to another project
/// and come back, your block / RTL / experiment / tab and command console history are restored.
class SemiconProjectState {
  final String selectedBlock;
  final String selectedRtlTag;
  final String selectedExperiment;
  final String selectedTab;
  final List<Map<String, dynamic>> chatMessages;

  const SemiconProjectState({
    this.selectedBlock = 'Select a block',
    this.selectedRtlTag = 'Select RTL tag',
    this.selectedExperiment = 'Select an experiment',
    this.selectedTab = 'Dashboard',
    this.chatMessages = const [],
  });

  SemiconProjectState copyWith({
    String? selectedBlock,
    String? selectedRtlTag,
    String? selectedExperiment,
    String? selectedTab,
    List<Map<String, dynamic>>? chatMessages,
  }) {
    return SemiconProjectState(
      selectedBlock: selectedBlock ?? this.selectedBlock,
      selectedRtlTag: selectedRtlTag ?? this.selectedRtlTag,
      selectedExperiment: selectedExperiment ?? this.selectedExperiment,
      selectedTab: selectedTab ?? this.selectedTab,
      chatMessages: chatMessages ?? this.chatMessages,
    );
  }
}

/// Notifier that holds per-project Semicon UI state (block, RTL, experiment, tab).
class SemiconProjectStateNotifier extends StateNotifier<Map<String, SemiconProjectState>> {
  SemiconProjectStateNotifier() : super({});

  /// Same id as tab_provider uses for the project (so we key state by tab).
  static String projectStateId(Map<String, dynamic> project) {
    return project['id']?.toString() ??
        project['name']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();
  }

  void saveState(String projectId, SemiconProjectState projectState) {
    state = {...state, projectId: projectState};
  }

  SemiconProjectState? getState(String projectId) => state[projectId];

  /// Clear persisted state for a project so next open does a fresh load from DB (no previous filter).
  void clearState(String projectId) {
    final next = Map<String, SemiconProjectState>.from(state)..remove(projectId);
    state = next;
  }

  /// Clear all persisted state (e.g. when closing all tabs / logout).
  void clearAll() {
    state = {};
  }
}

final semiconProjectStateProvider =
    StateNotifierProvider<SemiconProjectStateNotifier, Map<String, SemiconProjectState>>((ref) {
  return SemiconProjectStateNotifier();
});

/// Cached blocks/experiments data per project so switching tabs does not refetch from API.
class SemiconBlocksCache {
  final List<String> availableBlocks;
  final Map<String, List<String>> blockToExperiments;
  final Map<String, Map<String, String>> blockExperimentToRtlTag;
  final Map<String, Map<String, List<String>>> blockRtlTagToExperiments;

  const SemiconBlocksCache({
    this.availableBlocks = const [],
    this.blockToExperiments = const {},
    this.blockExperimentToRtlTag = const {},
    this.blockRtlTagToExperiments = const {},
  });
}

class SemiconBlocksCacheNotifier extends StateNotifier<Map<String, SemiconBlocksCache>> {
  SemiconBlocksCacheNotifier() : super({});

  void saveCache(String projectId, SemiconBlocksCache cache) {
    state = {...state, projectId: cache};
  }

  SemiconBlocksCache? getCache(String projectId) => state[projectId];

  /// Clear blocks cache for a project so next open fetches fresh from DB.
  void clearCache(String projectId) {
    final next = Map<String, SemiconBlocksCache>.from(state)..remove(projectId);
    state = next;
  }

  /// Clear all blocks cache (e.g. when closing all tabs / logout).
  void clearAll() {
    state = {};
  }
}

final semiconBlocksCacheProvider =
    StateNotifierProvider<SemiconBlocksCacheNotifier, Map<String, SemiconBlocksCache>>((ref) {
  return SemiconBlocksCacheNotifier();
});
