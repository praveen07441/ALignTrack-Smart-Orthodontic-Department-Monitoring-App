import 'dart:io';
import 'dart:typed_data';
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
  bool _isInitialized = false;

  // ✅ REQUEST PERMISSIONS (Critical for Android 13+ & iOS)
  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      final androidImpl = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestExactAlarmsPermission();
      await androidImpl?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  // ✅ INIT SERVICE
  Future<void> init() async {
    if (_isInitialized) return; // Prevent double initialization

    // ✅ SAFE TIMEZONE INIT: Prevents iOS boot freeze
    try {
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.local);
    } catch (e) {
      debugPrint("Timezone init failed: $e. Falling back to UTC.");
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
        debugPrint("Notification tapped with payload: ${details.payload}");
      },
    );

    // Create High-Importance Channel for Android
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'clinical_reminders_v4',
        'Clinical Alarm Reminders',
        description: 'Critical patient care and task alerts',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    _isInitialized = true;
    debugPrint("✅ Notification Service Initialized (iOS Ready)");
  }

  // 🔧 SHARED NOTIFICATION DETAILS
  NotificationDetails _getNotificationDetails({String? category}) {
    if (Platform.isAndroid) {
      final vibrationPattern =
          Int64List.fromList([0, 500, 200, 500, 200, 1000]);
      return NotificationDetails(
        android: AndroidNotificationDetails(
          'clinical_reminders_v4',
          'Clinical Alarm Reminders',
          importance: Importance.max,
          priority: Priority.high,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.alarm,
          visibility: NotificationVisibility.public,
          vibrationPattern: vibrationPattern,
          playSound: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        ),
      );
    } else {
      return const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          // ✅ SAFE LEVEL: Uses 'active' to avoid entitlement issues
          interruptionLevel: InterruptionLevel.active,
        ),
      );
    }
  }

  // 🔔 INSTANT TEST
  Future<void> testInstantNotification() async {
    await _notifications.show(
      999,
      "🔔 System Test",
      "ALignTrack notification service is active.",
      _getNotificationDetails(),
      payload: 'test_payload',
    );
  }

  // ⏰ SCHEDULED ALARM
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    final scheduledTZTime = tz.TZDateTime.from(scheduledTime, tz.local);

    if (scheduledTZTime.isBefore(tz.TZDateTime.now(tz.local))) {
      debugPrint("❌ Cannot schedule in the past: $scheduledTZTime");
      return;
    }

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      scheduledTZTime,
      _getNotificationDetails(),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );

    debugPrint("✅ Scheduled: '$title' for $scheduledTZTime");
  }

  Future<void> cancelNotification(int id) async =>
      await _notifications.cancel(id);
  Future<void> cancelAll() async => await _notifications.cancelAll();
}
