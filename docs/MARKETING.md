# FreshAlert – Marketing-Konzept

> Aktiver Vermarktungsplan für die iOS-App FreshAlert.

## 1. Positionierung

**Ein-Satz-Pitch:** „FreshAlert ist die App gegen Lebensmittelverschwendung –
scanne deinen Einkauf, behalte jedes Mindesthaltbarkeitsdatum im Blick und
werde rechtzeitig erinnert, bevor etwas schlecht wird."

Kategorie im Store: **Essen & Trinken** (sekundär: Lifestyle).

## 2. Zielgruppen

| Segment | Motiv |
|---|---|
| Nachhaltigkeitsbewusste (25–45) | Umwelt, weniger Müll |
| Familien mit Wocheneinkauf | Überblick über große Vorräte |
| Studierende & Singles | Geld sparen, knappes Budget |
| Meal-Prepper / Selbstkocher | Planung, Resteverwertung |

Primärmarkt: **DACH** (App ist auf Deutsch). Später englische Lokalisierung
für internationale Skalierung.

## 3. Problem & Nutzenversprechen

- In Deutschland werden pro Kopf rund 75 kg Lebensmittel pro Jahr weggeworfen –
  ein großer Teil davon, weil das Haltbarkeitsdatum vergessen wird.
- **Nutzen:** weniger wegwerfen → Geld sparen → Umwelt schonen → weniger Stress.

## 4. Alleinstellungsmerkmale (USP)

- Barcode-Scan mit automatischem Abruf von Produktname, Marke & Bild
- Eigenes Foto möglich, wenn ein Produkt nicht gefunden wird
- Lokale Erinnerungen vor Ablauf (global + pro Produkt einstellbar)
- Home-Screen-Widget mit den nächsten ablaufenden Produkten
- Funktioniert offline
- **Datensparsam:** keine Registrierung, kein Account, kein Tracking

## 5. App Store Optimization (ASO) – wichtigster organischer Hebel

| Feld | Limit | Vorschlag |
|---|---|---|
| App-Name | 30 Zeichen | `FreshAlert: Haltbarkeit` |
| Untertitel | 30 Zeichen | `Lebensmittel & MHD im Blick` |
| Keywords | 100 Zeichen | `mhd,haltbarkeit,lebensmittel,vorrat,kühlschrank,ablaufdatum,einkauf,resteverwertung,scanner,erinnerung,foodwaste` |

Regeln:
- Keywords **nicht** im Namen/Untertitel wiederholen (Verschwendung von Platz).
- Keine Leerzeichen nach Kommas im Keyword-Feld.
- Promotion-Text (170 Zeichen, jederzeit ohne Review änderbar) für Aktionen nutzen.
- Erste Beschreibungszeile zählt am meisten – mit dem klarsten Nutzen starten.

## 6. Marketing-Kanäle

**Organisch (Start hier, kostenlos):**
- **ASO** – laufend Keywords, Screenshots und Conversion optimieren.
- **Kurzvideo (TikTok / Instagram Reels / YouTube Shorts):** Food-Waste-Content,
  „So spare ich 30 €/Monat", „Was ist in deinem Kühlschrank abgelaufen?".
- **Reddit:** r/de, r/Finanzen, r/ZeroWaste, Frugal-Communities – als hilfreicher
  Beitrag, nicht als Werbung.
- **Product Hunt Launch** – einmaliger Sichtbarkeits-Boost.
- **App-Review-Blogs & YouTuber** im Bereich Nachhaltigkeit/Produktivität anschreiben.
- **Eigene Landingpage** (auch für die Pflicht-Datenschutz-URL nutzbar, siehe
  `APP_STORE.md`) + kurze Pressemitteilung an Nachhaltigkeits-Medien.

**Bezahlt (optional, nach erstem organischem Traction):**
- **Apple Search Ads** – sehr effizient, da Nutzer mit Kaufabsicht; schon mit
  kleinem Tagesbudget testbar, ideal auf die ASO-Keywords.
- Instagram/TikTok-Ads für Reichweite.

## 7. Content-Ideen

- „Vorher/Nachher": voller Kühlschrank → nichts weggeworfen.
- Wöchentliche „Rette-deine-Reste"-Rezeptidee.
- Spar-Challenge: 30 Tage nichts wegwerfen.
- Saisonal: nach Weihnachten/Ostern (volle Vorräte).

## 8. Launch-Plan

1. **Pre-Launch:** Landingpage online, TestFlightBeta mit 10–30 Testern, erstes
   Feedback + erste Bewertungen vorbereiten.
2. **Launch-Woche:** Product Hunt, Social-Posts, Reddit-Beiträge, Pressemitteilung.
3. **Wachstum:** Apple Search Ads starten, Kooperationen, regelmäßige Updates
   (Updates verbessern das Store-Ranking).

## 9. Kennzahlen (KPIs)

- Downloads & Impressions → Download-Conversion (App Store Connect → Analysen)
- Retention D1 / D7
- Ø Sternebewertung (Ziel ≥ 4,5)
- Gescannte Produkte pro aktivem Nutzer

## 10. Bewertungen aktiv einsammeln

Empfehlung für ein künftiges Update: nach einem positiven Moment (z. B. 5.
Produkt als „verwendet" markiert) per `SKStoreReviewController` /
`requestReview` um eine Bewertung bitten. Bewertungen sind der stärkste
Hebel für Ranking **und** Conversion.
