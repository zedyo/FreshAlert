# FreshAlert – Session-Handoff

> Arbeitsnotiz für den nahtlosen Übergang zwischen Arbeits-Sessions.
> **Sobald alle offenen Punkte erledigt sind, kann diese Datei gelöscht werden.**
> Vollständige Versionshistorie: `CHANGELOG.md`.

**Stand:** 2026-06-12 · **Version:** 1.8.3 · **Branch:** `claude/jolly-bardeen-PaCoT`
**Offener PR:** [#8 — Release-Train v1.8.0+](https://github.com/zedyo/freshalert/pull/8)
(Draft, NICHT mergen vor ASC-Setup)

**CI-Status (zuletzt):** Erster voller Lauf (27433532721) war rot — beide
Ursachen behoben (v1.8.1: SwiftLint nicht vorinstalliert → brew install;
v1.8.2: echter Crash-Bug in `decrementQuantity`, vom neuen Test gefunden).
**49/55 → erwartet 55/55** und der gesamte v1.6/v1.7-Code kompiliert.
Ergebnis des Folge-Laufs prüfen, falls diese Session nichts mehr meldet.

---

## Was in dieser Session gemacht wurde

### v1.8.1–v1.8.3 – CI-Fixes + Session-Kontinuität
- CI-Fix: `brew install swiftlint` (nicht auf macos-15 vorinstalliert),
  `actions/checkout` v4→v5 (Node-20-Zwangsumstellung 16.06.2026).
- **Echter Bug gefixt** (von `AppViewModelCRUDTests` gefunden):
  `decrementQuantity` capturte das SwiftData-Modell in einem async Task →
  Fatal Error bei zwischenzeitlichem Löschen. Jetzt UUID + weak self + Refetch.
- **Session-Kontinuität:** `.claude/settings.json` + `.claude/hooks/
  session-start.sh` — jede neue Session bekommt automatisch Git-Stand,
  letzte Commits und dieses Handoff injiziert. CLAUDE.md → AI-Arbeitsworkflow
  Punkt 7: Handoff-Pflege am Session-Ende ist Pflicht.

### v1.7.3 – Orphan-Recovery robust + Logger + AppDelegate
- `NotificationService`: `userInfo` enthält jetzt `itemName` + `expiryDate`.
- `OrphanedNotificationParser` als pure `enum` extrahiert (testbar ohne
  `UNUserNotificationCenter`); Body-Parsing nur noch als Fallback für
  Pre-1.8-Notifications.
- `os.Logger` statt `print` in `AppViewModel.saveContext`.
- `AppDelegate`: `MainActor.assumeIsolated` statt Task-Hop.

### v1.7.4 – Paywall-Fehlerzustand
- `StoreManager.productsLoadFailed` (auch bei leerer Liste!), `retryLoadProducts()`.
- `PaywallView` zeigt Fehler + „Erneut versuchen"-Button statt endlos-Spinner.

### v1.7.5 – Saves + Services
- 4× stille `try? modelContext.save()` in Views durch `saveContext(...)` ersetzt
  (Onboarding, Lagerorte, Lagerort-Edit).
- `OpenFoodFactsService.fetchProduct`: ASCII-Ziffern-Validierung gegen
  Injection durch QR/Code128-Payloads.
- `WidgetDataStore.queueDeleteAll` dedupet; Decrement-Queue bewusst nicht.

### v1.7.6 – Compliance
- **`PrivacyInfo.xcprivacy`** in beiden Targets (App + Widget).
- **armv7** aus `FreshAlert/Info.plist` entfernt.

### v1.7.7 – Tests
- Drei neue Unit-Test-Dateien:
  `OrphanedNotificationParsingTests`, `WidgetDataStoreTests`, `AppViewModelCRUDTests`.
- `ExpiryLabelTests` um Status-Boundaries erweitert.
- `WidgetDataStore.defaults`: computed → injizierbare `nonisolated(unsafe) static var`.

### v1.7.8 – Doku für AI-Autonomie
- `CLAUDE.md`: neue Abschnitte „AI-Arbeitsworkflow (verbindlich)" + „Definition
  of Done"; pbxproj-ID-Bereiche, Lokalisierungs-Konvention, Persistenz-Regel.
- Doku-Konsolidierung minimal-invasiv: „Geltungsbereich"-Hinweise oben in
  `RELEASE_AUTOMATION.md` (= Single Source of Truth Pipeline), `APP_STORE.md`,
  `MONETIZATION.md`.

---

## Offene Punkte (To-do)

### Owner — App Store Connect (blockiert Merge nach `main`)
- [ ] **Adresse in App Store Connect korrigieren** (Owner kümmert sich).
- [ ] Vertrag **„Paid Applications"** bis Status **„Aktiv"** fertigstellen.
- [ ] **Small Business Program** beantragen (15 % statt 30 %).
- [ ] **Beide IAPs anlegen** (Anleitung: `docs/MONETIZATION.md` §6.2), IDs
  buchstabengenau: `com.freshalert.pro.yearly`, `com.freshalert.pro.lifetime`.
- [ ] Beim ersten Release: beide IAPs auf der Versionsseite an den Build hängen.

### Owner — Code/GitHub
- [ ] **Datenschutz-URL** in `PaywallView.swift` (TODO) durch echte gehostete
  URL ersetzen, bevor der erste Build zur App-Store-Review eingereicht wird.
- [ ] **Branch-Ruleset für `main`** in GitHub: PR-Pflicht + Required Check
  „Build & Test". Schützt vor versehentlichem Push-Release.

### Owner — Geräte-Smoke-Test vor Merge
CI beweist Kompilierbarkeit und Unit-Test-Verhalten, nicht UI-Wirkung. Vor Merge
bitte einmal manuell:

- Paywall: bei nicht geladenen Produkten → Fehlerzustand + „Erneut versuchen".
- Push-Notification: alle drei Quick-Actions (Verbraucht / 1 verbraucht /
  Alle verbraucht) funktional, Notifications werden korrekt gecancelt.
- Einstellungen → „Vermisste Produkte" (sofern welche existieren) →
  Wiederherstellen.
- Onboarding-Abschluss speichert Lagerorte; Lagerorte-CRUD speichert (A3-Fix).
- TestFlight-Upload: keine Mail von Apple mit ITMS-91053 (= Privacy-Manifest ok).

### Spätere PRs (nicht in diesem Release-Train)
- **L10n-Infrastruktur**: `Localizable.xcstrings` einführen + EN-Übersetzungen
  (braucht einen lokalen Xcode-Build des Owners, weil die String-Extraktion
  beim Build zurückgeschrieben wird).
- **Suche/Filter ab 100+ Produkten**: Predicate-basierte Suche, evtl. Sektionen
  pro Lagerort.
- **Statistiken**: Gerettete Lebensmittel, geschätzte Ersparnis, Verschwendungs-
  quote. Klein, sofortiger Nutzen für Retention.
- **MHD-Foto-OCR** (Vision-Framework, lokal): Kamera-Bild → MHD-Datum-Erkennung.
  Großer Komfort-Differenzierer gegenüber Konkurrenz.
- **iCloud-Sync + Familien-Sharing**: braucht Schema-Arbeit (`@Attribute(.unique)`
  ist mit CloudKit nicht kompatibel — Migration nötig).
- **Rezeptvorschläge für bald ablaufende Produkte**: braucht Rezept-Quelle/API.

---

## Wichtig zu wissen

- **Merge nach `main` = vollständiges App-Store-Release.** Vorbedingungen
  siehe `CLAUDE.md` → „AI-Arbeitsworkflow".
- **Cloud-Umgebung kann kein Swift kompilieren.** Verifikation NUR über den
  CI-Check „Build & Test" auf dem PR.
- **Build-Nummern:** CI vergibt Commit-Count (~70 nach diesem Train),
  `CURRENT_PROJECT_VERSION = 21` in `pbxproj` ist obsolet, wird beim Release
  überschrieben — nicht von Hand pflegen.
- **Manueller TestFlight-Upload (vor Merge nach `main`)** geht aus Xcode:
  Build-Nummer manuell erhöhen, **Distribute App → „TestFlight & App Store"**
  (NICHT „Internal Only" — das wäre eine Sackgasse für externe Tester).
- **Release-Notes-Konvention**: Endnutzer-Text in `fastlane/metadata/de-DE/`,
  Datei nach `main`-Merge leeren.

---

## Anhang: fertige Texte für TestFlight (Beta App Review)

**Beta-App-Beschreibung:**

> FreshAlert hilft dir, die Haltbarkeit deiner Lebensmittel im Blick zu
> behalten und Verschwendung zu vermeiden. Produkte fügst du per Barcode-Scan
> oder manuell hinzu – Name und Details holt die App automatisch aus der
> Open-Food-Facts-Datenbank. Vor Ablauf des Mindesthaltbarkeitsdatums wirst du
> per Mitteilung erinnert. Quick-Actions in der Mitteilung machen den
> Verbrauch in einem Tipp möglich. Ein Widget für den Home-Bildschirm zeigt
> dir die nächsten ablaufenden Produkte auf einen Blick. Bitte meldet
> Abstürze, falsche Produktdaten oder Darstellungsfehler direkt über das
> Feedback in TestFlight. Danke fürs Testen!

**Prüfanmerkungen (Review Notes):**

> FreshAlert ist eine App zum Verwalten von Lebensmittel-Haltbarkeitsdaten.
> Kein Benutzerkonto, kein Login — alle Daten lokal auf dem Gerät. Kamera:
> ausschließlich für Barcode-Scan und optionale Produktfotos. Netzwerk:
> öffentliche Produktdaten der Open-Food-Facts-API; ohne Internet bleibt die
> App nutzbar. Mitteilungen: lokale Benachrichtigungen erinnern an ablaufende
> Produkte, mit Quick-Actions zum direkten Verbrauch. In-App-Käufe
> (Freemium): bis zu 20 Einträge kostenlos, danach Paywall mit „Pro Jährlich"
> (Abo, 4,99 €/Jahr) und „Pro Lifetime" (Einmalkauf, 14,99 €). Zum Testen der
> Paywall 20 Produkte anlegen; der nächste Eintrag öffnet sie. UI ist
> deutschsprachig.

**„What to Test":**

> Erste Beta-Version mit Quick-Actions in Push-Notifications, „Vermisste
> Produkte"-Wiederherstellung in den Einstellungen und Paywall-Fehlerzustand
> bei nicht geladenen Produkten. Bitte alle Kernfunktionen testen:
> Barcode-Scan, manuelles Hinzufügen, Ablauf-Erinnerungen (inkl.
> Quick-Actions), Lagerorte, Home-Bildschirm-Widget.
