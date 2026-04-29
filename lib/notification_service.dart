import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:flutter/foundation.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  // ================= PERMISSIONS =================
  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      final androidImpl = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
      await androidImpl?.requestExactAlarmsPermission();
    } else if (Platform.isIOS) {
      // For iOS, this triggers the native Apple "Allow Notifications" popup
      await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
            critical: true, // Useful for urgent clinical alerts
          );
    }

    // 🔥 ALSO request FCM permission (Essential for APNS handshake)
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  // ================= INIT =================
  Future<void> init() async {
    if (_isInitialized) return;

    // Initialize Timezones for scheduling
    try {
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.local);
    } catch (e) {
      debugPrint("Timezone init failed: $e");
      tz.setLocalLocation(tz.UTC);
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // Default iOS settings - permissions handled explicitly in requestPermissions()
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _notifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: (details) {
        debugPrint("🔔 Notification tapped: ${details.payload}");
        // Navigation logic for clinical alerts or chat can be placed here
      },
    );

    // 🔥 Create Android Notification Channel
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'clinical_reminders_v4',
        'Clinical Notifications',
        description: 'Department monitoring and clinical updates',
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
      );

      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    _isInitialized = true;
    debugPrint("✅ Notification Service Initialized");
  }

  // ================= FCM LISTENER =================
  void setupFCMListeners() {
    // 🔔 Foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;

      if (notification != null) {
        showNotification(
          title: notification.title ?? "New Message",
          body: notification.body ?? "",
          payload: message.data['senderId'],
        );
      }
    });

    // 🔔 Background click
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint("📲 Opened from background: ${message.data}");
    });

    // 🔔 Terminated state
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        debugPrint("🚀 Opened from terminated: ${message.data}");
      }
    });
  }

  // ================= COMMON SETTINGS =================
  NotificationDetails _getDetails() {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'clinical_reminders_v4',
        'Clinical Notifications',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel:
            InterruptionLevel.active, // 🔥 Required for banners on iOS 15+
      ),
    );
  }

  // ================= 🔔 SHOW NOTIFICATION =================
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    // Using a safe ID generation
    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await _notifications.show(
      id,
      title,
      body,
      _getDetails(),
      payload: payload,
    );
  }

  // ================= TEST =================
  Future<void> testInstantNotification() async {
    await showNotification(
      title: "🔔 Test Notification",
      body: "Alert system is operational!",
    );
  }

  // ================= SCHEDULE =================
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    final scheduledTZTime = tz.TZDateTime.from(scheduledTime, tz.local);

    if (scheduledTZTime.isBefore(tz.TZDateTime.now(tz.local))) {
      debugPrint("❌ Cannot schedule in past");
      return;
    }

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      scheduledTZTime,
      _getDetails(),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}
