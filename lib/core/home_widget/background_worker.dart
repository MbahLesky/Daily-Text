import 'package:workmanager/workmanager.dart';

import '../../features/daily_text/data/daily_text_service.dart';
import 'home_widget_service.dart';

/// Identifier for the periodic background refresh task.
const dailyTextRefreshTask = 'dailyTextRefreshTask';

/// Entry point Workmanager invokes in a background isolate. Must stay a
/// top-level function annotated with `vm:entry-point` or Android will fail
/// to find it after the app is killed.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != dailyTextRefreshTask) return true;

    try {
      final dailyText = await const DailyTextService().fetchDailyText();
      await HomeWidgetService.updateWidget(dailyText);
      return true;
    } catch (_) {
      // Let Workmanager's built-in retry/backoff policy handle it.
      return false;
    }
  });
}
