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
      await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    // 🔥 ALSO request FCM permission
    await FirebaseMessaging.instance.requestPermission();
  }

  // ================= INIT =================
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.local);
    } catch (e) {
      debugPrint("Timezone init failed: $e");
      tz.setLocalLocation(tz.UTC);
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _notifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: (details) {
        debugPrint("🔔 Notification tapped: ${details.payload}");
        // 👉 You can navigate to chat screen here using NavigatorKey
      },
    );

    // 🔥 Create Notification Channel
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'clinical_reminders_v4',
        'Clinical Notifications',
        description: 'App notifications',
        importance: Importance.max,
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
      ),
    );
  }

  // ================= 🔔 SHOW NOTIFICATION =================
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
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
      title: "🔔 Test",
      body: "Notification working!",
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
