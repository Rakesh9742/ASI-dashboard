import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'widgets/auth_wrapper.dart';
import 'screens/standalone_project_screen.dart';
import 'screens/standalone_view_screen.dart';
import 'screens/qms_dashboard_screen.dart';
import 'providers/theme_provider.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    
    return MaterialApp(
      title: 'SemiconOS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
          primary: Colors.blue.shade700,
          secondary: Colors.blue.shade600,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey.shade50,
        dividerColor: Colors.grey.shade300,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.blue.shade700, width: 2),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
          primary: Colors.blue.shade300,
          secondary: Colors.blue.shade400,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey.shade900,
        cardColor: Colors.grey.shade800,
        dividerColor: Colors.grey.shade700,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade800,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade700),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade700),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.blue.shade300, width: 2),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      themeMode: themeMode,
      home: const AuthWrapper(),
      onGenerateRoute: (settings) {
        if (settings.name == '/project' || settings.name?.contains('/project') == true) {
          return MaterialPageRoute(
            builder: (context) => const StandaloneProjectScreen(),
          );
        }
        if (settings.name == '/view' || settings.name?.contains('/view') == true) {
          return MaterialPageRoute(
            builder: (context) => const StandaloneViewScreen(),
          );
        }
        if (settings.name == '/qms-dashboard' || settings.name?.contains('/qms-dashboard') == true) {
          // Extract blockId from query parameters
          final uri = Uri.parse(settings.name ?? '');
          final blockIdStr = uri.queryParameters['blockId'];
          if (blockIdStr != null) {
            final blockId = int.tryParse(blockIdStr);
            if (blockId != null) {
              return MaterialPageRoute(
                builder: (context) => QmsDashboardScreen(blockId: blockId),
              );
            }
          }
          // Fallback: try to get from localStorage
          try {
            final storedBlockId = html.window.localStorage['standalone_qms_blockId'];
            if (storedBlockId != null) {
              final blockId = int.tryParse(storedBlockId);
              if (blockId != null) {
                return MaterialPageRoute(
                  builder: (context) => QmsDashboardScreen(blockId: blockId),
                );
              }
            }
          } catch (e) {
            // Ignore errors
          }
        }
        return null;
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

