import WidgetKit
import SwiftUI

struct DailyTextEntry: TimelineEntry {
    let date: Date
    let scripture: String
    let comment: String
}

struct DailyTextProvider: TimelineProvider {
    // Must match HomeWidgetService._iOSAppGroupId on the Dart side and the
    // App Group capability added to both the app and widget targets in Xcode.
    let appGroupId = "group.com.lespadev.jwdailytextwidget"

    func placeholder(in context: Context) -> DailyTextEntry {
        DailyTextEntry(date: Date(), scripture: "Loading…", comment: "")
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyTextEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyTextEntry>) -> Void) {
        let entry = currentEntry()
        // The app itself pushes fresh data whenever it fetches; this is
        // just a fallback so the widget still checks periodically.
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 6, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func currentEntry() -> DailyTextEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        return DailyTextEntry(
            date: Date(),
            scripture: defaults?.string(forKey: "scripture") ?? "No text available",
            comment: defaults?.string(forKey: "comment") ?? ""
        )
    }
}

struct DailyTextWidgetView: View {
    var entry: DailyTextEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.scripture)
                .font(.system(size: 14, weight: .semibold))
                .italic()
                .foregroundColor(.white)
            Text(entry.comment)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(6)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.29, green: 0.43, blue: 0.65))
    }
}

struct DailyTextWidget: Widget {
    let kind = "DailyTextWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyTextProvider()) { entry in
            DailyTextWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Text")
        .description("Today's JW daily text.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
