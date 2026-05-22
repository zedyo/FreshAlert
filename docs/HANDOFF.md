# FreshAlert – Session-Handoff

> Arbeitsnotiz für den nahtlosen Übergang zwischen Arbeits-Sessions.
> **Sobald alle offenen Punkte erledigt sind, kann diese Datei gelöscht werden.**
> Vollständige Versionshistorie: `CHANGELOG.md`.

**Stand:** 2026-05-22 · **Version:** 1.5.2 · **Branch:** `claude/food-expiry-tracker-app-rg1F5`
(alle Commits gepusht, Arbeitsverzeichnis sauber)

---

## Was in dieser Session gemacht wurde

### v1.5.0 – StoreKit 2 Freemium-Modell
- **Entscheidung Preise:** Jahresabo **4,99 €**, Lifetime **14,99 €** – bewusst
  **kein Monatsabo** (für eine einfache Offline-Utility zu teuer empfunden).
- Neue Dateien:
  - `FreshAlert/Services/StoreManager.swift` – `@MainActor ObservableObject`,
    lädt Produkte, prüft `Transaction.currentEntitlements`, beobachtet
    `Transaction.updates`, `purchase()` / `restorePurchases()`, `freeLimit = 20`.
  - `FreshAlert/Views/Paywall/PaywallView.swift` – Paywall, „Kauf wiederherstellen",
    Verlängerungshinweis, Pflichtlinks.
  - `FreshAlert/Products.storekit` – Simulator-Testkonfiguration.
- **Gate:** Ab 20 gespeicherten Einträgen zeigt `AddFoodItemView` (vor dem
  Speichern) und `BarcodeScannerView` (Scan / manueller Eintrag) die Paywall.
- `StoreManager` wird in `FreshAlertApp` als `@StateObject` erzeugt und per
  `.environmentObject` injiziert.

### v1.5.1 – Deployment-Umstellung
- App-Store-Einreichung passiert jetzt **beim Merge nach `main`** (vorher
  Versions-Tag). `release.yml` hat nur noch einen Job; Lane `release` ruft `beta`
  auf (Build + TestFlight, wartet auf Verarbeitung) und reicht danach ein.
- Setup-Doku in `docs/MONETIZATION.md` und `docs/RELEASE_AUTOMATION.md`
  aktualisiert.

---

## Offene Punkte (To-do)

### Code
- [ ] **Datenschutz-URL** in `FreshAlert/Views/Paywall/PaywallView.swift`
  (markiert mit `TODO`, im `legalSection`) durch die echte, veröffentlichte
  Policy-URL ersetzen.
- [ ] **Build noch nicht verifiziert:** Der StoreKit-Code wurde in dieser
  Umgebung **nicht kompiliert** (kein Xcode verfügbar). In der nächsten Session
  in Xcode bauen, `⌘U` für Tests laufen lassen, Paywall im Simulator prüfen.

### App Store Connect (Details: `docs/MONETIZATION.md`, Abschnitt 6)
- [ ] Vertrag „Paid Applications" akzeptieren, Bank-/Steuerdaten hinterlegen.
- [ ] Small Business Program beantragen (15 % statt 30 % Provision).
- [ ] In-App-Käufe anlegen – Produkt-IDs **buchstabengenau**:
  - `com.freshalert.pro.yearly` – Auto-Abo, 4,99 €/Jahr
  - `com.freshalert.pro.lifetime` – Non-Consumable, 14,99 €
- [ ] Beide IAPs bei der **ersten** Versionseinreichung an den Build hängen.

### Xcode
- [ ] Schema konfigurieren: **Edit Scheme → Run → Options → StoreKit
  Configuration → `Products.storekit`** (für Simulator-Tests ohne echte Käufe).

### GitHub
- [ ] **Branch-Schutz für `main`** einrichten (PR-Pflicht + CI-Check
  „Build & Test"). Wichtig, da jeder Merge nach `main` jetzt ein vollständiges
  App-Store-Release auslöst.

---

## Wichtig zu wissen

- **Merge nach `main` = App-Store-Release.** Kein Tag-Schritt mehr.
- **Vor jedem Merge nach `main`:** `MARKETING_VERSION` in `project.pbxproj`
  erhöhen – Apple lehnt Builds mit bereits veröffentlichter Version ab.
- Projektkonvention: jeder Commit bumpt die Version + `CHANGELOG.md`-Eintrag
  (siehe `CLAUDE.md`).
- `project.pbxproj` ist handgepflegt – neue Dateien in alle vier Abschnitte
  eintragen (siehe `CLAUDE.md` → „Project file gotchas").
