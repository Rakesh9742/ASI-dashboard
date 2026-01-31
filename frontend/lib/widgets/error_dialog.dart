import 'dart:ui';
import 'package:flutter/material.dart';

/// Reusable modal dialog for errors and info messages. Same popup for both.
/// Use via [ErrorHandlerProvider]: showError() for errors (red), showInfo() for info (blue).
class ErrorDialog extends StatefulWidget {
  final String title;
  final String message;
  final bool isInfo;

  const ErrorDialog({
    super.key,
    required this.title,
    required this.message,
    this.isInfo = false,
  });

  /// Builds a user-friendly message from an error object. Used by error handler and login screen.
  static String messageFromError(Object error) {
    final s = error.toString();
    final lower = s.toLowerCase();
    if (lower.contains('failed to fetch') ||
        lower.contains('clientexception') ||
        lower.contains('uri=http') ||
        lower.contains('uri=https')) {
      return 'The server is not responding. Please check that the application server is running and try again.';
    }
    if (lower.contains('err_connection_refused') ||
        lower.contains('connection refused') ||
        lower.contains('connectionrefused') ||
        lower.contains('failed to connect') ||
        lower.contains('unable to connect') ||
        lower.contains('socketexception') ||
        lower.contains('connection closed')) {
      return 'The server is not responding. Please check that the application server is running and try again.';
    }
    if (lower.contains('err_connection_reset') ||
        lower.contains('connection reset') ||
        lower.contains('err_name_not_resolved') ||
        lower.contains('network is unreachable') ||
        lower.contains('err_internet_disconnected') ||
        lower.contains('err_network_changed') ||
        lower.contains('no internet') ||
        lower.contains('network error')) {
      return 'Unable to reach the server. Please check your internet connection and try again.';
    }
    if (lower.contains('err_cert') ||
        lower.contains('err_ssl') ||
        lower.contains('handshakeexception') ||
        lower.contains('certificate') ||
        lower.contains('ssl')) {
      return 'There was a secure connection problem. Please try again or contact your administrator.';
    }
    if (lower.contains('err_proxy') || lower.contains('proxy connection')) {
      return 'Unable to connect through the proxy. Please check your network settings.';
    }
    if (lower.contains('timeout') ||
        lower.contains('timed out') ||
        lower.contains('deadline exceeded') ||
        lower.contains('receiving data')) {
      return 'The request took too long. Please check your connection and try again.';
    }
    if (lower.contains('400') || lower.contains('bad request')) {
      return 'The request was invalid. Please try again or contact support.';
    }
    if (lower.contains('401') || lower.contains('unauthorized')) {
      return 'Your session may have expired. Please sign in again.';
    }
    if (lower.contains('403') || lower.contains('forbidden')) {
      return "You don't have permission to perform this action.";
    }
    if (lower.contains('404') || lower.contains('not found')) {
      return 'The requested item was not found. Please refresh and try again.';
    }
    if (lower.contains('408') || lower.contains('request timeout')) {
      return 'The request took too long. Please try again.';
    }
    if (lower.contains('409') || lower.contains('conflict')) {
      return 'This action conflicts with the current state. Please refresh and try again.';
    }
    if (lower.contains('422') || lower.contains('unprocessable')) {
      return 'The information provided could not be processed. Please check your input and try again.';
    }
    if (lower.contains('429') || lower.contains('too many requests')) {
      return 'Too many requests. Please wait a moment and try again.';
    }
    if (lower.contains('500') || lower.contains('internal server error')) {
      return 'Something went wrong on the server. Please try again later.';
    }
    if (lower.contains('502') || lower.contains('bad gateway')) {
      return 'The server is temporarily unavailable. Please try again in a moment.';
    }
    if (lower.contains('503') || lower.contains('service unavailable')) {
      return 'The service is temporarily unavailable. Please try again later.';
    }
    if (lower.contains('504') || lower.contains('gateway timeout')) {
      return 'The server took too long to respond. Please try again.';
    }
    if (lower.contains('formatexception') ||
        lower.contains('format exception') ||
        lower.contains('unexpected character') ||
        lower.contains('json')) {
      return 'The server returned invalid data. Please refresh and try again.';
    }
    if (lower.contains('is not a subtype of') || lower.contains('type')) {
      return 'Something went wrong while loading data. Please refresh and try again.';
    }
    if (lower.contains('ioexception') || lower.contains('io exception')) {
      return 'A connection error occurred. Please check your network and try again.';
    }
    if (lower.contains('failed to load') ||
        lower.contains('failed to get') ||
        lower.contains('error connecting')) {
      return 'We couldn\'t load the information. Please try again.';
    }
    if (s.startsWith('Exception: ')) {
      final cleaned = s.substring(11).trim();
      if (cleaned.length > 120 ||
          cleaned.contains('dart:') ||
          cleaned.contains('at ') && cleaned.contains('(')) {
        return 'Something went wrong. Please try again. If the problem continues, contact support.';
      }
      return cleaned;
    }
    if (s.length > 150 || s.contains('dart:') || (s.contains('.dart:') && s.contains(')'))) {
      return 'Something went wrong. Please try again. If the problem continues, contact support.';
    }
    return s;
  }

  @override
  State<ErrorDialog> createState() => _ErrorDialogState();
}

class _ErrorDialogState extends State<ErrorDialog> with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late AnimationController _pulseController;
  late Animation<double> _entranceScale;
  late Animation<double> _entranceOpacity;
  late Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _entranceScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic),
    );
    _entranceOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
    );
    _pulseScale = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// True if message is about connection / server / network (show connection animation).
  static bool _isConnectionRelated(String message) {
    final m = message.toLowerCase();
    return m.contains('server is not responding') ||
        m.contains('check that the application server') ||
        m.contains('internet connection') ||
        m.contains('unable to reach') ||
        m.contains('connection and try again') ||
        m.contains('network and try again') ||
        m.contains('request took too long') ||
        m.contains('connection error');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isInfo = widget.isInfo;
    final isConnection = !isInfo && _isConnectionRelated(widget.message);
    final isDark = theme.brightness == Brightness.dark;
    // Info = blue/teal; error = red
    final accentBorderColor = isInfo ? Colors.blue.shade600 : Colors.red.shade600;
    final iconBg = isInfo ? Colors.blue.shade50 : Colors.red.shade50;
    final iconBorder = isInfo ? Colors.blue.shade200 : Colors.red.shade200;
    final iconColor = isInfo ? Colors.blue.shade700 : Colors.red.shade700;
    final buttonColor = isInfo ? Colors.blue.shade600 : Colors.red.shade600;
    final shadowTint = isInfo ? Colors.blue.shade100 : Colors.red.shade100;

    return FadeTransition(
      opacity: _entranceOpacity,
      child: ScaleTransition(
        scale: _entranceScale,
        alignment: Alignment.center,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 440, minWidth: 300),
                decoration: BoxDecoration(
                  color: isDark
                      ? theme.colorScheme.surface.withValues(alpha: 0.95)
                      : Colors.white.withValues(alpha: 0.98),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: accentBorderColor,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                      spreadRadius: 0,
                    ),
                    if (!isDark)
                      BoxShadow(
                        color: shadowTint.withValues(alpha: 0.3),
                        blurRadius: 24,
                        offset: const Offset(0, 4),
                        spreadRadius: -4,
                      ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Icon: info = info_rounded (blue); connection = pulsing wifi_off (red); else error (red)
                              if (isInfo)
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: iconBg,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: iconBorder, width: 1.5),
                                  ),
                                  child: Icon(
                                    Icons.info_outline_rounded,
                                    color: iconColor,
                                    size: 32,
                                  ),
                                )
                              else if (isConnection)
                                AnimatedBuilder(
                                  animation: _pulseScale,
                                  builder: (context, child) {
                                    return Transform.scale(
                                      scale: _pulseScale.value,
                                      child: Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: iconBg,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(color: iconBorder, width: 1.5),
                                        ),
                                        child: Icon(
                                          Icons.wifi_off_rounded,
                                          color: iconColor,
                                          size: 32,
                                        ),
                                      ),
                                    );
                                  },
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: iconBg,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: iconBorder, width: 1.5),
                                  ),
                                  child: Icon(
                                    Icons.error_outline_rounded,
                                    color: iconColor,
                                    size: 32,
                                  ),
                                ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    widget.title,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 160),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                widget.message,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                                  height: 1.5,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              FilledButton.icon(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.check_rounded, size: 20),
                                label: const Text('OK'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  backgroundColor: buttonColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
