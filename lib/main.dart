import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'firebase_web_plugins.dart';
import 'screens/auth_gate.dart';
import 'services/auth_service.dart';
import 'services/reminder_service.dart';
import 'widgets/presence_listener.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerWebFirebasePlugins();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Restore the persisted login session before the UI starts.
  await AuthService.waitForPersistedSession();

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await ReminderService.instance.init();
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF3B5BDB);

    return MaterialApp(
      title: 'ATS CRM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F8FC),
        textTheme: Typography.material2021().black,
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0.3,
          backgroundColor: Color(0xFFF7F8FC),
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1D2638),
          ),
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          margin: EdgeInsets.zero,
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDCE2EE)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDCE2EE)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: seedColor, width: 1.2),
          ),
        ),
      ),
      builder: (context, child) => PresenceListener(child: child!),
      home: const AuthGate(),
    );
  }
}
