import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class LoanNotificationService {
  LoanNotificationService._();

  static const _channelId = 'loan_monthly_checkin';
  static const _channelName = 'Monthly Check-In';
  static const _channelDesc =
      'Monthly reminder to log your loan payment and track progress.';
  static const _notifId = 101;

  static final _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    try {
      tz_data.initializeTimeZones();

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      await _plugin.initialize(settings);

      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.defaultImportance,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    } catch (_) {
      // flutter_local_notifications v18 may throw on Android 14 — non-fatal.
    }
  }

  /// Schedules a recurring notification on the 5th of each month at 9:00 AM.
  static Future<void> scheduleMonthlyCheckin(bool isSpanish) async {
    try {
      await _doSchedule(isSpanish);
    } catch (_) {
      // Non-fatal — monthly reminder silently skipped if scheduling fails.
    }
  }

  static Future<void> _doSchedule(bool isSpanish) async {
    // zonedSchedule with the same _notifId replaces any existing notification,
    // so no explicit cancel() needed — avoids loadScheduledNotifications crash
    // on devices that have legacy notification data from older plugin versions.

    final title = isSpanish
        ? 'Registra tu progreso de deuda 📊'
        : 'Track your debt progress 📊';
    final body = isSpanish
        ? 'Anota el pago de este mes y mantén tu plan de pago.'
        : "Log this month's payment and stay on your payoff plan.";

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const details = NotificationDetails(android: androidDetails);

    // Find the next 5th of month at 09:00 AM in local time.
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      5,
      9,
    );
    if (scheduled.isBefore(now)) {
      // Already past the 5th of this month — schedule for next month.
      final next = now.month == 12
          ? tz.TZDateTime(tz.local, now.year + 1, 1, 5, 9)
          : tz.TZDateTime(tz.local, now.year, now.month + 1, 5, 9);
      scheduled = next;
    }

    await _plugin.zonedSchedule(
      _notifId,
      title,
      body,
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
    );
  }

  static Future<void> cancel() async {
    try {
      await _plugin.cancel(_notifId);
    } catch (_) {
      // Legacy notification format in SharedPreferences — ignore.
    }
  }
}
