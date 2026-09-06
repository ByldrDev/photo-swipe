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
`B89YM4B72X` (edit `project.yml` / the target's Signing tab for a different team).

## Not in v1

Inline video playback (videos show a poster frame with a duration badge), duplicate
detection, per-album filtering, and richer iCloud "not downloaded" placeholders.

## TestFlight

`scripts/testflight.sh` archives a Release build and uploads it to App Store Connect:

```sh
ASC_KEY_ID=2M8HBZGHA8 ASC_ISSUER_ID=7a62ff2d-f404-42b0-b11b-2a475a0c4ad3 scripts/testflight.sh
```

Auth: an App Store Connect API key (Team key, App Manager role) read from
`~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`; without `ASC_KEY_ID` the script falls
back to the Apple ID signed in to Xcode. The build number defaults to a UTC timestamp so
uploads never collide. `ITSAppUsesNonExemptEncryption` is false, so builds skip the
export-compliance prompt.

**Signing is manual for the upload step.** Xcode 26's automatic distribution signing asks
Apple for a cloud-managed certificate (`DISTRIBUTION_MANAGED`), which this team's portal
rejects with a 403. So the export uses a classic **Apple Distribution** certificate in the
login keychain plus the **"PhotoSwipe App Store"** provisioning profile, both created by hand
in Certificates, Identifiers & Profiles (CSR via `openssl req`, upload, download `.cer`,
build a `.p12` with the key, `security import`; then an App Store profile for the bundle ID,
downloaded into `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`). Both expire
2027-09-06. `scripts/ExportOptions.plist` names them. The archive step still uses automatic
(development) signing, which works fine.

App Store Connect record: "PhotoSwipe: Keep or Delete" (app id 6809222601; "PhotoSwipe" and
"Photo Swipe" were taken). The name can be changed under App Information before release.
