import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Screens
import 'login_screen.dart';
import 'hod_dashboard.dart';
import 'pg_dashboard.dart';
import 'faculty_dashboard.dart';
import 'opd_entry_dashboard.dart';

// Notifications
import 'notification_service.dart';

// Firebase Options
import 'firebase_options.dart';

// ==========================================================
// 🔥 Background handler (ONLY Android)
// ==========================================================
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (Platform.isAndroid) {
    debugPrint("🔔 Background Message: ${message.notification?.title}");
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (Platform.isAndroid) {
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
    }
  } catch (e) {
    debugPrint("Firebase Init Error: $e");
  }

  runApp(const MyApp());
}

// 🎨 Theme
class AppColors {
  static const Color primary = Color(0xFFC8E6C9);
  static const Color background = Color(0xFFF1F8E9);
  static const Color accentTeal = Color(0xFF00695C);
  static const Color textDark = Color(0xFF2D3436);
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isFCMInitialized = false;

  @override
  void initState() {
    super.initState();

    // ✅ AUTO-LOGIN REMOVED: No more _loadUserSession() call here.

    // ✅ Notification logic (Android Only) - Kept active
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await NotificationService().init();
          await _setupFCM();

          if (!_isFCMInitialized) {
            NotificationService().setupFCMListeners();
            _isFCMInitialized = true;
          }
        } catch (e) {
          debugPrint("Notification Error: $e");
        }
      });
    }
  }

  // ================= 🔔 ANDROID ONLY FCM SETUP =================
  Future<void> _setupFCM() async {
    if (!Platform.isAndroid) return;

    FirebaseMessaging messaging = FirebaseMessaging.instance;

    await messaging.requestPermission();
    await messaging.setAutoInitEnabled(true);

    String? token = await messaging.getToken();
    debugPrint("🔥 FCM TOKEN: $token");

    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      debugPrint("🔄 Token Refreshed: $newToken");
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint("🔔 Message: ${message.notification?.title}");

      if (message.notification != null) {
        NotificationService().showNotification(
          title: message.notification!.title ?? "New Notification",
          body: message.notification!.body ?? "",
          payload: message.data['senderId'] ?? "",
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint("📲 Opened from notification");
    });

    RemoteMessage? initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint("🚀 Opened from terminated state");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AlignTrack',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.accentTeal,
          primary: AppColors.accentTeal,
          secondary: AppColors.primary,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textDark,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: AppColors.textDark,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      // ✅ FIXED: Hardcoded LoginScreen as the entry point.
      // No checks, no "Restoring Session" spinner, no auto-login.
      home: const LoginScreen(),
    );
  }
}
