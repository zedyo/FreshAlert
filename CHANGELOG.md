# Changelog

## [1.5.2] – 2026-05-22

### Projekt / Dokumentation
- **`docs/HANDOFF.md`**: Session-Handoff hinzugefügt – fasst zusammen, was zuletzt
  umgesetzt wurde (StoreKit-2-Freemium, Deployment-Umstellung) und welche
  Aufgaben noch offen sind (Datenschutz-URL, In-App-Käufe in App Store Connect,
  Xcode-StoreKit-Konfiguration, Branch-Schutz). Ermöglicht den nahtlosen Übergang
  in eine neue Arbeits-Session. `CLAUDE.md` verweist darauf.

---

## [1.5.1] – 2026-05-22

### Projekt / Infrastruktur
- **Deployment**: Die App-Store-Einreichung erfolgt jetzt automatisch beim
  **Merge nach `main`** (statt zuvor über einen Versions-Tag). `release.yml` hat
  nur noch einen Job; die Fastlane-Lane `release` baut, lädt zu TestFlight hoch
  (wartet nun auf Apples Build-Verarbeitung) und reicht den Build anschließend
  zur App-Store-Prüfung ein.
- **Dokumentation**: `docs/MONETIZATION.md` um konkrete Setup-Schritte erweitert –
  In-App-Käufe in App Store Connect anlegen (mit aktuellen Menüpfaden),
  IAP-Einreichung an den Build hängen, StoreKit-Konfiguration im Xcode-Schema.
  `docs/RELEASE_AUTOMATION.md` an den neuen Merge-basierten Ablauf angepasst,
  inkl. Empfehlung zum Branch-Schutz für `main`.

---

## [1.5.0] – 2026-05-22

### Neue Funktionen
- **StoreKit 2 – Freemium-Modell**: Kostenlose Nutzung bis zu 20 gleichzeitig gespeicherten Produkten. Darüber hinaus erscheint die Paywall (Pro Jährlich 4,99 € / Pro Lifetime 14,99 €). Das Limit gilt beim Speichern in `AddFoodItemView` und beim Öffnen neuer Scans in `BarcodeScannerView`.
- **`StoreManager`** (`FreshAlert/Services/StoreManager.swift`): `@MainActor ObservableObject` — lädt Produkte via `Product.products(for:)`, prüft Berechtigung über `Transaction.currentEntitlements`, lauscht dauerhaft auf `Transaction.updates` (geräteübergreifende Käufe, Verlängerungen). Bietet `purchase(_:)` und `restorePurchases()`.
- **`PaywallView`** (`FreshAlert/Views/Paywall/PaywallView.swift`): Zeigt Pro Jährlich (empfohlen, grün) und Pro Lifetime. Enthält „Kauf wiederherstellen"-Button sowie Pflichtlinks zu Nutzungsbedingungen und Datenschutz.
- **`Products.storekit`** (`FreshAlert/Products.storekit`): StoreKit-Konfigurationsdatei für lokales Testen im Simulator ohne echte Käufe. Muss einmalig im Xcode-Schema unter Run → Options → StoreKit Configuration aktiviert werden.

### Hinweise vor der App-Store-Einreichung
- Produkte `com.freshalert.pro.yearly` und `com.freshalert.pro.lifetime` in App Store Connect anlegen.
- Datenschutz-URL in `PaywallView.swift` durch die veröffentlichte Policy ersetzen (TODO-Kommentar).
- Small Business Program beantragen (15 % statt 30 % Provision).

---

## [1.4.4] – 2026-05-22

### Projekt / Dokumentation
- **`docs/MONETIZATION.md`**: Umsatzeinschätzung und Monetarisierungs-Konzept –
  Freemium mit Eintrags-Limit, Preisempfehlung, Apple-Rahmenbedingungen und
  technischer Umsetzungsplan (StoreKit 2).

---

## [1.4.3] – 2026-05-22

### Projekt / Infrastruktur
- **Automatisches Deployment**: GitHub-Actions-Pipeline mit Fastlane hinzugefügt –
  Tests als Qualitäts-Gate bei jedem PR, automatischer TestFlight-Upload bei Push
  auf `main`, App-Store-Einreichung per Versions-Tag.
- **Dokumentation** unter `docs/`: Marketing-Konzept, App-Store-Anleitung,
  Deployment-/QA-Leitfaden und ein Datenschutzerklärungs-Entwurf.

---

## [1.4.2] – 2026-05-22

### Fehlerbehebungen
- **Scan-Linie**: Beim ersten Öffnen des Scanners „flog" die Linie vom oberen Bildschirmrand herein. Die Animation wurde komplett neu gebaut — sie wird jetzt zeitgesteuert über `TimelineView` gerendert (Position als reine Funktion der Uhrzeit). Dadurch gibt es keine zu interpolierende Animation mehr: kein Einfliegen, kein Überlagern, sauberer Neustart nach Tab-Wechseln.

---

## [1.4.1] – 2026-05-22

### Fehlerbehebungen
- **Scan-Linie**: Sprang aus dem grünen Rahmen, wenn man den Scanner-Tab verließ und zurückkehrte (zwei `repeatForever`-Animationen überlagerten sich). Die Animation läuft jetzt über `phaseAnimator` und startet bei jedem Wiedererscheinen sauber neu.

---

## [1.4.0] – 2026-05-22

### Neue Funktionen
- **Sound & Haptik**: Dezentes Feedback an sinnvollen Stellen — ein leichtes haptisches Tippen beim Wechsel der Tabs, ein feiner Ton plus Haptik bei erfolgreichem Barcode-Scan und beim Speichern eines Produkts, sowie ein kurzes Feedback beim Markieren als verwendet. Töne respektieren den Stummschalter des iPhones.

---

## [1.3.0] – 2026-05-22

### Neue Funktionen
- **Eigenes Produktfoto**: Wird ein Produkt nicht gefunden oder ist es ein Offline-Eintrag, kann beim manuellen Erfassen jetzt ein Foto aufgenommen oder aus der Mediathek gewählt werden. Das Bild wird lokal als Produktbild gespeichert. Im Bearbeiten-Modus genügt ein Tipp auf das Bildfeld (Kamera-Symbol).

### Fehlerbehebungen
- **Offline-Modus**: Bei Offline-Erfassung öffnet sich jetzt direkt der manuelle Eingabemodus (vorher blieb die Karte schreibgeschützt).
- Automatische Bereinigung „verwaister" Bilddaten beim Start entfernt — sie hätte selbst aufgenommene Produktfotos gelöscht.

---

## [1.2.2] – 2026-05-22

### Fehlerbehebungen
- **Saubere Pulls**: Die `project.pbxproj` und das geteilte Schema liegen jetzt exakt in der Form vor, die Xcode 26 erzeugt (Build-Phase „Embed Foundation Extensions", „Recovered References"-Gruppe für Frameworks, Schema `LastUpgradeVersion 2640`). Dadurch normalisiert Xcode die Dateien nicht mehr automatisch — keine ungewollten lokalen Änderungen mehr, die Pulls blockieren.

---

## [1.2.1] – 2026-05-22

### Verbesserungen
- **Benachrichtigungs-Abfrage**: Die iOS-Nachfrage „Darf FreshAlert dir Mitteilungen senden?" erscheint beim Erststart jetzt erst im Wizard — direkt nachdem die Erinnerungs-Funktion erklärt wurde — statt sofort beim App-Start. Bestehende Nutzer werden weiterhin beim Start gefragt.

---

## [1.2.0] – 2026-05-22

### Neue Funktionen
- **Einrichtungs-Wizard**: Beim allerersten Start führt ein Tutorial durch die App (Scannen, Erinnerungen) und lässt den Nutzer seine Lagerorte auswählen. Erscheint nur, wenn noch keine Lagerorte existieren; bestehende Nutzer sehen ihn nicht.

### Verbesserungen
- **Code-Qualität**: Das Marken-Grün ist jetzt zentral als `Color.freshGreen` definiert statt 9× hartkodiert.
- **Tests**: Zusätzliche Unit-Tests für `daysUntilExpiry`, `Color(hex:)` und die Standard-Lagerorte.
- **Geteiltes Xcode-Schema**: `FreshAlert.xcscheme` ist nun versioniert — das Test-Target ist fest im Schema verankert und das Setup geht bei Pulls nicht mehr verloren. Test-Code wird bei jedem Build mitkompiliert.
- **Projekt-Doku**: `CLAUDE.md` mit Architektur-Überblick und Projekt-Konventionen hinzugefügt.

### Fehlerbehebungen
- Überflüssiges Ternary in `WidgetDataStore.expiryLabel` entfernt.
- Lagerorte werden nicht mehr automatisch beim Start angelegt — das übernimmt jetzt der Wizard.

---

## [1.1.7] – 2026-05-22

### Fehlerbehebungen
- **Build-Warnungen**: `AppDelegate.pendingShortcutType` als `nonisolated(unsafe)` markiert — behebt zwei Swift-Concurrency-Warnungen („Main actor-isolated static property can not be referenced/mutated from a Sendable closure"). Die Property wird ausschließlich auf dem Main-Thread verwendet.

---

## [1.1.6] – 2026-05-22

### Verbesserungen
- **Widget – keine manuelle Einrichtung mehr**: Die App Group `group.com.freshalert.app` wird jetzt über versionierte `.entitlements`-Dateien (`FreshAlert.entitlements`, `FreshAlertWidget.entitlements`) und feste `CODE_SIGN_ENTITLEMENTS`-Build-Settings konfiguriert. Bisher musste die App Group nach jedem Clone/Pull manuell in Xcode unter „Signing & Capabilities" für beide Targets aktiviert werden. Das Widget ist nun direkt aktiv und teilt Daten ohne Setup.
- **Settings**: Obsolete „Widget einrichten"-Anleitung entfernt.

---

## [1.1.5] – 2026-05-22

### Fehlerbehebungen
- **Home Screen Quick Action**: Endgültige Behebung. Ursache war, dass SwiftUI-Scene-Apps Quick Actions **ausschließlich** an den Scene-Delegate liefern — `UIApplicationDelegate.performActionFor` wird nie aufgerufen, und der Kaltstart-Shortcut steht nicht in `launchOptions`. Ein echter `SceneDelegate` wurde hinzugefügt: Kaltstart über `scene(_:willConnectTo:)` (`connectionOptions.shortcutItem`), Hintergrund→Vordergrund über `windowScene(_:performActionFor:)`.

---

## [1.1.4] – 2026-05-22

### Fehlerbehebungen
- **Home Screen Quick Action**: Umstellung von SwiftUI-`scenePhase` auf `UIApplication.didBecomeActiveNotification`-Beobachtung in `AppViewModel`.

---

## [1.1.3] – 2026-05-22

### Fehlerbehebungen / Verbesserungen
- **Produkt-Karte**: „Details"-Bereich (Name/Marke-TextFelder) entfernt. Name und Marke können direkt in der Produktkarte bearbeitet werden — Karte antippen öffnet die Felder inline. Bei manuellem Eintrag oder nicht gefundenem Produkt sind die Felder sofort aktiv.

---

## [1.1.2] – 2026-05-22

### Fehlerbehebungen
- **Quick Action**: `performActionFor` setzt jetzt `pendingShortcutType` statt direkt eine Notification zu posten — behebt den Tab-Wechsel bei Hintergrund→Vordergrund.
- **Scan-Linie**: Animation startet jetzt zuverlässig neu nach jedem Scan (`.onAppear` auf die Capsule verschoben, `scanLineProgress` wird vor dem Start zurückgesetzt).
- **Suchleiste**: Suche-Button entfernt; native iOS-Suchleiste (nach oben scrollen) übernimmt. Liste startet leicht gescrollt damit die Suchleiste initial eingeklappt ist.
- **Xcode-Datenmüll**: `.gitignore` hinzugefügt — `xcuserdata/`, `*.xcuserstate` u.a. werden nicht mehr getrackt, kein „Stash Changes"-Dialog mehr beim Pull.

---

## [1.1.1] – 2026-05-22

### Fehlerbehebungen
- **Quick Action**: Wechsel in den Scanner-Tab funktioniert jetzt zuverlässig (Race-Condition beim Kaltstart behoben).
- **Versionsnummer**: Wird in den Einstellungen jetzt dynamisch aus dem App-Bundle gelesen.
- **Build-Fehler**: `isAutoSmoothAutoFocusEnabled` entfernt (API nicht im aktuellen SDK vorhanden).
- **Warnung**: Unbenutzte Variable `frameX` im Scanner-Overlay entfernt.

---

## [1.1.0] – 2026-05-22

### Neue Funktionen
- **Home Screen Quick Action**: Langes Drücken auf das App-Icon öffnet direkt den Scanner.
- **Manuelle Produkteingabe**: Im Scanner-Modus kann über „Ohne Barcode hinzufügen" ein Produkt ohne Barcode erfasst werden.

### Verbesserungen
- **Ablaufdatum-Anzeige**: Heute ablaufende Produkte zeigen „Heute verbrauchen". Bereits abgelaufene Produkte zeigen „Abgelaufen · X Tag(e)".
- **Suche**: Die Suchleiste wird nur noch angezeigt, wenn das Lupen-Symbol in der Titelleiste angetippt wird.
- **Scanner**: Verbesserte Zuverlässigkeit durch fokussierteren Scan-Bereich und automatische Fokusnachführung.

### Fehlerbehebungen
- Bilder werden dauerhaft lokal gespeichert und nach App-Neustart nicht neu geladen.
- Bilddaten werden beim Löschen eines Produkts korrekt entfernt.

---

## [1.0.0] – 2026-05-01

- Erstveröffentlichung
