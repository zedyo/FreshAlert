# CLAUDE.md

Project guidance for working effectively in this repository.

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
  `PBXBuildFile`, `PBXFileReference`, `PBXGroup`, `PBXSourcesBuildPhase`.
  Hex ID prefixes: `D…` file refs, `E…` app build files, `T…` test, widget reuse.
- App Group is configured via tracked `.entitlements` files + `CODE_SIGN_ENTITLEMENTS`
  build settings — no manual Xcode capability setup needed.
- `.gitignore` covers `xcuserdata/`, `*.xcuserstate` etc. Never re-track them.

## Versioning

Every commit bumps the version. `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION`
appear 6×/6× in `project.pbxproj` (Settings reads them from the bundle).
Semantic: x.0.0 major · x.y.0 feature · x.y.z bugfix. Add a `CHANGELOG.md` entry.

## Build & test

- Build/run: open `FreshAlert.xcodeproj` in Xcode, run the `FreshAlert` scheme.
- Tests: `⌘U` (scheme `FreshAlert` includes `FreshAlertTests` in its TestAction).
  The test target is built on every build, so test code that stops compiling
  fails the build immediately.

## Release & deployment

- CI/CD via GitHub Actions + Fastlane. PR → tests (`ci.yml`); merge to `main` →
  TestFlight upload **and** App Store submission (`release.yml`, lane `release`).
  A merge to `main` is a full App Store release — there is no tag step.
  CI sets the build number from the commit count.
- Docs: `docs/RELEASE_AUTOMATION.md` (pipeline + setup), `docs/APP_STORE.md`
  (manual store steps), `docs/MARKETING.md`, `docs/MONETIZATION.md`,
  `docs/PRIVACY_POLICY.md`.
