# FreshAlert – App Store Deployment (manuell)

> Schritt-für-Schritt-Anleitung für die erste Veröffentlichung im App Store.
> Stand 2025, Xcode 26. Apple benennt Menüpunkte gelegentlich um – die
> Bezeichnungen können minimal abweichen.

Sobald die automatische Pipeline eingerichtet ist (siehe
`RELEASE_AUTOMATION.md`), brauchst du diese manuellen Schritte nicht mehr für
jedes Update – aber die **einmalige Einrichtung** (Abschnitte 1–6) ist trotzdem
nötig.

---

## 1. Was du brauchst

- **Mac** mit **Xcode 26**.
- **Apple Developer Program** – Mitgliedschaft kostet **99 USD/Jahr**.
  Anmeldung: <https://developer.apple.com/programs/> → „Enroll".
  Freischaltung dauert i. d. R. 24–48 h.
- Eine **Datenschutzrichtlinie** als öffentlich erreichbare URL (Pflicht!).
  Entwurf liegt bereit unter `docs/PRIVACY_POLICY.md` – hosten z. B. über
  GitHub Pages oder eine eigene Landingpage.
- Ein **App-Icon** 1024 × 1024 px (PNG, ohne Transparenz, ohne abgerundete Ecken)
  im Asset-Katalog (`Assets.xcassets` → `AppIcon`).
- **Screenshots** (siehe Abschnitt 5).

## 2. App-ID & Capabilities (Apple Developer Portal)

Bei automatischer Signierung legt Xcode die IDs beim ersten Archivieren selbst
an. Falls du es manuell machen willst:

1. <https://developer.apple.com/account> → **Certificates, Identifiers & Profiles**.
2. **Identifiers → +** → *App IDs* → *App*:
   - App: `com.freshalert.app`
   - Widget: `com.freshalert.app.widget`
   - Capability **App Groups** bei beiden aktivieren.
3. **Identifiers → +** → *App Groups* → `group.com.freshalert.app` anlegen und
   beiden App-IDs zuordnen.

(Die Entitlements-Dateien im Projekt verweisen bereits auf diese App Group.)

## 3. App in App Store Connect anlegen

1. <https://appstoreconnect.apple.com> → **Apps**.
2. Blaues **„+" → Neue App**.
3. Felder:
   - **Plattformen:** iOS
   - **Name:** `FreshAlert: Haltbarkeit` (Store-Name, max. 30 Zeichen)
   - **Primärsprache:** Deutsch
   - **Bundle-ID:** `com.freshalert.app` auswählen
   - **SKU:** frei wählbar, z. B. `freshalert-ios-001`
   - **Benutzerzugriff:** Vollzugriff

## 4. App-Informationen ausfüllen

In App Store Connect → deine App:

- **Allgemein → App-Informationen:** Kategorie *Essen & Trinken*,
  **Datenschutzrichtlinie-URL** eintragen (Pflicht).
- **App-Datenschutz** (Fragebogen „App Privacy"): FreshAlert hat keinen Account,
  kein Analyse-SDK, kein Tracking; Fotos bleiben lokal. Der Barcode-Abruf bei
  Open Food Facts überträgt keine personenbezogenen Daten. Daher i. d. R.
  **„Es werden keine Daten erfasst"** – beantworte den Fragebogen aber
  gewissenhaft selbst.
- Pro Version (linke Spalte, z. B. „1.0 Vorbereitung zur Einreichung"):
  **Werbetext**, **Beschreibung**, **Keywords**, **Support-URL**,
  **Screenshots**, **App-Icon**.

## 5. Screenshots

App Store Connect verlangt aktuell mindestens Screenshots für die
**iPhone-Displayklasse 6,9″** (1320 × 2868 px hochkant, z. B. iPhone 16 Pro Max).
Diese werden automatisch für kleinere iPhones skaliert; 6,5″/6,7″ werden auch
akzeptiert. 3–10 Screenshots empfohlen. iPad-Screenshots sind **nicht** nötig
(FreshAlert ist eine reine iPhone-App).

Erzeugen: im Xcode-Simulator (iPhone 16 Pro Max) mit `Cmd + S` bzw. über
`Datei → ...`, oder per Fastlane `snapshot` (optional).

## 6. Version & Build-Nummer

- `MARKETING_VERSION` = sichtbare Version (z. B. `1.4.3`).
- `CURRENT_PROJECT_VERSION` = Build-Nummer. **Jeder** Upload zu App Store Connect
  braucht eine eindeutige, höhere Build-Nummer. Die CI-Pipeline setzt diese
  automatisch (siehe `RELEASE_AUTOMATION.md`).
- Signing: Im Xcode-Projekt **Target → Signing & Capabilities → Team** wählen,
  „Automatically manage signing" aktiviert lassen.

## 7. Archivieren & Hochladen (rein manueller Weg)

1. In der Xcode-Toolbar als Ziel **„Any iOS Device (arm64)"** wählen
   (kein Simulator).
2. Menü **Product → Archive**.
3. Nach dem Build öffnet sich der **Organizer** (sonst: **Window → Organizer**).
4. Archiv auswählen → **Distribute App** → **App Store Connect** → **Upload**
   → Signierungsoptionen bestätigen → **Upload**.
5. Der Build erscheint nach einigen Minuten Verarbeitung in App Store Connect
   unter **TestFlight** und kann der Version zugewiesen werden.

## 8. TestFlight (Beta-Test vor Release)

In App Store Connect → **TestFlight**: interne Tester (eigene Apple-IDs, sofort)
oder externe Tester (Gruppe + kurze Beta-Prüfung durch Apple). Dringend
empfohlen, bevor du in den Store gehst.

## 9. Zur Prüfung einreichen

1. App Store Connect → App → Version → **Build auswählen**.
2. **Exportkonformität:** Das Projekt setzt `ITSAppUsesNonExemptEncryption = false`
   in der `Info.plist` – die Verschlüsselungsfrage entfällt dadurch.
3. Altersfreigabe, Preis (kostenlos), Verfügbarkeit festlegen.
4. **„Zur Prüfung hinzufügen" / „Add for Review"** → **Senden**.
5. Apple-Prüfung dauert üblicherweise 24–48 h. Danach automatisch oder manuell
   veröffentlichen (Option „Phased Release" für stufenweises Ausrollen möglich).

## 10. Häufige Ablehnungsgründe (vorab vermeiden)

- Fehlende/nicht erreichbare Datenschutz-URL.
- Kamera-Nutzungstext unklar – FreshAlert erklärt ihn in der `Info.plist`
  (`NSCameraUsageDescription`) bereits.
- Abstürze beim Review – vorher per TestFlight testen.
- Platzhalter-Inhalte oder Demo-Daten.
