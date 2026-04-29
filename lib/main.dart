import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Screens
import 'login_screen.dart';

// Notifications
import 'notification_service.dart';

// Firebase Options
import 'firebase_options.dart';

// ==========================================================
// 🔥 REQUIRED for background notifications
// ==========================================================
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized in the background isolate
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint("🔔 Background Message received: ${message.notification?.title}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Firebase first
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // 2. Register background handler AFTER Firebase init
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
  } catch (e) {
    debugPrint("Firebase Initialization Error: $e");
  }

  runApp(const MyApp());
}

// 🎨 Global Theme Colors (Clean, Professional Minimalist)
class AppColors {
  static const Color primary = Color(0xFFC8E6C9); // Soft Pale Green/Grey
  static const Color background = Color(0xFFF1F8E9); // Light Mint/White
  static const Color accentTeal = Color(0xFF00695C); // Deep Professional Teal
  static const Color textDark = Color(0xFF2D3436); // Dark Slate Grey
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

    // Use addPostFrameCallback to ensure UI is ready before triggering logic
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // Initialize local notification settings
        await NotificationService().init();

        // Setup FCM and permissions
        await _setupFCM();

        if (!_isFCMInitialized) {
          NotificationService().setupFCMListeners();
          _isFCMInitialized = true;
        }
      } catch (e) {
        debugPrint("Notification Setup Error: $e");
      }
    });
  }

  // ================= 🔔 FCM SETUP =================
  Future<void> _setupFCM() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // 1. Request permission first (Crucial for iOS APNs handshake)
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint("Permission Status: ${settings.authorizationStatus}");

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint("❌ User declined notification permissions.");
      return;
    }

    // 2. ✅ iOS Specific: Wait for APNS token before fetching FCM token
    if (Platform.isIOS) {
      debugPrint("🍎 iOS detected. Waiting for APNS token...");

      String? apnsToken;
      // Increased retry logic for physical hardware
      for (int i = 0; i < 15; i++) {
        apnsToken = await messaging.getAPNSToken();
        if (apnsToken != null) break;

        debugPrint("⏳ Still waiting for APNS token... attempt ${i + 1}");
        await Future.delayed(const Duration(seconds: 2));
      }

      if (apnsToken == null) {
        debugPrint(
            "❌ CRITICAL: APNS token not found. Push notifications will fail on this device.");
        return;
      }
      debugPrint("✅ APNS TOKEN RECEIVED: $apnsToken");
    }

    // 3. Manually enable FCM auto-init
    await messaging.setAutoInitEnabled(true);

    // 4. ✅ Fetch FCM Token
    String? token = await messaging.getToken();
    debugPrint("🔥 FCM TOKEN: $token");

    // 5. Set foreground presentation options
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 6. Token refresh listener
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      debugPrint("🔄 FCM Token Refreshed: $newToken");
    });

    // 7. Foreground messages listener
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint("🔔 Foreground Message: ${message.notification?.title}");
      if (message.notification != null) {
        NotificationService().showNotification(
          title: message.notification!.title ?? "New Notification",
          body: message.notification!.body ?? "",
          payload: message.data['senderId'] ?? "",
        );
      }
    });

    // 8. Interaction: When app is in background but opened via notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint("📲 App opened from notification: ${message.data}");
    });

    // 9. Interaction: When app is terminated and opened via notification
    RemoteMessage? initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint(
          "🚀 App launched from terminated state: ${initialMessage.data}");
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
      home: const LoginScreen(),
    );
  }
}
