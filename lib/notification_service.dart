import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:flutter/foundation.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // 🔥 PERMISSIONS (ANDROID 10+ & 13+)
  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      final androidImplementation =
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      await androidImplementation?.requestExactAlarmsPermission();
      await androidImplementation?.requestNotificationsPermission();
    }
  }

  // 🔥 INIT SERVICE
  Future<void> init() async {
    tz_data.initializeTimeZones();

    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (e) {
      debugPrint("Timezone error: $e");
    }

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    await _notifications.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: (details) {
        debugPrint("Notification tapped: ${details.payload}");
      },
    );

    // 🔥 HIGH PRIORITY CHANNEL
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'alarm_channel_v2',
      'Clinical Alarm Reminders',
      description: 'Critical reminder alerts',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  // 🔧 TEST NOTIFICATION (FOR SETTINGS TRIGGER)
  Future<void> testInstantNotification() async {
    final vibrationPattern = Int64List.fromList([0, 500, 200, 500, 200, 1000]);

    final androidDetails = AndroidNotificationDetails(
      'alarm_channel_v2',
      'Clinical Alarm Reminders',
      importance: Importance.max,
      priority: Priority.high,

      // 🔥 CRITICAL (FOR ONEPLUS LIST APPEAR)
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,

      enableVibration: true,
      vibrationPattern: vibrationPattern,
      playSound: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      "🔔 Test Reminder",
      "Notification system is working",
      NotificationDetails(android: androidDetails),
    );
  }

  // 🔥 FINAL SCHEDULER (100% RELIABLE)
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    final vibrationPattern = Int64List.fromList([0, 500, 200, 500, 200, 1000]);

    final scheduledTZTime = tz.TZDateTime.from(scheduledTime, tz.local);

    if (scheduledTZTime.isBefore(tz.TZDateTime.now(tz.local))) {
      debugPrint("❌ Cannot schedule past time");
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      'alarm_channel_v2',
      'Clinical Alarm Reminders',
      importance: Importance.max,
      priority: Priority.high,

      // 🔥 VERY IMPORTANT FOR ONEPLUS + TECNO
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,

      enableVibration: true,
      vibrationPattern: vibrationPattern,
      playSound: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      scheduledTZTime,
      NotificationDetails(android: androidDetails),

      // 🔥 CRITICAL (FOR OEM DEVICES)
      androidScheduleMode: AndroidScheduleMode.alarmClock,

      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,

      matchDateTimeComponents: null,
    );

    debugPrint("✅ Scheduled at $scheduledTZTime");
  }

  Future<void> cancelNotification(int id) async =>
      await _notifications.cancel(id);

  Future<void> cancelAll() async => await _notifications.cancelAll();
}
