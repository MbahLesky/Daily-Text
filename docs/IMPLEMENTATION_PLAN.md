# JW Daily Text Widget — Implementation Plan (Android MVP)

This document is the handoff spec for implementation. Follow it top to bottom;
each task lists its acceptance criteria. Scaffold files referenced below
already exist in this repo under `lib/`, `android/`, and `pubspec.yaml` —
treat them as a starting draft, not final code; adjust as needed while
implementing.

## 0. Repo setup

1. `git init` in the project root (if not already a repo).
2. Add a Flutter-appropriate `.gitignore` (standard `flutter create` one:
   `.dart_tool/`, `build/`, `.flutter-plugin-dependencies`, `*.iml`,
   `.idea/`, local `.env` files, etc.). Do not commit `android/local.properties`
   or keystore files.
3. Run `flutter create .` in the project root to generate the missing
   platform scaffolding (`android/`, standard Gradle files, etc.) — merge it
   with the existing hand-written files in this repo rather than overwriting
   them (`DailyTextWidgetProvider.kt`, the widget layout/xml, `pubspec.yaml`).
4. `flutter pub get`.
5. Create the GitHub repo (name suggestion: `jw-daily-text-widget`), push the
   initial commit. Suggested repo description: "Android app + home screen
   widget showing the JW daily text." Make it public unless told otherwise.
6. First commit message: `chore: scaffold Flutter project with daily text widget plan`.

## 1. Data layer

**Files:** `lib/features/daily_text/data/daily_text.dart`,
`lib/features/daily_text/data/daily_text_service.dart`

- Endpoint: `https://wol.jw.org/wol/dt/r{rsconf}/lp-{locale}/{year}/{month}/{day}`
  (unofficial, undocumented; used by wol.jw.org itself). Defaults:
  `rsconf=1`, `locale=e` (English).
- Response is JSON with an `items` array; `items[0].content` is an HTML
  fragment. First `<p>` is the scripture, remaining `<p>` tags are the
  comment (join with `\n\n` if there are multiple).
- `DailyText` model fields: `scripture`, `comment`, `date`. Add a `jwpubUri`
  and `webUri` getter/field (see Section 3) so the widget tap handler
  doesn't need to reconstruct the URL scheme itself.
- `DailyTextService.fetchDailyText({DateTime? date})`: retries transient
  failures (network/5xx) with linear backoff, throws `DailyTextException`
  on final failure. Existing scaffold code covers this — verify and adjust
  timeout/retry counts as needed.

**Acceptance criteria**
- Unit tests cover: single-paragraph content, multi-paragraph comment,
  malformed/empty content (throws `FormatException` or similar, not a crash).
- A manual `flutter run -d chrome` or command-line script confirms a real
  fetch for today's date parses cleanly (spot-check against wol.jw.org).

## 2. Home widget bridge (Dart side)

**Files:** `lib/core/home_widget/home_widget_service.dart`,
`lib/core/home_widget/background_worker.dart`

- `HomeWidgetService.updateWidget(DailyText)` writes `scripture`, `comment`,
  `date`, and the two URIs from Section 3 into shared storage via
  `home_widget`'s `saveWidgetData`, then calls `HomeWidget.updateWidget(androidName: 'DailyTextWidgetProvider')`.
- Drop the iOS-specific `configure()` / App Group call from scaffold — not
  needed for Android-only scope. Remove `iOSName` param from the
  `updateWidget` call.
- `background_worker.dart`: Workmanager periodic task, `frequency: Duration(hours: 12)`,
  network-connected constraint. Keep the `callbackDispatcher` as a
  top-level `@pragma('vm:entry-point')` function — this is required by
  Workmanager on Android or the callback won't survive app kill.

**Acceptance criteria**
- After `flutter run`, killing the app, and waiting (or manually invoking
  the task via `adb shell cmd jobscheduler run`), the widget's cached data
  updates without the app being reopened.

## 3. Tap-to-open with fallback (the key native piece)

This is Android-native, not Dart, since the tap needs to resolve before the
Flutter engine is involved.

**Files:** `android/app/src/main/kotlin/.../DailyTextWidgetProvider.kt`,
new file `android/app/src/main/kotlin/.../WidgetTapHandler.kt` (or inline in
the provider — extract if it grows past ~40 lines per the project's
function-size convention).

- Deep link format: `jwpub://dt/r{rsconf}/lp-{locale}/{year}/{month}/{day}`
  (e.g. `jwpub://dt/r1/lp-e/2026/7/10`).
- Web fallback: `https://wol.jw.org/en/wol/dt/r{rsconf}/lp-{locale}/{year}/{month}/{day}`.
- In `onUpdate`, after populating the text views, build a `PendingIntent`:
  1. Construct an explicit `Intent(Intent.ACTION_VIEW, Uri.parse(jwpubUri))`.
  2. Use `context.packageManager.queryIntentActivities(intent, 0)` to check
     if anything resolves it (JW Library registers this scheme).
  3. If non-empty → use that intent as-is.
  4. If empty → build `Intent(Intent.ACTION_VIEW, Uri.parse(webUri))` instead
     (any browser resolves `https://`, so no further check needed).
  5. Wrap in `PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE)`.
  6. `views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)` — add
     an `android:id="@+id/widget_root"` to the outer `LinearLayout` in
     `daily_text_widget.xml` (currently missing an id; add it).
- The year/month/day used to build these URIs must come from the cached
  `date` field (an ISO string), not `DateTime.now()` at tap time — the
  widget should open the day it's currently displaying, even if stale.

**Acceptance criteria**
- With JW Library installed: tapping the widget opens JW Library directly
  to that day's text (verify the app actually navigates to the right date,
  not just launches to its home screen).
- With JW Library uninstalled (test on an emulator/device without it):
  tapping the widget opens the default browser to the matching wol.jw.org
  page.
- Works after a phone reboot (widget re-added) and after force-stopping
  the JW Daily Text Widget app itself (PendingIntent must not go stale).

## 4. Android manifest & resources

- Merge `android/app/src/main/AndroidManifest_widget_snippet.xml` into the
  real `AndroidManifest.xml` (inside `<application>`), then delete the
  snippet file.
- Confirm `daily_text_widget_info.xml`'s `minWidth`/`minHeight` render
  sensibly on a 4x2 grid cell on at least one real launcher (Pixel launcher
  is a reasonable baseline).
- Add `android:id="@+id/widget_root"` to the root `LinearLayout` in
  `daily_text_widget.xml` per Section 3.

## 5. App screen (lower priority, already scaffolded)

`lib/main.dart` is functional as-is for Android. Remove the
`HomeWidgetService.configure()` call and its import if it was iOS-only per
Section 2. Otherwise no changes required for MVP — verify it builds and
the pull-to-refresh path also updates the widget (already wired via
`_loadAndPublish`).

## 6. Testing checklist (manual, pre-merge)

- [ ] Fresh install, no cache: widget shows a sensible placeholder, not a
      crash or blank white view.
- [ ] Airplane mode after first successful fetch: widget still shows
      yesterday's/last-cached text.
- [ ] Tap-to-open, JW Library installed.
- [ ] Tap-to-open, JW Library not installed → browser fallback.
- [ ] Force-stop app, background task still refreshes widget within its
      scheduled window.
- [ ] Widget resize (drag smaller/larger) doesn't clip text unreadably.

## 7. Out of scope for this pass (do not implement)

iOS WidgetKit target, App Group sync, language selection, multi-day
history, lock-screen widgets. These are Phase 2/3 per the architecture
plan — leave stubs alone rather than half-implementing.
