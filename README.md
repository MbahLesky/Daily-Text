# JW Daily Text Widget

A Flutter app that fetches the JW daily text and shows it on an Android
home-screen widget.

The Flutter/Android/iOS/web scaffolding (`flutter create .`, org
`com.lespadev`) has been generated and merged with the hand-written source
(Dart app code, the Kotlin widget provider/tap handler, layout/manifest
fragments, an iOS WidgetKit stub). See `docs/IMPLEMENTATION_PLAN.md` for the
full spec.

## Working locally

1. `flutter pub get`.
2. `flutter test` to run `test/features/daily_text/data/daily_text_test.dart`.
3. `flutter run -d chrome` (or a small script) to confirm a real fetch for
   today's date parses cleanly — spot-check against wol.jw.org.
4. `flutter run` on a real Android device/emulator, add the widget to the
   home screen, and work through the manual checklist in
   `docs/IMPLEMENTATION_PLAN.md` Section 6 (fresh install placeholder,
   airplane-mode caching, tap with/without JW Library installed,
   force-stop + background refresh via `adb shell cmd jobscheduler run`,
   widget resize).
5. When resuming iOS work (Phase 2): re-add an iOS-aware `configure()`/App
   Group call to `HomeWidgetService`, and wire the App Group
   `group.com.lespadev.jwdailytextwidget` on both the Runner app target and
   the `ios/DailyTextWidget` extension target in Xcode — the existing
   Swift stub already expects that exact App Group id.

If you regenerate scaffolding with `flutter create .` again, pass
`--org com.lespadev` — it must keep matching the Kotlin package
(`com.lespadev.jwdailytextwidget`), the `namespace`/`applicationId` in
`android/app/build.gradle.kts`, and the iOS App Group id, or the
hand-written native files stop lining up with what gets generated.
`flutter create .` won't overwrite existing files, so re-running it is
always safe.
