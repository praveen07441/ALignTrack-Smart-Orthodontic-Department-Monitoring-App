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

  // ================= INIT =================
  Future<void> init() async {
    if (!Platform.isAndroid) return; // ❌ Skip iOS completely
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

    await _notifications.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: (details) {
        debugPrint("🔔 Notification tapped: ${details.payload}");
      },
    );

    // ✅ Android Notification Channel
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

    _isInitialized = true;
    debugPrint("✅ Notification Service Initialized (Android only)");
  }

  // ================= FCM LISTENER =================
  void setupFCMListeners() {
    if (!Platform.isAndroid) return;

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

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint("📲 Opened from background: ${message.data}");
    });

    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        debugPrint("🚀 Opened from terminated: ${message.data}");
      }
    });
  }

  // ================= SETTINGS =================
  NotificationDetails _getDetails() {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'clinical_reminders_v4',
        'Clinical Notifications',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        vibrationPattern: Int64List.fromList(const [0, 500, 200, 500]),
      ),
    );
  }

  // ================= SHOW =================
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!Platform.isAndroid) return;

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
    if (!Platform.isAndroid) return;

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
    if (!Platform.isAndroid) return;

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

  // ================= CANCEL =================
  Future<void> cancelNotification(int id) async {
    if (!Platform.isAndroid) return;
    await _notifications.cancel(id);
  }

  Future<void> cancelAll() async {
    if (!Platform.isAndroid) return;
    await _notifications.cancelAll();
  }
}
