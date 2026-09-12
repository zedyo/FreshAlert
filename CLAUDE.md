# CLAUDE.md

Project guidance for working effectively in this repository.

> **Open work:** see `docs/HANDOFF.md` for what is still open before the first
> App Store submission. Delete that file once everything in it is resolved.

## How work gets merged (AI-driven development)

The owner does not merge or push by hand. Agents work like this:

1. Branch from `main`, commit, push, open a pull request.
2. CI (`ci.yml`, job "Build & Test") must pass. Enable auto-merge on the PR:
   `gh pr merge --auto --squash <nr>`. GitHub merges when CI is green.
3. **`main` means TestFlight**, never App Store. `testflight.yml` builds and uploads
   on every merge (skipped with a notice while the signing secrets are missing).
4. **App Store submission only via a tag** `vX.Y.Z` (`store.yml`). The tag is set
   on the owner's explicit request. Release to the store stays manual in
   App Store Connect.
5. Never push to `main` directly, never force-push, never delete `main`.

## Project

**FreshAlert** — native iOS app for tracking food expiry dates. Barcode scanner,
Open Food Facts lookup, local notifications, home-screen widget. German UI.

- **Min iOS:** 17.0 · **Language:** Swift 5 · **UI:** SwiftUI · **Persistence:** SwiftData
- Bundle IDs: app `com.freshalert.app`, widget `com.freshalert.app.widget`
- App Group: `group.com.freshalert.app`

## Targets

| Target | Path | Notes |
|---|---|---|
| FreshAlert | `FreshAlert/` | Main app |
| FreshAlertWidget | `FreshAlertWidget/` | Widget extension (app-extension) |
| FreshAlertTests | `FreshAlertTests/` | XCTest unit tests |

`WidgetDataStore.swift` is compiled into **both** the app and widget targets
(shared App Group data layer).

## Architecture

- `FreshAlertApp` — `@main`, builds the SwiftData `ModelContainer`, owns `AppViewModel`.
- `AppDelegate` / `SceneDelegate` — wired via `UIApplicationDelegateAdaptor`.
  Home-screen quick actions arrive at the **scene delegate** only.
- `ContentView` — `TabView` (Übersicht / Scannen / Einstellungen).
- `AppViewModel` (`@MainActor`, `ObservableObject`) — all CRUD, network monitoring,
  widget snapshot writing, offline sync, notification scheduling.
- Models: `FoodItem`, `StorageLocation` (`@Model`).
- Services: `OpenFoodFactsService` (actor), `NotificationService` (`@MainActor`),
  `StoreManager` (`@MainActor`, StoreKit 2 — freemium gate, injected via env).
- Views split by feature folder under `FreshAlert/Views/`. `Paywall/PaywallView`
  appears once the free limit (`StoreManager.freeLimit = 20`) is reached.

## Conventions

- German user-facing strings.
- Brand green: `Color.freshGreen` (defined in `StorageLocation.swift` for the app,
  and privately in `FreshAlertWidget.swift` for the widget). Do not re-hardcode
  `Color(red: 0.2, green: 0.78, blue: 0.2)`.
- `expiryLabel` / `expiryStatus` logic lives on `FoodItem`; the widget has its own
  abbreviated `WidgetFoodItem.expiryLabel`.

## Project file gotchas

- `project.pbxproj` is hand-maintained. New files must be added in **all** of:
  `PBXBuildFile`, `PBXFileReference`, `PBXGroup`, `PBXSourcesBuildPhase`
  (resources such as `PrivacyInfo.xcprivacy` go into `PBXResourcesBuildPhase`).
  Hex ID prefixes: `D…` file refs, `E…` app build files, `T…` test, widget reuse.
  Highest IDs in use: `D…39`, `E…38`, `T…0B`. Continue from there.
- `FreshAlertTests` depends on the app target (`T…0A`); keep that dependency,
  otherwise `xcodebuild test` fails with "Unable to find module dependency".
- Both targets ship a `PrivacyInfo.xcprivacy` (UserDefaults, reasons CA92.1 and
  1C8F.1, no tracking). Add new Required-Reason APIs there, never delete it.
- Legal links live in `FreshAlert/Legal.swift` only. CI fails on `apple.com/privacy`.
- App Group is configured via tracked `.entitlements` files + `CODE_SIGN_ENTITLEMENTS`
  build settings — no manual Xcode capability setup needed.
- `.gitignore` covers `xcuserdata/`, `*.xcuserstate` etc. Never re-track them.

## Versioning

- `MARKETING_VERSION` (6× in `project.pbxproj`) is bumped **per pull request**, not per
  commit: x.0.0 major · x.y.0 feature · x.y.z bugfix. Add a `CHANGELOG.md` entry.
- `CURRENT_PROJECT_VERSION` is **not** edited by hand. Fastlane sets it to
  commit count + 100 on every upload (`VERSIONING_SYSTEM = apple-generic`).
- A store tag `vX.Y.Z` must match `MARKETING_VERSION`; the `release` lane sets
  the version from the tag as a safety net.

## Build & test

- Build/run: open `FreshAlert.xcodeproj` in Xcode, run the `FreshAlert` scheme.
- Tests: `⌘U`, or on the command line:
  `xcodebuild test -project FreshAlert.xcodeproj -scheme FreshAlert -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
  The test target is only built for the test action, not for a plain build.
- Unsigned device build (what CI does):
  `xcodebuild build -project FreshAlert.xcodeproj -scheme FreshAlert -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`.
- **Test data in the simulator:** the launch argument `-seedTestData` fills an
  *empty* database with the 50 products from `FreshAlert/TestData/testprodukte.json`
  (real Open Food Facts items with images, mixed expiry dates) and skips onboarding.
  Build for the simulator, install, then:
  `xcrun simctl launch "iPhone 17 Pro" com.freshalert.app -seedTestData`.
  Seeding only runs when there are no items and no locations; uninstall first
  (`xcrun simctl uninstall "iPhone 17 Pro" com.freshalert.app`) to start over.
- **Developer menu** (Einstellungen → Entwickler → Entwicklermenü): only in Debug
  builds, TestFlight (sandbox receipt / `AppTransaction.environment == .sandbox`)
  or with launch argument `-developerMenu`. Never in App Store builds. Offers seed,
  delete all items, full reset (back to onboarding) and the list of pending
  notifications (`AppEnvironment.swift`, `TestDataSeeder.swift`, `DeveloperMenuView.swift`).

## Release & deployment

- CI/CD via GitHub Actions + Fastlane. PR → build + tests (`ci.yml`);
  merge to `main` → TestFlight (`testflight.yml`, lane `beta`);
  tag `v*` → App Store review (`store.yml`, lane `release`, no automatic release).
- Secrets needed for the cloud lanes: `ASC_KEY_ID`, `ASC_ISSUER_ID`,
  `ASC_KEY_CONTENT` (base64 .p8), `MATCH_GIT_URL`, `MATCH_PASSWORD`,
  `MATCH_GIT_BASIC_AUTHORIZATION`. Without them the TestFlight job skips itself.
- Build machine fallback: the owner's iMac (Xcode 26.3, Intel). Same lanes locally.
- Docs: `docs/RELEASE_AUTOMATION.md` (pipeline + setup), `docs/APP_STORE.md`
  (manual store steps), `docs/MARKETING.md`, `docs/MONETIZATION.md`,
  `docs/PRIVACY_POLICY.md`.
