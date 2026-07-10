import 'package:home_widget/home_widget.dart';

import '../../features/daily_text/data/daily_text.dart';

/// Writes the daily text into the shared storage the native Android widget
/// reads from, then asks the OS to redraw it.
///
/// Android-only for this MVP pass. iOS App Group wiring returns in a later
/// phase (see docs/IMPLEMENTATION_PLAN.md, Section 7) alongside the
/// ios/DailyTextWidget WidgetKit stub, which already expects the App Group
/// id `group.com.example.jwDailyTextWidget`.
class HomeWidgetService {
  const HomeWidgetService._();

  static const _androidWidgetProviderName = 'DailyTextWidgetProvider';

  /// Persists [dailyText] to shared storage and triggers a widget refresh.
  static Future<void> updateWidget(DailyText dailyText) async {
    for (final entry in dailyText.toWidgetData().entries) {
      await HomeWidget.saveWidgetData<String>(entry.key, entry.value);
    }
    await HomeWidget.updateWidget(androidName: _androidWidgetProviderName);
  }
}
