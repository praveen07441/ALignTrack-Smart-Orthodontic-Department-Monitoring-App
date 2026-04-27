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
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint("🔔 Background Message: ${message.notification?.title}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔥 Register background handler BEFORE Firebase init
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Initialization Error: $e");
  }

  runApp(const MyApp());
}

// 🎨 Global Theme Colors
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

    // ✅ Using addPostFrameCallback instead of microtask
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await NotificationService().init();
        await NotificationService().requestPermissions();
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

  // ================= 🔔 FCM SETUP =================
  Future<void> _setupFCM() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // ✅ Manually enable FCM since auto-init is disabled in Info.plist
    await FirebaseMessaging.instance.setAutoInitEnabled(true);

    // 1. Request permission first
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint("Permission Status: ${settings.authorizationStatus}");

    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      debugPrint("❌ Notifications not authorized");
      return;
    }

    // 2. Set foreground options BEFORE getting tokens
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 3. ✅ Wait for APNS token with retry loop (iOS only)
    String? apnsToken;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      for (int i = 0; i < 10; i++) {
        apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        if (apnsToken != null) break;
        debugPrint("⏳ Waiting for APNS token... attempt ${i + 1}");
        await Future.delayed(const Duration(seconds: 2));
      }

      if (apnsToken == null) {
        debugPrint("❌ APNS token unavailable after retries. Skipping FCM.");
        return;
      }
      debugPrint("🍎 APNS TOKEN: $apnsToken");
    }

    // 4. ✅ Now safely get FCM token
    String? token = await messaging.getToken();
    debugPrint("🔥 FCM TOKEN: $token");

    // 5. Token refresh listener
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      debugPrint("🔄 New Token: $newToken");
    });

    // 6. Foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint("🔔 Foreground Message: ${message.notification?.title}");
      if (message.notification != null) {
        NotificationService().showNotification(
          title: message.notification!.title ?? "New Message",
          body: message.notification!.body ?? "",
          payload: message.data['senderId'],
        );
      }
    });

    // 7. Background tap
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint("📲 Notification Clicked (Background): ${message.data}");
    });

    // 8. Terminated state
    RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      debugPrint("🚀 Opened from terminated state: ${initialMessage.data}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ALignTrack',
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
