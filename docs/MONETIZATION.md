# FreshAlert – Monetarisierung & Umsatzeinschätzung

> Ehrliche Einordnung, wie viel sich verdienen lässt, und ein konkreter
> Umsetzungsplan für ein Freemium-Modell mit Eintrags-Limit.

## 1. Wie viel kann man realistisch verdienen?

**Ehrlich vorweg:** Der Umsatz hängt fast vollständig von der **Nutzerzahl** ab –
und die hängt vom Marketing ab, nicht von der App selbst. Die allermeisten
Indie-Utility-Apps verdienen wenig (Hobby-Einkommen). Eine seriöse Einzelprognose
ist unmöglich; sinnvoll ist nur eine **Modellrechnung**, die du selbst füllst.

### Faustformel (Abo-Modell)

```
Monatsumsatz (netto) ≈ zahlende Abonnenten × Ø-Netto-Erlös pro Abo/Monat
zahlende Abonnenten  ≈ aktive Nutzer × Conversion-Rate
```

Übliche Werte für Freemium-Utility-Apps:
- **Conversion Free → zahlend:** 1–5 % (oft ~2–3 %)
- **Apple-Provision:** 30 %, bzw. **15 %** im *App Store Small Business Program*
  (für Entwickler < 1 Mio. USD/Jahr – das gilt für dich, muss aber beantragt
  werden). Rechne mit **15 %** → du behältst 85 %.

### Szenarien (Beispiel: Jahresabo 11,99 €, ~0,85 €/Monat netto pro Abo)

| Aktive Nutzer | Conversion | Abonnenten | Netto-Umsatz/Monat |
|---|---|---|---|
| 500 | 3 % | ~15 | ~15–30 € |
| 5.000 | 3 % | ~150 | ~150–300 € |
| 50.000 | 3 % | ~1.500 | ~1.500–3.000 € |

**Einordnung:** Eine Nische-App im DACH-Markt landet realistisch eher im Bereich
*einige zehn bis wenige hundert Euro pro Monat* – relevante Einnahmen entstehen
erst mit zehntausenden Nutzern. Das ist kein App-Problem, sondern gilt für fast
alle Indie-Apps.

### Kosten dagegenrechnen

- Apple Developer Program: **99 USD/Jahr** (Pflicht).
- Ggf. GitHub-Actions-macOS-Minuten bei privatem Repo.
- Die App muss also erst ~100 €/Jahr einspielen, um kostendeckend zu sein.

## 2. Empfohlenes Modell

Dein Ansatz – **kostenlos bis zu einer bestimmten Anzahl Einträge, danach Abo** –
ist für eine Tracker-App sinnvoll und gut verständlich.

**Empfehlung:**
- **Gratis:** bis zu **20 gleichzeitig gespeicherte Produkte** (nicht „jemals
  angelegt" – sonst wird die App irgendwann unbenutzbar). Reicht für Singles und
  kleine Haushalte und macht die App vollwertig erlebbar.
- **FreshAlert Pro:** unbegrenzte Produkte.
- Limit-Wahl ist ein Kompromiss: zu niedrig → schlechte Bewertungen & Abwanderung;
  zu hoch → kaum Conversions. Start bei 20, später anhand der Daten justieren
  (ein Limit **senken** verärgert Bestandsnutzer – lieber etwas höher starten).

**Wichtig – biete beides an:**
- **Abo** (wiederkehrender Umsatz) **und** einen **einmaligen „Lifetime"-Kauf**.
  Viele Nutzer lehnen Abos für eine simple Offline-Utility ab und kaufen lieber
  einmalig. Beides parallel anzubieten maximiert die Conversion.

## 3. Preisempfehlung

| Produkt | Typ | Preis-Vorschlag |
|---|---|---|
| Pro Monatlich | Auto-Abo | 2,49 € |
| Pro Jährlich | Auto-Abo | 11,99 € (als „spare 60 %" ankern) |
| Pro Lifetime | Einmalkauf (non-consumable) | 24,99 € |

- **Einführungsangebot** (kostenlose Testphase, z. B. 7 Tage) beim Abo erhöht die
  Conversion deutlich – StoreKit unterstützt das.
- Jahresabo prominent als Standard zeigen, Monatsabo als Einstieg.

## 4. Apple-Rahmenbedingungen

- **Small Business Program** beantragen (App Store Connect → *Verträge* /
  Agreements) → 15 % statt 30 % Provision.
- **Verträge für bezahlte Apps** in App Store Connect aktivieren, **Bank- und
  Steuerdaten** hinterlegen – sonst keine Auszahlung.
- Auszahlung erfolgt monatlich, mit Verzögerung.
- Steuern: Einnahmen sind in Deutschland einkommen-/ggf. umsatzsteuerpflichtig –
  bei nennenswertem Umsatz steuerlich beraten lassen.

## 5. Technische Umsetzung

Empfohlen: **StoreKit 2** (modern, async/await, ab iOS 17 – passt zum Projekt).

### App Store Connect
1. **Abo-Gruppe** „FreshAlert Pro" anlegen mit zwei Auto-Abos (monatlich,
   jährlich).
2. Optional ein **non-consumable** Produkt „Lifetime".
3. Produkt-IDs vergeben, z. B. `com.freshalert.pro.monthly`,
   `com.freshalert.pro.yearly`, `com.freshalert.pro.lifetime`.

### Im Projekt (neue Dateien, alle ins App-Target)
- **`StoreManager.swift`** – `@MainActor ObservableObject`:
  - lädt Produkte via `Product.products(for:)`
  - veröffentlicht `@Published var isPro: Bool`
  - prüft Berechtigung über `Transaction.currentEntitlements`
  - lauscht auf `Transaction.updates` (Käufe von anderen Geräten / Verlängerungen)
  - bietet `purchase(_:)` und `restorePurchases()`
- **`PaywallView.swift`** – wird angezeigt, wenn das Limit erreicht ist:
  Produkte, Preise, „Kauf wiederherstellen", Links zu Nutzungsbedingungen
  (Apple-Standard-EULA) und Datenschutz.
- **`Products.storekit`** – StoreKit-Konfigurationsdatei für lokales Testen im
  Simulator ohne echte Käufe.

### Die eigentliche Sperre (Gate)
- Item-Anzahl ermitteln (`fetchCount`/`@Query` auf `FoodItem`).
- In `AddFoodItemView` bzw. vor dem Speichern prüfen:
  `if !store.isPro && itemCount >= freeLimit → PaywallView zeigen statt speichern`.
- `freeLimit` als zentrale Konstante (z. B. `20`).
- `BarcodeScannerView` ebenso absichern (auch der Scan führt zum Anlegen).

### Pflicht für die App-Prüfung
- Paywall muss **Preis, Laufzeit und Verlängerungshinweis** klar nennen.
- **„Kauf wiederherstellen"-Button** ist Pflicht.
- Links zu **Nutzungsbedingungen** und **Datenschutzerklärung** auf der Paywall.
- Abo-Bedingungen auch in der Store-Beschreibung angeben.

### Aufwand
Überschaubar – grob ein bis zwei Tage Implementierung plus Tests. Der größere
Teil ist die Einrichtung in App Store Connect und das Testen der Kaufabläufe.

## 6. Nächste Schritte

1. Entscheiden: Freigrenze (Empfehlung 20) und Preise.
2. Small Business Program + Verträge/Steuerdaten in App Store Connect erledigen.
3. In-App-Produkte in App Store Connect anlegen.
4. Implementierung StoreKit 2 (`StoreManager`, `PaywallView`, Gate).

Sag Bescheid, wenn ich die StoreKit-Integration umsetzen soll – dann baue ich
`StoreManager`, `PaywallView`, die `.storekit`-Testdatei und das Eintrags-Limit
ein. Du müsstest dann nur noch die Produkte in App Store Connect anlegen.
