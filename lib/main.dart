import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Screens
import 'login_screen.dart';

// Notifications
import 'notification_service.dart';

// Firebase Options ← ADD THIS
import 'firebase_options.dart';

// ==========================================================
// 🔥 Background notification handler
// ==========================================================
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // ← ADD THIS
  );
  debugPrint("🔔 Background Message: ${message.notification?.title}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔥 Register background handler BEFORE Firebase init
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

  try {
    // ✅ Initialize Firebase WITH options
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

    Future.microtask(() async {
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

  Future<void> _setupFCM() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint("Permission Status: ${settings.authorizationStatus}");

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    String? token = await messaging.getToken();
    debugPrint("🔥 FCM TOKEN: $token");

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      debugPrint("🔄 New Token: $newToken");
    });

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

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint("📲 Notification Clicked (Background): ${message.data}");
    });

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
