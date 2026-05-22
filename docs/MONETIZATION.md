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

## 3. Preise (umgesetzt)

Ein Monatsabo wurde bewusst weggelassen: Für eine einfache Offline-Utility ohne
laufende Serverkosten ist es zu teuer empfunden und konvertiert schlecht. Daher
nur zwei klare Optionen:

| Produkt | Typ | Preis | Produkt-ID |
|---|---|---|---|
| Pro Jährlich | Auto-Abo | 4,99 € / Jahr | `com.freshalert.pro.yearly` |
| Pro Lifetime | Einmalkauf (non-consumable) | 14,99 € | `com.freshalert.pro.lifetime` |

- Das Jahresabo ist in der Paywall als **„EMPFOHLEN"** hervorgehoben (grün);
  Lifetime steht als ablösefreie Alternative darunter.
- **Einführungsangebot** (kostenlose Testphase, z. B. 7 Tage) beim Abo erhöht die
  Conversion – kann später in App Store Connect ergänzt werden.

## 4. Apple-Rahmenbedingungen

- **Small Business Program** beantragen (App Store Connect → *Verträge* /
  Agreements) → 15 % statt 30 % Provision.
- **Verträge für bezahlte Apps** in App Store Connect aktivieren, **Bank- und
  Steuerdaten** hinterlegen – sonst keine Auszahlung.
- Auszahlung erfolgt monatlich, mit Verzögerung.
- Steuern: Einnahmen sind in Deutschland einkommen-/ggf. umsatzsteuerpflichtig –
  bei nennenswertem Umsatz steuerlich beraten lassen.

## 5. Was im Code bereits umgesetzt ist

Die StoreKit-2-Integration ist seit **v1.5.0** vollständig im Projekt
(`CHANGELOG.md`). Im Code musst du nichts mehr tun:

- **`FreshAlert/Services/StoreManager.swift`** – `@MainActor ObservableObject`:
  lädt Produkte via `Product.products(for:)`, veröffentlicht `isPro`, prüft die
  Berechtigung über `Transaction.currentEntitlements`, lauscht dauerhaft auf
  `Transaction.updates` (Käufe anderer Geräte / Verlängerungen), bietet
  `purchase(_:)` und `restorePurchases()`. Konstante `freeLimit = 20`.
- **`FreshAlert/Views/Paywall/PaywallView.swift`** – Paywall mit beiden Produkten,
  „Kauf wiederherstellen", Verlängerungshinweis und Pflichtlinks.
- **`FreshAlert/Products.storekit`** – Testkonfiguration für den Simulator.
- **Gate**: `AddFoodItemView` (vor dem Speichern) und `BarcodeScannerView` (beim
  Scan / manuellen Eintrag) zeigen ab 20 Einträgen die Paywall statt zu speichern.

> **Vor der App-Store-Einreichung noch im Code zu erledigen:** In
> `PaywallView.swift` die **Datenschutz-URL** (markiert mit `TODO`) durch deine
> veröffentlichte Policy ersetzen.

## 6. Setup-Schritte für dich (App Store Connect & Xcode)

Apple ändert Menübezeichnungen gelegentlich – Stand 2025/2026, Xcode 26.

### 6.1 Verträge & Steuerdaten (sonst keine Käufe möglich)

1. <https://appstoreconnect.apple.com> → **Business** (früher „Verträge,
   Steuern und Bankverbindung").
2. Den Vertrag **„Paid Applications" / „Bezahlte Apps"** akzeptieren.
3. **Bankverbindung** und **Steuerdaten** hinterlegen.
4. **Small Business Program** beantragen (eigene Seite unter *Business* bzw.
   <https://developer.apple.com/app-store/small-business-program/>) → 15 % statt
   30 % Provision.

Ohne aktiven Paid-Apps-Vertrag liefert `Product.products(for:)` eine **leere
Liste** – die Paywall bleibt dann ohne Produkte.

### 6.2 In-App-Käufe in App Store Connect anlegen

App Store Connect → **Apps** → *FreshAlert* auswählen.

**A) Jahresabo** (linke Seitenleiste → Abschnitt *Monetarisierung* →
**Abonnements / Subscriptions**):

1. Zuerst eine **Abonnementgruppe** anlegen, Referenzname z. B. `FreshAlert Pro`.
2. In der Gruppe **+** → neues Abonnement:
   - **Referenzname:** `Pro Jährlich`
   - **Produkt-ID:** `com.freshalert.pro.yearly` (muss exakt so lauten)
3. Auf der Abo-Seite einstellen:
   - **Abodauer:** 1 Jahr
   - **Abonnementpreise:** Preis hinzufügen → Land *Deutschland* → Preispunkt
     **4,99 €** wählen (Apple rechnet die anderen Länder um)
   - **Lokalisierung:** Deutsch hinzufügen – Anzeigename „Pro Jährlich",
     Beschreibung
   - **Prüfinformationen:** einen Screenshot der Paywall hochladen
4. Status muss **„Bereit zur Einreichung"** erreichen.

**B) Lifetime** (Seitenleiste → **In-App-Käufe / In-App Purchases**):

1. **+** → Typ **Nicht-verbrauchbar (Non-Consumable)**.
2. **Referenzname:** `Pro Lifetime`, **Produkt-ID:** `com.freshalert.pro.lifetime`.
3. **Preis:** Preispunkt **14,99 €**.
4. **Lokalisierung** Deutsch (Anzeigename, Beschreibung) + **Prüf-Screenshot**.
5. Status **„Bereit zur Einreichung"**.

> Die Produkt-IDs müssen **buchstabengenau** mit den Konstanten in
> `StoreManager.swift` übereinstimmen, sonst werden sie nicht geladen.

### 6.3 Erste Einreichung: IAPs an den Build hängen

Neue In-App-Käufe werden beim **ersten Mal zusammen mit der App-Version**
geprüft. Auf der Versionsseite (App Store Connect → App → Version, z. B.
„1.5.0 – Vorbereitung zur Einreichung") im Abschnitt **„In-App-Käufe"** beide
Produkte zur Einreichung auswählen. Erst danach den Merge nach `main` auslösen
(die Pipeline lädt den Build hoch und reicht ein – siehe `RELEASE_AUTOMATION.md`).

Bei späteren Updates sind die IAPs bereits genehmigt und müssen nicht erneut
angehängt werden.

### 6.4 Lokales Testen im Simulator (ohne echte Käufe)

Damit die Paywall ohne echtes Apple-Konto funktioniert:

1. Xcode → in der Toolbar auf den Schema-Namen klicken → **Edit Scheme…**
   (oder Menü **Product → Scheme → Edit Scheme…**).
2. Links **Run** wählen → Tab **Options**.
3. Bei **StoreKit Configuration** im Dropdown **`Products.storekit`** auswählen.
4. App im Simulator starten → 20 Einträge anlegen → Paywall erscheint, Käufe
   laufen gegen die lokale Konfiguration (sofort, kostenlos, rücksetzbar über
   **Debug → StoreKit → Manage Transactions**).

Für Tests mit echtem Ablauf gegen App Store Connect → **Sandbox-Tester** unter
*Benutzer und Zugriff → Sandbox* anlegen und auf einem echten Gerät einloggen.

## 7. Pflichten für die App-Prüfung (im Code bereits erfüllt)

- Paywall nennt **Preis, Laufzeit und Verlängerungshinweis** klar. ✅
- **„Kauf wiederherstellen"-Button** vorhanden. ✅
- Links zu **Nutzungsbedingungen** (Apple-Standard-EULA) und **Datenschutz**. ✅
  (Datenschutz-URL noch eintragen, siehe Abschnitt 5.)
- Abo-Bedingungen zusätzlich in der **Store-Beschreibung** angeben (manuell in
  App Store Connect).

## 8. Reihenfolge zusammengefasst

1. Verträge/Steuern/Bank + Small Business Program (Abschnitt 6.1).
2. Beide In-App-Käufe anlegen, Status „Bereit zur Einreichung" (Abschnitt 6.2).
3. Datenschutz-URL in `PaywallView.swift` eintragen.
4. `MARKETING_VERSION` erhöhen, Kaufabläufe im Simulator testen (Abschnitt 6.4).
5. IAPs auf der Versionsseite an den Build hängen (Abschnitt 6.3).
6. PR nach `main` mergen → Pipeline lädt hoch und reicht ein.
