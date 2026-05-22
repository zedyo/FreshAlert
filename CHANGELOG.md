# Changelog

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
