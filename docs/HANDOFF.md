# FreshAlert – Session-Handoff

> Arbeitsnotiz für den nahtlosen Übergang zwischen Arbeits-Sessions.
> **Sobald alle offenen Punkte erledigt sind, kann diese Datei gelöscht werden.**
> Vollständige Versionshistorie: `CHANGELOG.md`.

**Stand:** 2026-06-12 · **Version:** 1.7.1 · **Branch:** `claude/jolly-bardeen-PaCoT`
(alle Commits gepusht)

---

## Was in dieser Session gemacht wurde

### Code
- **v1.5.3** – Build-Fehler in `PaywallView.swift` behoben (gerades `"` beendete
  das String-Literal). Damit kompilierte der StoreKit-Code erstmals.
- **v1.6.0** – Wiederherstellung verlorener Produkte: verwaiste Notifications
  (geplant, aber Produkt nicht mehr im Datenbestand) werden beim Start erkannt
  und in den Einstellungen unter „Vermisste Produkte" zum Wiederherstellen/
  Verwerfen angeboten. Alle stillen `try? modelContext.save()` durch
  `saveContext()` (Logging + Fehler-Toast) ersetzt.
- **v1.7.0** – Quick Actions in Push-Notifications: „Verbraucht" (Menge 1) bzw.
  „1 verbraucht" / „Alle verbraucht" (Menge > 1) direkt aus der Mitteilung,
  via App-Group-Queue (gleicher Mechanismus wie das Widget). Außerdem
  Release-Notes-Workflow eingeführt (`fastlane/metadata/de-DE/release_notes.txt`
  + Konvention in `CLAUDE.md`).

### TestFlight / App Store Connect (manuell durch den Owner)
- Erster TestFlight-Build hochgeladen (1.5.3, Build 21, **Internal Only**),
  läuft auf dem iPhone des Owners. Signing auf das bezahlte Team
  „Nikolai Seel" umgestellt (vorher fälschlich Personal Team).
- DSA-Händlererklärung („Händler"), Namens-Dokument und Bankverbindung (IBAN)
  in App Store Connect eingereicht/eingetragen.

---

## Offene Punkte (To-do)

### App Store Connect – Monetarisierung (NÄCHSTER SCHRITT, wartet auf Owner)
- [ ] **Adresse in App Store Connect korrigieren** – Owner kümmert sich, dauert
  noch. Blockiert die folgenden Punkte.
- [ ] Vertrag **„Paid Applications"** fertigstellen (Bank ✓, Steuerformulare,
  Kontakte) bis Status **„Aktiv"**. Ohne ihn liefert `Product.products(for:)`
  eine leere Liste → Paywall bleibt leer, auch in TestFlight.
- [ ] **Small Business Program** beantragen (15 % statt 30 %).
- [ ] **Beide IAPs anlegen** (Anleitung: `docs/MONETIZATION.md` §6.2), IDs
  buchstabengenau: `com.freshalert.pro.yearly` (Abo, 4,99 €/Jahr),
  `com.freshalert.pro.lifetime` (Non-Consumable, 14,99 €). Beide bis Status
  „Bereit zur Einreichung" (inkl. Prüf-Screenshot der Paywall, im Simulator
  mit `Products.storekit` erstellbar).
- [ ] Danach in TestFlight prüfen: Paywall zeigt beide Produkte; Sandbox-Käufe
  sind für Tester gratis (kein Coupon-Mechanismus nötig – bewusst entschieden).
- [ ] Beim **ersten** App-Store-Release: beide IAPs auf der Versionsseite an
  den Build hängen (`docs/MONETIZATION.md` §6.3).

### TestFlight – externe Tester
- [ ] Neuen Build mit Distribution **„TestFlight & App Store"** hochladen
  („Internal Only"-Builds lassen sich externen Gruppen nicht zuordnen!).
  Build-Nummer manuell erhöhen (zuletzt: 22).
- [ ] Build der externen Gruppe zuordnen, „What to Test" ausfüllen, zur
  **Beta App Review** einreichen. Test-Informationen (Beschreibung, Kontakt)
  ggf. vervollständigen – fertige Texte siehe Anhang unten.

### Code
- [ ] **v1.6.0/v1.7.0 noch nicht kompiliert/getestet** (keine Xcode-Umgebung
  hier). In Xcode bauen, `⌘U`, Quick Actions + Wiederherstellung auf dem Gerät
  testen, dann neuen TestFlight-Build hochladen.
- [ ] **Datenschutz-URL** in `PaywallView.swift` (`TODO` im `legalSection`)
  durch echte veröffentlichte Policy-URL ersetzen.
- [ ] `UIRequiredDeviceCapabilities` (`armv7`) aus `FreshAlert/Info.plist`
  entfernen – obsoleter 32-Bit-Eintrag. Upload ging zwar durch, der Eintrag
  ist aber falsch und potenziell problematisch.

### GitHub
- [ ] **Branch-Schutz für `main`** einrichten (PR-Pflicht + CI-Check
  „Build & Test"). Wichtig, da jeder Merge nach `main` ein vollständiges
  App-Store-Release auslöst.

---

## Wichtig zu wissen

- **Merge nach `main` = App-Store-Release** (TestFlight + Einreichung). Nicht
  mergen, bevor IAPs angelegt und angehängt sind, sonst scheitert die
  automatische Einreichung.
- **Vor jedem Merge nach `main`:** `MARKETING_VERSION` erhöhen (aktuell 1.7.1).
- **Build-Nummern:** CI vergibt Commit-Anzahl (aktuell ~62) – liegt sicher über
  den manuell vergebenen (21/22). Bei manuellen Uploads selbst hochzählen.
- **Mac-Checkout** des Owners war zuletzt auf dem alten Branch
  `claude/food-expiry-tracker-app-rg1F5` → auf `claude/jolly-bardeen-PaCoT`
  wechseln (`git fetch && git checkout claude/jolly-bardeen-PaCoT`).
- Release-Notes-Konvention: nutzersichtbare Änderungen zusätzlich in
  `fastlane/metadata/de-DE/release_notes.txt` (Endnutzer-Deutsch), siehe
  `CLAUDE.md`. Datei nach einem `main`-Merge-Release leeren.
- `project.pbxproj` ist handgepflegt – neue Dateien in alle vier Abschnitte
  (siehe `CLAUDE.md` → „Project file gotchas").

---

## Anhang: fertige Texte für TestFlight (Beta App Review)

**Beta-App-Beschreibung:**

> FreshAlert hilft dir, die Haltbarkeit deiner Lebensmittel im Blick zu
> behalten und Verschwendung zu vermeiden. Produkte fügst du per Barcode-Scan
> oder manuell hinzu – Name und Details holt die App automatisch aus der
> Open-Food-Facts-Datenbank. Vor Ablauf des Mindesthaltbarkeitsdatums wirst du
> per Mitteilung erinnert. Ein Widget für den Home-Bildschirm zeigt dir die
> nächsten ablaufenden Produkte auf einen Blick. In dieser Beta kannst du den
> kompletten Funktionsumfang testen: Scanner, Ablauf-Erinnerungen, Lagerorte
> und Widget. Bitte meldet Abstürze, falsche Produktdaten oder
> Darstellungsfehler direkt über das Feedback in TestFlight. Danke fürs Testen!

**Prüfanmerkungen (Review Notes):**

> FreshAlert ist eine App zum Verwalten von Lebensmittel-Haltbarkeitsdaten.
> Es ist kein Benutzerkonto und kein Login erforderlich – alle Daten werden
> lokal auf dem Gerät gespeichert. Kamera: ausschließlich zum Scannen von
> Produkt-Barcodes und für optionale Produktfotos. Netzwerk: ruft öffentliche
> Produktdaten der Open-Food-Facts-API ab; ohne Internet bleibt die App
> nutzbar. Mitteilungen: lokale Benachrichtigungen erinnern an ablaufende
> Produkte. In-App-Käufe (Freemium): bis zu 20 Einträge kostenlos, danach
> Paywall mit „Pro Jährlich" (Abo) und „Pro Lifetime" (Einmalkauf). Zum Testen
> der Paywall 20 Produkte anlegen; der nächste Eintrag öffnet sie. Die
> Benutzeroberfläche ist deutschsprachig.

**„What to Test":**

> Erste Beta-Version. Bitte alle Kernfunktionen testen: Barcode-Scan,
> manuelles Hinzufügen, Ablauf-Erinnerungen, Lagerorte und das
> Home-Bildschirm-Widget.
