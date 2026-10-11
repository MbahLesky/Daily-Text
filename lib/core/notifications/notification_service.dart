import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Service that handles scheduled local notifications using [FlutterLocalNotificationsPlugin].
/// Reminds the user to read Examining the Scriptures Daily at a customizable time each day.
class NotificationService {
  static final NotificationService instance = NotificationService._internal();

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  ValueChanged<String?>? onNotificationClick;

  static const int reminderNotificationId = 1001;
  static const int testNotificationId = 1002;

  static const String channelId = 'daily_text_reminders';
  static const String channelName = 'Daily Scripture Reminder';
  static const String channelDescription =
      'Reminds you to read Examining the Scriptures Daily each morning';

  static const String _prefEnabledKey = 'notification_reminder_enabled';
  static const String _prefHourKey = 'notification_reminder_hour';
  static const String _prefMinuteKey = 'notification_reminder_minute';

  /// Initializes the local notification plugin and timezone database.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // 1. Initialize timezone database for zoned scheduling
      tz.initializeTimeZones();

      // 2. Initialize settings for supported platforms
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const linuxSettings = LinuxInitializationSettings(
        defaultActionName: 'Open JW Daily Text',
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: linuxSettings,
      );

      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) {
          debugPrint('Notification clicked: ${response.payload}');
          onNotificationClick?.call(response.payload);
        },
      );

      // 3. Create Android notification channel
      if (!kIsWeb) {
        final androidImpl = _notificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();

        if (androidImpl != null) {
          const channel = AndroidNotificationChannel(
            channelId,
            channelName,
            description: channelDescription,
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          );
          await androidImpl.createNotificationChannel(channel);
        }
      }

      _initialized = true;

      // 4. Restore scheduled reminder if previously enabled
      final isEnabled = await isReminderEnabled();
      if (isEnabled) {
        final time = await getReminderTime();
        await scheduleDailyReminder(hour: time.hour, minute: time.minute);
      }
    } catch (e) {
      debugPrint('NotificationService initialization error: $e');
    }
  }

  /// Requests runtime notification permission on Android 13+ / iOS.
  Future<bool> requestPermission() async {
    try {
      if (kIsWeb) return true;

      final androidImpl = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        final granted = await androidImpl.requestNotificationsPermission();
        return granted ?? false;
      }

      final iosImpl = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      if (iosImpl != null) {
        final granted = await iosImpl.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }
    } catch (e) {
      debugPrint('Error requesting notification permission: $e');
    }
    return true;
  }

  /// Checks if the daily reminder is currently enabled in settings.
  Future<bool> isReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabledKey) ?? true; // Enabled by default
  }

  /// Reads the configured reminder time from persistent storage.
  /// Defaults to 07:00 AM.
  Future<TimeOfDay> getReminderTime() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt(_prefHourKey) ?? 7;
    final minute = prefs.getInt(_prefMinuteKey) ?? 0;
    return TimeOfDay(hour: hour, minute: minute);
  }

  /// Updates and persists the reminder preferences, scheduling or cancelling accordingly.
  Future<void> updateReminderSettings({
    required bool enabled,
    required int hour,
    required int minute,
    String? title,
    String? body,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabledKey, enabled);
    await prefs.setInt(_prefHourKey, hour);
    await prefs.setInt(_prefMinuteKey, minute);

    if (enabled) {
      await requestPermission();
      await scheduleDailyReminder(
        hour: hour,
        minute: minute,
        title: title,
        body: body,
      );
    } else {
      await cancelReminder();
    }
  }

  /// Calculates the next daily instance of the specified [hour] and [minute].
  /// If the time has already passed today relative to [baseTime], schedules for tomorrow.
  tz.TZDateTime nextInstanceOfTime(int hour, int minute, [tz.TZDateTime? baseTime]) {
    final now = baseTime ?? tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  /// Schedules a recurring daily notification at the specified [hour] and [minute].
  Future<void> scheduleDailyReminder({
    required int hour,
    required int minute,
    String? title,
    String? body,
  }) async {
    try {
      if (!_initialized) await initialize();

      // Cancel existing reminder first to prevent duplicates
      await cancelReminder();

      final scheduledDate = nextInstanceOfTime(hour, minute);
      final notificationDetails = _buildNotificationDetails(
        bigText: body ?? "Start your day with today's scripture and comment!",
        summaryText: "Daily Scripture Reminder",
      );

      final notifTitle = title ?? 'JW Daily Text';
      final notifBody = body ?? "Start your day with today's scripture and comment!";

      try {
        await _notificationsPlugin.zonedSchedule(
          id: reminderNotificationId,
          title: notifTitle,
          body: notifBody,
          scheduledDate: scheduledDate,
          notificationDetails: notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time, // Repeats daily at specified time
        );
      } catch (exactAlarmErr) {
        debugPrint('Exact alarm disallowed ($exactAlarmErr), falling back to inexact schedule');
        await _notificationsPlugin.zonedSchedule(
          id: reminderNotificationId,
          title: notifTitle,
          body: notifBody,
          scheduledDate: scheduledDate,
          notificationDetails: notificationDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }

      debugPrint(
        'Daily reminder scheduled for ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
      );
    } catch (e) {
      debugPrint('Error scheduling daily reminder: $e');
    }
  }

  /// Cancels the scheduled daily reminder notification.
  Future<void> cancelReminder() async {
    try {
      if (!_initialized) return;
      await _notificationsPlugin.cancel(id: reminderNotificationId);
    } catch (e) {
      debugPrint('Error cancelling reminder: $e');
    }
  }

  /// Fires an immediate test notification so users can verify notification alerts.
  Future<void> showTestNotification({String? scripture}) async {
    try {
      if (!_initialized) await initialize();
      await requestPermission();

      final details = _buildNotificationDetails(
        bigText: scripture,
        summaryText: "Today's Scripture",
      );

      await _notificationsPlugin.show(
        id: testNotificationId,
        title: 'JW Daily Text Reminder',
        body: scripture != null && scripture.isNotEmpty
            ? scripture
            : "Today's scripture is ready. Tap to read!",
        notificationDetails: details,
        payload: 'daily_text_reminder',
      );
    } catch (e) {
      debugPrint('Error showing test notification: $e');
    }
  }

  NotificationDetails _buildNotificationDetails({String? bigText, String? summaryText}) {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF2C4D75),
      styleInformation: bigText != null && bigText.isNotEmpty
          ? BigTextStyleInformation(
              bigText,
              contentTitle: 'JW Daily Text Reminder',
              summaryText: summaryText ?? 'Daily Scripture',
            )
          : const BigTextStyleInformation(''),
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    return NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );
  }
}
