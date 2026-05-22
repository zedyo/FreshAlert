# Changelog

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
