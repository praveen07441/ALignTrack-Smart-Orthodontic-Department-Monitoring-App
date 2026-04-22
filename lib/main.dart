import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Screens
import 'login_screen.dart';

// Notifications
import 'notification_service.dart';

// ==========================================================
// 🔥 REQUIRED for background notifications
// This must be a top-level function (outside any class)
// ==========================================================
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("🔔 Background Message: ${message.notification?.title}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // 1. Initialize Firebase
    await Firebase.initializeApp();

    // 2. Register background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
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

    // Use microtask to perform async initialization after the first build frame
    Future.microtask(() async {
      try {
        // 🔥 Initialize local notifications
        await NotificationService().init();

        // 🔥 Request permissions (local + FCM)
        await NotificationService().requestPermissions();

        // 🔥 Setup Firebase Messaging Configuration
        await _setupFCM();

        // 🔥 Avoid duplicate listeners if initState is called multiple times
        if (!_isFCMInitialized) {
          NotificationService().setupFCMListeners();
          _isFCMInitialized = true;
        }
      } catch (e) {
        debugPrint("Notification Error: $e");
      }
    });
  }

  // ================= 🔔 FCM SETUP & LISTENERS =================
  Future<void> _setupFCM() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // 1. Request explicit permission (Crucial for iOS and Android 13+)
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint("Permission Status: ${settings.authorizationStatus}");

    // 2. Get device token for debugging/database
    String? token = await messaging.getToken();
    debugPrint("🔥 FCM TOKEN: $token");

    // ⚠️ Note: Actual token saving logic is handled in login_screen.dart
    // to link the token to a specific UID.

    // 3. Foreground Message Listener
    // Triggered when the app is open and in view
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

    // 4. Background Click Listener
    // Triggered when the app is in the background and the user taps the notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint("📲 Notification Clicked (Background): ${message.data}");
    });

    // 5. Terminated State handling
    // Triggered if the app was completely closed and opened via a notification tap
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
      title: 'Clinical Monitor',
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
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accentTeal,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
