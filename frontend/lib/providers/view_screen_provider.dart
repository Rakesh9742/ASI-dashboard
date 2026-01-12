import 'package:flutter_riverpod/flutter_riverpod.dart';

class ViewScreenParams {
  final String? project;
  final String? domain;
  final String? viewType;

  ViewScreenParams({
    this.project,
    this.domain,
    this.viewType,
  });
}

final viewScreenParamsProvider = StateProvider<ViewScreenParams?>((ref) => null);

// Provider to control navigation tab selection in MainNavigationScreen
final navigationIndexProvider = StateProvider<int>((ref) => 0);

