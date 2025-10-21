// lib/services/push_notifications.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Timezone support for precise local scheduling
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:flutter_native_timezone/flutter_native_timezone.dart';

import '../models/task.dart';

class PushNotifications {
  static final FlutterLocalNotificationsPlugin _fln =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _defaultChannel =
      AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'Used for important notifications.',
    importance: Importance.high,
  );

  static bool _tzReady = false;

  /// Call once at startup from main().
  static Future<void> init() async {
    // Create Android notification channel
    try {
      await _fln
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_defaultChannel);
    } catch (e) {
      debugPrint('createNotificationChannel error: $e');
    }

    // --- Init local notifications ---
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // Request iOS/macOS permissions via initialization settings
    const DarwinInitializationSettings darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    try {
      await _fln.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // Handle tap on local notification if needed (use response.payload)
        },
      );
    } catch (e) {
      debugPrint('Local notifications init error: $e');
    }

    // Ask push/FCM permissions (foreground banners, etc.)
    await _requestPermissionsSafe();

    // iOS/macOS: show alerts while app is foreground
    try {
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint('PresentationOptions error: $e');
    }

    // Foreground FCM -> mirror as local notification
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showLocalForRemote(message);
    });

    // Prepare timezone for scheduling
    await _ensureTimezone();
  }

  static Future<void> _ensureTimezone() async {
    if (_tzReady) return;
    try {
      tz.initializeTimeZones();
      final name = await FlutterNativeTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
      _tzReady = true;
    } catch (e) {
      debugPrint('Timezone init error: $e');
      _tzReady = true; // still allow scheduling using tz.local
    }
  }

  static Future<void> _requestPermissionsSafe() async {
    try {
      // FCM push permission (iOS/macOS shows the system prompt)
      await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
      );

      // Android 13+ runtime permission for notifications
      // if (Platform.isAndroid) {
      //   await _fln
      //       .resolvePlatformSpecificImplementation<
      //           AndroidFlutterLocalNotificationsPlugin>()
      //       ?.requestPermission();
      // }
    } catch (e) {
      debugPrint('Permission request error: $e');
    }
  }

  /// Mirror remote (foreground) to a local banner.
  static Future<void> _showLocalForRemote(RemoteMessage message) async {
    final notif = message.notification;
    final android = notif?.android;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _defaultChannel.id,
        _defaultChannel.name,
        channelDescription: _defaultChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: android?.smallIcon ?? '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(),
      macOS: const DarwinNotificationDetails(),
    );

    try {
      await _fln.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        notif?.title ?? 'Notification',
        notif?.body ?? '',
        details,
        payload: message.data.isNotEmpty ? message.data.toString() : null,
      );
    } catch (e) {
      debugPrint('show local notif error: $e');
    }
  }

  // ======== TASK REMINDERS ========

  /// Schedule 5-minute and 1-minute reminders before [startAtLocal].
  /// If either time is already past, it’s skipped.
  static Future<void> scheduleTaskReminders(Task task, DateTime startAtLocal) async {
    await _ensureTimezone();
    if (task.completed) return;

    // Stable base ID for this task on today's date + start time
    final today = DateTime.now();
    final baseId = _baseId(
      task,
      date: DateTime(today.year, today.month, today.day),
      start: startAtLocal,
    );

    Future<void> _scheduleMinus(Duration delta, int salt) async {
      final when = startAtLocal.subtract(delta);

      // Skip if already past (give 2s buffer)
      if (when.isBefore(DateTime.now().add(const Duration(seconds: 2)))) return;

      final tzWhen = tz.TZDateTime.from(when, tz.local);
      final id = baseId ^ salt;

      final minutes = delta.inMinutes;
      final phrase = minutes == 1 ? '1 minute' : '$minutes minutes';
      final bannerTitle = '${task.title} is starting in $phrase';

      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _defaultChannel.id,
          _defaultChannel.name,
          channelDescription: _defaultChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          category: AndroidNotificationCategory.reminder,
        ),
        iOS: const DarwinNotificationDetails(
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
        macOS: const DarwinNotificationDetails(),
      );

      try {
        await _fln.zonedSchedule(
          id,
          bannerTitle,                 // <-- exact banner text you asked for
          'Tap to view in the app',    // body (optional)
          tzWhen,
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: 'task:${task.title}',
          matchDateTimeComponents: null,
        );
      } catch (e) {
        debugPrint('zonedSchedule error: $e');
      }
    }

    await _scheduleMinus(const Duration(minutes: 5), 0x5);
    await _scheduleMinus(const Duration(minutes: 1), 0x1);
  }

  /// Cancel the two reminders previously scheduled for [task] at [startAtLocal].
  static Future<void> cancelTaskReminders(Task task, DateTime startAtLocal) async {
    final today = DateTime.now();
    final baseId = _baseId(
      task,
      date: DateTime(today.year, today.month, today.day),
      start: startAtLocal,
    );
    try {
      await _fln.cancel(baseId ^ 0x5);
      await _fln.cancel(baseId ^ 0x1);
    } catch (e) {
      debugPrint('cancel error: $e');
    }
  }

  /// Create a stable ID for a task on a specific day & start time.
  static int _baseId(Task task, {required DateTime date, required DateTime start}) {
    final key = '${task.title}|${task.startTime}|${task.period}|'
        '${date.year}-${date.month}-${date.day}|'
        '${start.hour}:${start.minute}';
    return key.hashCode & 0x7fffffff; // positive 31-bit int
  }

  // ======== Optional helpers ========

  static Future<String?> getToken() async {
    try { return await FirebaseMessaging.instance.getToken(); }
    catch (e) { debugPrint('getToken error: $e'); return null; }
  }

  static Future<void> subscribe(String topic) =>
      FirebaseMessaging.instance.subscribeToTopic(topic);
  static Future<void> unsubscribe(String topic) =>
      FirebaseMessaging.instance.unsubscribeFromTopic(topic);
}