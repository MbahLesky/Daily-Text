# JW Daily Text Widget

A Flutter app that fetches the JW daily text and shows it on an Android
home-screen widget.

This repo currently holds hand-written source only (Dart app code, the
Kotlin widget provider/tap handler, layout/manifest fragments, an iOS
WidgetKit stub) — the Flutter/Android build tooling (Gradle wrapper, full
`AndroidManifest.xml`, Xcode project) hasn't been generated yet because no
Flutter SDK was available when this was written. See
`docs/IMPLEMENTATION_PLAN.md` for the full spec.

## Bootstrapping locally

Run these once you have the Flutter SDK installed:

1. `flutter create . --platforms=android --org com.lespadev` — the org must
   match the existing Kotlin package (`com.lespadev.jwdailytextwidget`), the
   `namespace`/`applicationId` in `android/app/build.gradle.kts`, and the iOS
   App Group id, or the hand-written native files won't line up with what
   gets generated. Scoping to `--platforms=android` avoids generating
   `ios/Runner`/Xcode project files until Phase 2 iOS work starts.
   `flutter create .` won't overwrite existing files (`pubspec.yaml`,
   `lib/main.dart`, the Kotlin/XML files) — it only fills in what's
   missing.
2. Merge `android/app/src/main/AndroidManifest_widget_snippet.xml` into the
   generated `AndroidManifest.xml`: the `<queries>` block as a sibling of
   `<application>`, and the `<receiver>` inside `<application>`. Then
   delete the snippet file.
3. In `android/app/build.gradle`, set `minSdkVersion` to at least `23` —
   required for `PendingIntent.FLAG_IMMUTABLE` used in
   `WidgetTapHandler.kt`.
4. `flutter pub get`.
5. `flutter test` to run `test/features/daily_text/data/daily_text_test.dart`.
6. `flutter run -d chrome` (or a small script) to confirm a real fetch for
   today's date parses cleanly — spot-check against wol.jw.org.
7. `flutter run` on a real Android device/emulator, add the widget to the
   home screen, and work through the manual checklist in
   `docs/IMPLEMENTATION_PLAN.md` Section 6 (fresh install placeholder,
   airplane-mode caching, tap with/without JW Library installed,
   force-stop + background refresh via `adb shell cmd jobscheduler run`,
   widget resize).
8. When resuming iOS work (Phase 2): re-add an iOS-aware `configure()`/App
   Group call to `HomeWidgetService`, and wire the App Group
   `group.com.lespadev.jwdailytextwidget` on both the Runner app target and
   the `ios/DailyTextWidget` extension target in Xcode — the existing
   Swift stub already expects that exact App Group id.
