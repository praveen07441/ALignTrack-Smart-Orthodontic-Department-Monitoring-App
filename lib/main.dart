import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:permission_handler/permission_handler.dart';

// Firebase Config
import 'firebase_options.dart';

// Screens
import 'login_screen.dart';
import 'hod_dashboard.dart';
import 'pg_dashboard.dart';
import 'faculty_dashboard.dart';
import 'opd_entry_dashboard.dart';

// Notifications
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🚀 Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 🔔 Initialize Notification Service
  final notificationService = NotificationService();
  await notificationService.init();

  // 🔐 Request Permissions (FCM & Local Notifications)
  await notificationService.requestPermissions();

  runApp(const MyApp());
}

// 🎨 Global Brand Colors
class AppColors {
  static const Color primary = Color(0xFFC8E6C9);
  static const Color background = Color(0xFFF1F8E9);
  static const Color accentTeal = Color(0xFF075E54);
  static const Color cardShadow = Color(0x1A000000);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  /// 🛡️ Android 13+ Specific Notification Permission Request
  Future<void> _requestAndroidPermissions() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Execute permission check once the app starts
    Future.microtask(() => _requestAndroidPermissions());

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Clinical Monitor',

      // 🎭 Premium Material 3 Theme Configuration
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.accentTeal,
          primary: AppColors.accentTeal,
          secondary: AppColors.primary,
          brightness: Brightness.light,
        ),

        // App Bar Styling
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 20,
            letterSpacing: 0.5,
          ),
        ),

        // Card Styling
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),

        // Input/TextField Styling
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.accentTeal, width: 2),
          ),
        ),

        // Button Styling
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accentTeal,
            foregroundColor: Colors.white,
            elevation: 2,
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),

      // 🛣️ Defined Routes for easy navigation management
      routes: {
        '/hod': (context) => const HodDashboard(userId: 'HOD_USER'),
        '/pg': (context) =>
            const PgDashboard(userId: 'PG_USER', userName: 'PG Student'),
        '/faculty': (context) => const FacultyDashboard(
            userId: 'FAC_USER', userName: 'Faculty Member'),
        '/opd': (context) => const OpdEntryDashboard(
            userId: 'OPD_USER', userName: 'OPD Registrar'),
      },

      // 🏠 Entry Point
      home: const LoginScreen(),
    );
  }
}
