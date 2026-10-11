import 'package:flutter_test/flutter_test.dart';
import 'package:jw_daily_text_widget/core/notifications/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    tz.initializeTimeZones();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('NotificationService settings & persistence', () {
    test('isReminderEnabled defaults to true', () async {
      final service = NotificationService.instance;
      final enabled = await service.isReminderEnabled();
      expect(enabled, isTrue);
    });

    test('getReminderTime defaults to 07:00 AM', () async {
      final service = NotificationService.instance;
      final time = await service.getReminderTime();
      expect(time.hour, 7);
      expect(time.minute, 0);
    });

    test('updateReminderSettings persists new enabled and custom time values', () async {
      final service = NotificationService.instance;

      await service.updateReminderSettings(
        enabled: false,
        hour: 8,
        minute: 45,
      );

      final enabled = await service.isReminderEnabled();
      final time = await service.getReminderTime();

      expect(enabled, isFalse);
      expect(time.hour, 8);
      expect(time.minute, 45);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('notification_reminder_enabled'), isFalse);
      expect(prefs.getInt('notification_reminder_hour'), 8);
      expect(prefs.getInt('notification_reminder_minute'), 45);
    });
  });

  group('NotificationService scheduling logic', () {
    test('nextInstanceOfTime schedules for today if target time is in the future', () {
      final service = NotificationService.instance;

      // Base time: 06:00 AM
      final base = tz.TZDateTime(tz.local, 2026, 10, 11, 6, 0);
      final nextInstance = service.nextInstanceOfTime(8, 30, base);

      expect(nextInstance.year, 2026);
      expect(nextInstance.month, 10);
      expect(nextInstance.day, 11); // Same day
      expect(nextInstance.hour, 8);
      expect(nextInstance.minute, 30);
    });

    test('nextInstanceOfTime schedules for tomorrow if target time has already passed today', () {
      final service = NotificationService.instance;

      // Base time: 09:00 AM
      final base = tz.TZDateTime(tz.local, 2026, 10, 11, 9, 0);
      // Target time: 07:00 AM (already passed today)
      final nextInstance = service.nextInstanceOfTime(7, 0, base);

      expect(nextInstance.year, 2026);
      expect(nextInstance.month, 10);
      expect(nextInstance.day, 12); // Next day
      expect(nextInstance.hour, 7);
      expect(nextInstance.minute, 0);
    });

    test('nextInstanceOfTime schedules for tomorrow if target time equals base time', () {
      final service = NotificationService.instance;

      // Base time: 07:00:30 AM
      final base = tz.TZDateTime(tz.local, 2026, 10, 11, 7, 0, 30);
      final nextInstance = service.nextInstanceOfTime(7, 0, base);

      expect(nextInstance.day, 12); // Next day
      expect(nextInstance.hour, 7);
      expect(nextInstance.minute, 0);
    });

    test('onNotificationClick callback receives notification payloads', () {
      final service = NotificationService.instance;
      String? receivedPayload;

      service.onNotificationClick = (payload) {
        receivedPayload = payload;
      };

      service.onNotificationClick?.call('test_payload_123');
      expect(receivedPayload, 'test_payload_123');
    });
  });
}
