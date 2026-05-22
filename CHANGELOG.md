# Changelog

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
