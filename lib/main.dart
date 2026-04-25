import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Screens
import 'login_screen.dart';

// Notifications
import 'notification_service.dart';

// ==========================================================
// 🔥 REQUIRED for background notifications
// ==========================================================
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("🔔 Background Message: ${message.notification?.title}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔥 Register background handler BEFORE Firebase init (best practice)
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

  try {
    // Initialize Firebase
    await Firebase.initializeApp();
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

    Future.microtask(() async {
      try {
        // 🔥 Initialize local notifications
        await NotificationService().init();

        // 🔥 Request permissions
        await NotificationService().requestPermissions();

        // 🔥 Setup FCM
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

    // 1. Request permission (iOS + Android 13+)
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint("Permission Status: ${settings.authorizationStatus}");

    // 🔥 IMPORTANT: Show notifications in foreground (iOS)
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2. Get FCM Token
    String? token = await messaging.getToken();
    debugPrint("🔥 FCM TOKEN: $token");

    // 🔄 Token refresh listener
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      debugPrint("🔄 New Token: $newToken");
    });

    // 3. Foreground messages
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

    // 4. Background click
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint("📲 Notification Clicked (Background): ${message.data}");
    });

    // 5. Terminated state
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
      ),
      home: const LoginScreen(),
    );
  }
}
