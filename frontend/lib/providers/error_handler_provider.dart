import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/error_dialog.dart';

/// Global error and info dialog for the whole app. Use the same modal for errors and info messages.
///
/// From any page (with access to WidgetRef):
///   ref.read(errorHandlerProvider.notifier).showError(e);                    // error
///   ref.read(errorHandlerProvider.notifier).showError(e, title: 'Custom');   // error with title
///   ref.read(errorHandlerProvider.notifier).show('Title', 'Message');        // error (message mapped)
///   ref.read(errorHandlerProvider.notifier).showInfo('Info', 'Message');     // info (same modal, blue)
///   ref.read(errorHandlerProvider.notifier).showInfo('Please select a block'); // title defaults to 'Info'
///
/// [ErrorHandlerScope] must wrap the app once (see main.dart).

/// Holds a pending message to show in the global dialog (error or info).
class ErrorState {
  final String title;
  final String message;
  final bool isInfo;

  const ErrorState({required this.title, required this.message, this.isInfo = false});
}

class ErrorHandlerNotifier extends StateNotifier<ErrorState?> {
  ErrorHandlerNotifier() : super(null);

  /// Show the global dialog with an error (red styling).
  void showError(Object error, {String? title}) {
    state = ErrorState(
      title: title ?? 'Error',
      message: ErrorDialog.messageFromError(error),
      isInfo: false,
    );
  }

  /// Show the global dialog with explicit title and message (error styling, message run through mapping).
  void show(String title, String message) {
    state = ErrorState(
      title: title,
      message: ErrorDialog.messageFromError(message),
      isInfo: false,
    );
  }

  /// Show the global dialog with an info message (blue/teal styling). Use for "Please select a block" etc.
  /// Message is shown as-is (no error mapping).
  void showInfo(String message, {String title = 'Info'}) {
    state = ErrorState(
      title: title,
      message: message,
      isInfo: true,
    );
  }

  void clear() {
    state = null;
  }
}

final errorHandlerProvider = StateNotifierProvider<ErrorHandlerNotifier, ErrorState?>((ref) {
  return ErrorHandlerNotifier();
});

/// Wraps the app so that when [errorHandlerProvider] has a pending error,
/// the global error dialog is shown. Include this once at the root (e.g. around [AuthWrapper]).
/// Pass [navigatorKey] from MaterialApp so the dialog can show from any screen (e.g. login).
class ErrorHandlerScope extends ConsumerStatefulWidget {
  final GlobalKey<NavigatorState>? navigatorKey;
  final Widget child;

  const ErrorHandlerScope({super.key, this.navigatorKey, required this.child});

  @override
  ConsumerState<ErrorHandlerScope> createState() => _ErrorHandlerScopeState();
}

class _ErrorHandlerScopeState extends ConsumerState<ErrorHandlerScope> {
  @override
  Widget build(BuildContext context) {
    final errorState = ref.watch(errorHandlerProvider);

    if (errorState != null) {
      final title = errorState.title;
      final message = errorState.message;
      final isInfo = errorState.isInfo;
      final navKey = widget.navigatorKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(errorHandlerProvider.notifier).clear();
        final dialogContext = navKey?.currentContext ?? context;
        if (dialogContext.mounted) {
          showDialog<void>(
            context: dialogContext,
            barrierDismissible: false,
            builder: (ctx) => ErrorDialog(title: title, message: message, isInfo: isInfo),
          );
        }
      });
    }

    return widget.child;
  }
}
