import 'dart:async';

import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/task.dart';

/// Centralized push + local notification helper.
///
/// Responsibilities:
/// * request the right permissions on every platform
/// * mirror foreground FCM messages as local notifications (nice-to-have)
/// * schedule/cancel the “5 minutes before” and “1 minute before” task reminders
class PushNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static bool _timezoneReady = false;
  static final StreamController<String> _notificationTapController =
      StreamController<String>.broadcast();

  static Stream<String> get notificationTaps => _notificationTapController.stream;

  static const AndroidNotificationChannel _defaultChannel =
      AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'Used for reminders and mirrored push notifications.',
    importance: Importance.high,
  );

  /// Entry point — call once from `main()` *after* Firebase.initializeApp.
  static Future<void> init() async {
    if (_initialized) return;
    await _configureLocalPlugin();
    await _createAndroidChannel();
    await _ensureTimezone();
    await _requestPermissions();

    // Allow foreground FCM banners on Apple platforms.
    try {
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint('Foreground presentation setup failed: $e');
    }

    FirebaseMessaging.onMessage.listen(_mirrorRemoteMessage);

    _initialized = true;
  }

  // ---------- Public API ----------

  /// Schedule reminders 5 minutes and 1 minute before [startLocal].
  static Future<void> scheduleTaskReminders(Task task, DateTime startLocal) async {
    if (!_initialized) {
      await init();
    }
    await _ensureTimezone();
    debugPrint('[PushNotifications] Scheduling reminders for "${task.title}" at $startLocal');

    final tzStart = tz.TZDateTime.from(startLocal, tz.local);
    await _scheduleSingle(task, tzStart.subtract(const Duration(minutes: 5)), startLocal,
        salt: 0x5);
    await _scheduleSingle(task, tzStart.subtract(const Duration(minutes: 1)), startLocal,
        salt: 0x1);
  }

  /// Remove the previously scheduled reminders for [task].
  static Future<void> cancelTaskReminders(Task task, DateTime startLocal) async {
    final baseId = _notificationBase(task, startLocal);
    try {
      await _plugin.cancel(baseId ^ 0x5);
      await _plugin.cancel(baseId ^ 0x1);
    } catch (e) {
      debugPrint('cancelTaskReminders error: $e');
    }
  }

  // Optional helpers for diagnostics/UI.
  static Future<String?> getToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('getToken error: $e');
      return null;
    }
  }

  static Future<void> subscribe(String topic) =>
      FirebaseMessaging.instance.subscribeToTopic(topic);

  static Future<void> unsubscribe(String topic) =>
      FirebaseMessaging.instance.unsubscribeFromTopic(topic);

  // ---------- Internal plumbing ----------

  static Future<void> _configureLocalPlugin() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      requestCriticalPermission: true,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
      defaultPresentBanner: true,
      defaultPresentList: true,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    try {
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            debugPrint('[PushNotifications] Notification tap payload: $payload');
            _notificationTapController.add(payload);
          }
        },
      );
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      final initialPayload = launchDetails?.notificationResponse?.payload;
      if ((launchDetails?.didNotificationLaunchApp ?? false) &&
          initialPayload != null &&
          initialPayload.isNotEmpty) {
        Future.microtask(() {
          debugPrint('[PushNotifications] App launched from notification: $initialPayload');
          _notificationTapController.add(initialPayload);
        });
      }
    } catch (e) {
      debugPrint('Local notification init error: $e');
    }
  }

  static Future<void> _createAndroidChannel() async {
    try {
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_defaultChannel);
    } catch (e) {
      debugPrint('createNotificationChannel error: $e');
    }
  }

  static Future<void> _requestPermissions() async {
    try {
      if (!kIsWeb) {
        switch (defaultTargetPlatform) {
          case TargetPlatform.iOS:
            await _plugin
                .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(
                  alert: true,
                  badge: true,
                  sound: true,
                  critical: true,
                );
            break;
          case TargetPlatform.macOS:
            await _plugin
                .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(
                  alert: true,
                  badge: true,
                  sound: true,
                );
            break;
          case TargetPlatform.android:
            // Temporarily disabled due to platform issues; Android 13+ users must grant notification permission manually.
            // await _plugin
            //     .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            //     ?.requestPermission();
            break;
          default:
            break;
        }
      }

      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint('Permission request error: $e');
    }
  }

  static Future<void> _ensureTimezone() async {
    if (_timezoneReady) return;
    try {
      tz.initializeTimeZones();
      final name = await FlutterNativeTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
      _timezoneReady = true;
    } catch (e) {
      debugPrint('Timezone init error: $e');
      _timezoneReady = true;
    }
  }

  static Future<void> _scheduleSingle(
    Task task,
    tz.TZDateTime fireTime,
    DateTime originalStart, {
    required int salt,
  }) async {
    if (fireTime.isBefore(tz.TZDateTime.now(tz.local).add(const Duration(seconds: 1)))) {
      debugPrint('[PushNotifications] Skipping reminder for "${task.title}" '
          '(${_saltLabel(salt)}) because $fireTime is in the past.');
      return; // already in the past
    }

    final minutes = (originalStart.difference(fireTime.toLocal())).inMinutes;
    final phrase = minutes <= 1 ? '1 minute' : '$minutes minutes';
    final title = '${task.title} starts in $phrase';

    final notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _defaultChannel.id,
        _defaultChannel.name,
        channelDescription: _defaultChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        icon: '@mipmap/ic_launcher',
        playSound: true,
        enableVibration: true,
      ),
      iOS: const DarwinNotificationDetails(
        interruptionLevel: InterruptionLevel.timeSensitive,
        presentAlert: true,
        presentSound: true,
        presentBadge: false,
        presentBanner: true,
        presentList: true,
      ),
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: false,
        presentBanner: true,
        presentList: true,
      ),
    );

    final id = _notificationBase(task, originalStart) ^ salt;

    try {
      debugPrint('[PushNotifications] Requesting reminder (${_saltLabel(salt)}) '
          'for "${task.title}" @ ${fireTime.toLocal()} (id=$id)');
      await _plugin.zonedSchedule(
        id,
        title,
        'Tap to view the steps.',
        fireTime,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: _buildPayload(task, originalStart),
        matchDateTimeComponents: null,
      );
      debugPrint('[PushNotifications] Reminder scheduled (id=$id).');
    } catch (e) {
      debugPrint('[PushNotifications] zonedSchedule error for "${task.title}" '
          '(${_saltLabel(salt)}): $e');
    }
  }

  static void _mirrorRemoteMessage(RemoteMessage message) {
    final notif = message.notification;
    if (notif == null) return;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _defaultChannel.id,
        _defaultChannel.name,
        channelDescription: _defaultChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: notif.android?.smallIcon ?? '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: false,
      ),
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: false,
      ),
    );

    _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      notif.title ?? 'Notification',
      notif.body ?? '',
      details,
    );
  }

  static int _notificationBase(Task task, DateTime startLocal) {
    final key = '${task.title}|${task.startTime}|${task.period}|${startLocal.toIso8601String()}';
    return key.hashCode & 0x7fffffff;
  }

  static String _buildPayload(Task task, DateTime startLocal) {
    final map = <String, dynamic>{
      'title': task.title,
      'startTime': task.startTime,
      'period': task.period,
      'familyTag': task.familyTag,
      'startDate': startLocal.toIso8601String(),
    };
    return jsonEncode(map);
  }

  static String _saltLabel(int salt) {
    switch (salt) {
      case 0x5:
        return '-5 min';
      case 0x1:
        return '-1 min';
      default:
        return 'salt:$salt';
    }
  }
}
