import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../../features/daily_text/data/daily_text.dart';

/// Writes the daily text into the shared storage the native Android widget
/// reads from, then asks the OS to redraw it.
class HomeWidgetService {
  const HomeWidgetService._();

  static const _androidWidgetProviderName = 'DailyTextWidgetProvider';
  static const _iOSWidgetName = 'DailyTextWidget';
  static const _iOSAppGroupId = 'group.com.lespadev.jwdailytextwidget';

  /// Initializes App Group ID configuration for iOS widget support.
  static Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      await HomeWidget.setAppGroupId(_iOSAppGroupId);
    } catch (e) {
      debugPrint('HomeWidgetService: Failed to configure iOS App Group: $e');
    }
  }

  /// Persists [dailyText] to shared storage and triggers an Android and iOS widget refresh.
  /// Safely handles web or unsupported platforms.
  static Future<void> updateWidget(DailyText dailyText) async {
    if (kIsWeb) {
      // Home widgets are Android/iOS native features; skip on web platform
      return;
    }

    try {
      // Ensure App Group ID is set on iOS
      await HomeWidget.setAppGroupId(_iOSAppGroupId);

      for (final entry in dailyText.toWidgetData().entries) {
        await HomeWidget.saveWidgetData<String>(entry.key, entry.value);
      }

      // Save formatted dateTitle for widget header
      final dateDisplay = dailyText.dateTitle.isNotEmpty
          ? dailyText.dateTitle
          : DateFormat('EEEE, MMMM d').format(dailyText.date);
      await HomeWidget.saveWidgetData<String>('dateTitle', dateDisplay);

      await HomeWidget.updateWidget(
        androidName: _androidWidgetProviderName,
        iOSName: _iOSWidgetName,
      );
      debugPrint('HomeWidgetService: Successfully updated home screen widget');
    } catch (e) {
      debugPrint('HomeWidgetService: Failed to update native widget: $e');
    }
  }
}
