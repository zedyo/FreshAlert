# CLAUDE.md

Project guidance for working effectively in this repository.

> **Open work:** see `docs/HANDOFF.md` for the current session handoff — what was
> done last and which tasks are still open. Delete that file once everything in
> it is resolved.

## AI-Arbeitsworkflow (verbindlich)

Diese Cloud-Umgebung kann **kein Swift kompilieren** (kein Xcode, kein macOS).
Die einzige Verifikation, dass eine Änderung baut und die Tests grün sind, ist
der GitHub-Actions-Check **„Build & Test"** auf einem Pull Request.

**Pflicht-Loop für jede Code-Änderung:**

1. **Feature-Branch** (nie direkt auf `main`).
2. Änderung committen + pushen.
3. **Pull Request** öffnen (Draft genügt).
4. CI-Status verfolgen — auf das eigene PR per `mcp__github__subscribe_pr_activity`
   oder ggf. polling via `gh pr checks`. **Webhooks liefern nur Failures**, kein
   Success — bei Bedarf einen `Monitor` (oder `send_later`) auf Termination
   einrichten.
5. Bei **rotem CI**: Fehler lesen, fix-forward committen, push, erneut warten.
6. **Niemals** zum Mergen drücken — der Owner mergt.

**`main` ist heilig:** jeder Push auf `main` löst über `release.yml` automatisch
einen TestFlight-Upload **und** eine App-Store-Einreichung aus. Vor jedem Merge
nach `main` müssen erfüllt sein:

- CI grün
- `CHANGELOG.md`-Eintrag für jede Version
- `fastlane/metadata/de-DE/release_notes.txt` für nutzersichtbare Änderungen
  (deutsche Endnutzersprache)
- `MARKETING_VERSION` bei nutzersichtbaren Änderungen erhöht
- In App Store Connect angelegt + an den Build angehängt: beide IAPs
  (`com.freshalert.pro.yearly`, `com.freshalert.pro.lifetime`) und der
  „Paid Applications"-Vertrag aktiv (sonst leere Paywall — siehe
  `docs/MONETIZATION.md` §6)
- Datenschutz-URL in `PaywallView.swift` ist real (kein `TODO`)
- Privacy-Manifest abdeckt alle genutzten Required-Reason-APIs (aktuell:
  `NSPrivacyAccessedAPICategoryUserDefaults`, CA92.1 + 1C8F.1). Bei Hinzufügen
  von z. B. Datei-Timestamps, Disk-Space oder Boot-Zeit-APIs erweitern.

## Definition of Done

Vor PR-Abschluss / Merge-Anfrage:

- [ ] CI „Build & Test" grün auf dem PR
- [ ] Tests für neue Logik (testbare Funktionen pure halten, siehe
      `OrphanedNotificationParser` als Muster)
- [ ] `CHANGELOG.md` aktualisiert
- [ ] `fastlane/metadata/de-DE/release_notes.txt` aktualisiert (bei
      Nutzersicht­barkeit)
- [ ] `MARKETING_VERSION` gebumpt (`x.y.z` für Bugfix, `x.y.0` für Feature,
      `x.0.0` für Major) — **6× in `project.pbxproj`**
- [ ] Privacy-Manifest geprüft (neue Required-Reason-API genutzt?)
- [ ] `/code-review` und `/security-review` einmal über den Diff gelaufen
- [ ] Auf `main`-Merge-Konsequenzen geprüft (siehe oben)

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
- **Lokalisierungs-Vorbereitung** (EN folgt später, eigenes PR): UI-Strings als
  Literal in `Text("…")` belassen (SwiftUI's String-Catalog kann sie automatisch
  extrahieren). Nicht-View-Strings — insbesondere `NotificationService`-Titel
  und ‑Bodies — über `String(localized: "…")` formulieren. Keine deutschen
  Strings in Identifier, Logik-Keys oder Compile-Zeit-Konstanten. Damit ist der
  spätere EN-PR rein additiv.
- **Persistenz**: nie `try? modelContext.save()`. Stattdessen
  `viewModel.saveContext("Kontext-Bezeichner")` (oder das Äquivalent), damit
  Save-Fehler über `os.Logger` (`subsystem: com.freshalert.app`) landen und
  als Toast sichtbar werden. Stille Fehler waren die Hauptursache des
  Datenverlust-Bugs in v1.5.

## Project file gotchas

- `project.pbxproj` is hand-maintained. New **source** files must be added in
  **all** of: `PBXBuildFile`, `PBXFileReference`, `PBXGroup`,
  `PBXSourcesBuildPhase`. New **resource** files (e. g. `PrivacyInfo.xcprivacy`)
  go into `PBXResourcesBuildPhase` instead of `PBXSourcesBuildPhase`.
- Hex ID prefixes & ranges (Stand 1.7.7, beim Erweitern fortfahren):
  - `A…` PBXGroups (App + Subgruppen, Widget, Tests).
  - `B…` Projekt / NativeTargets (`B…02` App, `B…03` Widget, `B…04` Tests).
  - `C…` BuildPhases. `C…03` = App-Resources, `C…06` = Widget-Resources.
  - `D…` FileReferences, **nächste freie: `D…28`**.
  - `E…` BuildFiles für App + Widget, **nächste freie: `E…2C`**.
  - `F…` Build-Configurations.
  - `T…` Test-Target-spezifisch (BuildFiles + Configs), **nächste freie BuildFile: `T…0C`**.
- Bei jeder neuen Datei **vier Dinge**: FileRef, BuildFile (oder Resource), Group-Eintrag,
  Build-Phase-Eintrag. Beide Targets prüfen, wenn die Datei in beide gehört
  (z. B. `WidgetDataStore.swift`).
- App Group is configured via tracked `.entitlements` files + `CODE_SIGN_ENTITLEMENTS`
  build settings — no manual Xcode capability setup needed.
- `.gitignore` covers `xcuserdata/`, `*.xcuserstate` etc. Never re-track them.
- CI nutzt den Simulator `iPhone 16` (Fastfile-Lane `test`). Bei Xcode-Updates
  prüfen, ob dieser Simulator-Name auf dem Runner-Image (`macos-15`) existiert.

## Versioning

Every commit bumps the version. `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION`
appear 6×/6× in `project.pbxproj` (Settings reads them from the bundle).
Semantic: x.0.0 major · x.y.0 feature · x.y.z bugfix. Add a `CHANGELOG.md` entry.

## Release notes (App-Store-What's-New)

Every user-visible change (new feature, fixed bug the user noticed, behaviour
change) must also be written in `fastlane/metadata/de-DE/release_notes.txt` in
the user's voice (German, no jargon). This file holds the **next release's**
"What's New" text, accumulating since the last App-Store-published version.
Reset it after a `main` merge ships. `CHANGELOG.md` keeps the full technical
history; `release_notes.txt` is what TestFlight + App-Store users actually see.

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
