# PhotoSwipe

An iPhone app that does one thing well: rapid photo triage.

Enter **delete mode**, see one photo fullscreen at a time, and swipe:

| Gesture | Result |
|---|---|
| Swipe **right** | Keep |
| Swipe **left** | Queue for deletion |
| Swipe **up** | Queue for hiding (iOS's Face ID-locked Hidden album) |
| **Undo** button | Step back to the previous photo and decide again |

Nothing is destroyed while you swipe. When you're done, the **Review** screen shows
everything queued, lets you rescue anything with a tap, and commits all changes in one
batch. iOS asks you to confirm once for hides and once for deletes; deleted photos land
in Recently Deleted for 30 days.

Start from your newest photo by default, flip to oldest-first, or use **Choose where to
start…** to jump to any month or date. Sessions are saved after every swipe, so quitting
the app never loses your delete list; Home offers **Resume** on the next launch.

![Home](screenshots/01-home.png) ![Swipe](screenshots/02-swipe.png) ![Review](screenshots/04-review.png)

## Requirements

- Xcode 26 (builds against iOS 17.0+; no iOS 26-only APIs are used)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) only if you change `project.yml`
  (`brew install xcodegen`, then `xcodegen generate`). The generated `.xcodeproj` is committed.

## Project layout

```
PhotoSwipe/
  App/          PhotoSwipeApp (entry), AppModel (wires session ↔ PhotoKit ↔ disk)
  Models/       SwipeSession — pure, testable engine: cursor, direction, decision log, undo
  Services/     PhotoLibraryService (PhotoKit), AssetImageLoader, SessionStore (JSON)
  Views/        HomeView, StartPickerView, SwipeView, ReviewView, AssetImageView, Theme
PhotoSwipeTests/     unit tests for SwipeSession and SessionStore
PhotoSwipeUITests/   XCUITests that drive real swipes against the simulator library
```

`SwipeSession` never imports Photos. `PhotoLibraryService` maps the library to an array of
`localIdentifier`s (newest first) and the session walks that array; `direction` decides
whether the cursor moves +1 or -1. Hidden assets are excluded from the fetch, so a photo
you hide never resurfaces in triage.

## Build & test

```sh
# Build
xcodebuild -project PhotoSwipe.xcodeproj -scheme PhotoSwipe \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Unit tests (fast, no simulator library needed)
xcodebuild -project PhotoSwipe.xcodeproj -scheme PhotoSwipe \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PhotoSwipeTests test

# UI tests: real swipes, undo, review rescue, relaunch/resume, and one end-to-end
# commit that deletes 1 + hides 1 photo from the simulator library.
xcodebuild -project PhotoSwipe.xcodeproj -scheme PhotoSwipe \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PhotoSwipeUITests test
```

### Simulator notes

- The simulator ships with a handful of sample photos. To add more:
  `xcrun simctl addmedia booted path/to/*.png`
- `xcrun simctl privacy booted grant photos <bundle id>` does **not** grant PhotoKit
  read-write access on recent iOS simulators. The UI tests therefore tap the real
  "Allow Full Access" alert on first launch. To re-trigger it:
  `xcrun simctl privacy booted reset photos com.ryancwynar.PhotoSwipe`
- The commit test mutates the simulator library (that is the point). Re-seed with
  `addmedia` if it runs low.

## Running on a device

Open `PhotoSwipe.xcodeproj`, pick your iPhone, run. Signing is automatic with team
`ZFLMF363GG` (edit `project.yml` / the target's Signing tab for a different team).

## Not in v1

Inline video playback (videos show a poster frame with a duration badge), duplicate
detection, per-album filtering, and richer iCloud "not downloaded" placeholders.
