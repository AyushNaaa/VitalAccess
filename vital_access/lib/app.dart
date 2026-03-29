import 'package:flutter/material.dart';
import 'config/theme.dart';
import 'config/constants.dart';
import 'screens/language_select_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/symptom_chat_screen.dart';
import 'screens/processing_screen.dart';
import 'screens/result_screen.dart';

class VitalAccessApp extends StatelessWidget {
  const VitalAccessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VitalAccess',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: AppRoutes.language,
      onGenerateRoute: (settings) {
        Widget page;
        switch (settings.name) {
          case AppRoutes.language:
            page = const LanguageSelectScreen();
          case AppRoutes.scan:
            page = const ScanScreen();
          case AppRoutes.chat:
            page = const SymptomChatScreen();
          case AppRoutes.processing:
            page = const ProcessingScreen();
          case AppRoutes.result:
            page = const ResultScreen();
          default:
            page = const LanguageSelectScreen();
        }
        return PageRouteBuilder(
          settings: settings,
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
              ),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 250),
        );
      },
    );
  }
}
