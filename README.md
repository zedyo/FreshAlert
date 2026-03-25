# FreshAlert

Eine native iOS-App zum Verwalten von Lebensmitteln mit Barcode-Scanner, Ablaufdatum-Tracking und Erinnerungen.

---

## Features

- **Barcode-Scanner** – Scannt EAN-8, EAN-13, UPC und mehr via Kamera
- **Open Food Facts** – Automatisches Abrufen von Produktname, Marke und Bild
- **Offline-Modus** – Einträge offline speichern, automatische Synchronisation wenn online
- **Lagerorte** – Anpassbare Orte mit SF Symbol Icons und Farben
- **Erinnerungen** – Globale + individuelle Benachrichtigungen vor Ablauf
- **Mengen-Tracking** – Menge reduzieren oder Produkt als aufgebraucht markieren
- **Clean Design** – SwiftUI, SwiftData, iOS 17+

---

## Technischer Stack

| Technologie | Verwendung |
|---|---|
| SwiftUI | UI Framework |
| SwiftData | Lokale Persistenz |
| AVFoundation | Barcode-Scanner |
| UserNotifications | Lokale Erinnerungen |
| Network (NWPathMonitor) | Online/Offline-Erkennung |
| Open Food Facts API | Kostenlose Produktdatenbank |

---

## Projektstruktur

```
FreshAlert/
├── FreshAlertApp.swift          # App-Einstiegspunkt, ModelContainer
├── ContentView.swift            # Tab-Navigation
├── Models/
│   ├── FoodItem.swift            # SwiftData-Modell für Lebensmittel
│   └── StorageLocation.swift     # SwiftData-Modell für Lagerorte + Color-Extension
├── Views/
│   ├── Dashboard/
│   │   ├── DashboardView.swift      # Hauptliste mit Filter, Suche, Stats
│   │   └── FoodItemCardView.swift   # Produktkarte + Detail-Sheet
│   ├── Scanner/
│   │   ├── BarcodeScannerView.swift # Kamera-Preview, Taschenlampe, manuell
│   │   └── AddFoodItemView.swift    # Formular: Name, MHD, Ort, Erinnerung
│   ├── StorageLocations/
│   │   ├── StorageLocationsView.swift
│   │   └── AddStorageLocationView.swift  # Icon-Picker, Farbauswahl
│   └── Settings/
│       └── SettingsView.swift       # Globale Erinnerung, Netzwerk-Status
├── Services/
│   ├── OpenFoodFactsService.swift  # API-Abfrage (actor)
│   └── NotificationService.swift   # Benachrichtigungen planen/abbrechen
└── ViewModels/
    └── AppViewModel.swift          # Hauptlogik, Sync, CRUD
```

---

## Setup & Installation auf dem Mac

### Voraussetzungen

- **Mac** mit macOS 14 Sonoma oder neuer
- **Xcode 15.4** oder neuer ([kostenlos im Mac App Store](https://apps.apple.com/de/app/xcode/id497799835))
- **iOS 17** auf deinem iPhone (oder Simulator)

### Schritt 1: Repository klonen

```bash
git clone https://github.com/zedyo/project-ice.git
cd project-ice
git checkout claude/food-expiry-tracker-app-rg1F5
```

### Schritt 2: Xcode-Projekt öffnen

Doppelklick auf **`FreshAlert.xcodeproj`** – Xcode öffnet sich automatisch.

### Schritt 3: Bundle Identifier anpassen

1. Links im Projekt-Navigator auf **FreshAlert** klicken
2. Target **FreshAlert** auswählen
3. Tab **Signing & Capabilities**
4. `Bundle Identifier` auf etwas Einzigartiges ändern, z.B.: `com.DEINNAME.freshalert`

---

## App auf dem iPhone testen (OHNE bezahlten Developer Account)

Du kannst die App kostenlos mit einem **kostenlosen Apple-ID** auf deinem iPhone installieren.
Der kostenlose Account hat eine **7-Tage-Signatur** – danach musst du die App neu deployen.

### Schritt 1: iPhone verbinden

1. iPhone per USB-Kabel mit dem Mac verbinden
2. Auf dem iPhone: **Vertrauen** drücken wenn gefragt

### Schritt 2: Signing in Xcode einrichten

1. Xcode → Target **FreshAlert** → **Signing & Capabilities**
2. **Team**: Deine Apple-ID aus dem Dropdown wählen
   - Falls keine Apple-ID vorhanden: `Add Account...` → mit Apple-ID einloggen
3. **Automatically manage signing**: Checkbox aktiviert lassen
4. Xcode erstellt automatisch ein Provisioning Profile

### Schritt 3: iPhone als Ziel wählen

1. Oben links in Xcode: Geräte-Dropdown (neben dem Play-Button)
2. Dein iPhone aus der Liste auswählen

### Schritt 4: App installieren

1. **Cmd + R** drücken (oder Play-Button klicken)
2. Xcode kompiliert und installiert die App auf deinem iPhone

### Schritt 5: Dem Entwickler vertrauen (einmalig)

> Dieser Schritt ist nur beim ersten Mal nötig.

1. iPhone: **Einstellungen** → **Allgemein** → **VPN & Geräteverwaltung**
2. Unter "Entwickler-App": Deinen Apple-ID-Namen tippen
3. **Vertrauen** drücken
4. FreshAlert starten → App läuft!

---

## App im iOS Simulator testen (kein iPhone nötig)

> **Hinweis:** Der Barcode-Scanner funktioniert im Simulator nicht (keine echte Kamera). Du kannst Produkte aber manuell über den Tastatur-Button eingeben.

### Simulator starten

1. Xcode → Geräte-Dropdown → z.B. **iPhone 16 Pro** wählen
2. **Cmd + R** → Simulator startet und App öffnet sich
3. Im Scanner-Tab: **Tastatur-Icon** oben rechts → Barcode manuell eingeben

**Test-Barcodes:**
- `4000417025005` – Milka Schokolade
- `4008400201429` – Nutella
- `5000112637939` – Coca-Cola
- `4006381333641` – Persil

---

## Kamera-Berechtigung

Beim ersten Start des Scanners fragt die App um Kamera-Zugriff.
Bitte **Erlauben** drücken. Ohne Kamera-Berechtigung kann der Barcode-Scanner nicht funktionieren.
(Im Simulator erscheint diese Abfrage nicht.)

---

## Wichtige Hinweise zum kostenlosen Developer Account

| Einschränkung | Kostenlos | Bezahlt ($99/Jahr) |
|---|---|---|
| App auf eigenem iPhone | ✅ Ja | ✅ Ja |
| App auf fremden Geräten | ❌ Nein | ✅ Ja |
| App im App Store | ❌ Nein | ✅ Ja |
| Signatur-Gültigkeit | 7 Tage | 1 Jahr |
| Push Notifications | ❌ Nein | ✅ Ja |
| Gleichzeitige App-Registrierungen | 3 | Unbegrenzt |

**Nach 7 Tagen:** Einfach Xcode öffnen, iPhone verbinden und nochmals **Cmd + R** drücken.
Daten gehen dabei nicht verloren.

---

## Erste Schritte in der App

1. **Standorte** → Tab unten mitte → Eigene Lagerorte erstellen (oder Standardorte nutzen)
2. **Einstellungen** → Globale Erinnerungsfrist einstellen (Standard: 7 Tage)
3. **Scannen** → Barcode eines Produkts scannen
4. Ablaufdatum per Schnellauswahl oder Kalender eingeben
5. Lagerort auswählen → **Speichern**
6. **Übersicht** → Alle Produkte sortiert nach Ablaufdatum

---

## Lizenz

MIT License – Produktdaten via [Open Food Facts](https://world.openfoodfacts.org) (CC BY-SA)
