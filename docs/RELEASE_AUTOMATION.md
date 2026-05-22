# FreshAlert – Automatisches Deployment & Qualitätssicherung

> Ziel: Du beschreibst nur noch Änderungen, der Rest läuft automatisch –
> mit Tests als Qualitäts-Gate, automatischem Upload zu TestFlight und
> automatischer Einreichung im App Store, sobald nach `main` gemergt wird.

## So sieht der Alltag aus

1. Änderung umsetzen (oder umsetzen lassen) → Commit auf einem **Branch** →
   **Pull Request**.
2. GitHub Actions baut die App und führt die **Unit-Tests** aus (`ci.yml`).
   Schlägt ein Test fehl, lässt sich der PR nicht sinnvoll mergen → **Qualitäts-Gate**.
3. **PR nach `main` mergen** → die Pipeline (`release.yml`) baut automatisch eine
   signierte Version, lädt sie zu **TestFlight** hoch und reicht sie anschließend
   **zur App-Store-Prüfung** ein. Die Tests laufen dabei erneut – nichts geht
   ohne grüne Tests live.

**Ein Merge nach `main` ist damit ein vollständiges App-Store-Release.** Einen
separaten Tag-Schritt gibt es nicht mehr – wer nur testen will, bleibt im Pull
Request auf einem Branch. Build-Nummern werden automatisch vergeben (Commit-Anzahl).

> **Wichtig:** Weil jeder Merge nach `main` die App zur Apple-Prüfung schickt,
> sollte `main` geschützt sein (siehe „Qualitätssicherung") und ausschließlich
> über geprüfte Pull Requests beschrieben werden – kein direkter Push.

## Qualitätssicherung

- **Jeder** PR und **jeder** Release-Build führt die Test-Suite
  (`FreshAlertTests`) über die Fastlane-Lane `test` aus.
- Der Build selbst kompiliert das Test-Target mit – Code, der die Tests nicht
  mehr übersetzbar macht, lässt den Build sofort fehlschlagen.
- **Dringend empfohlen** (weil jeder Merge live geht): in GitHub unter
  **Settings → Branches → Add branch ruleset** (bzw. **Branch protection rules**)
  eine Regel für `main` anlegen, die
  - den CI-Check **„Build & Test"** als Pflicht verlangt („Require status checks
    to pass"),
  - **„Require a pull request before merging"** aktiviert,
  - direkte Pushes auf `main` blockiert.

## Einmalige Einrichtung

Diese Schritte sind **einmal** nötig. Voraussetzung: aktives Apple Developer
Program (siehe `APP_STORE.md`) und die App ist in App Store Connect angelegt.

### 1. App Store Connect API-Key erstellen

1. <https://appstoreconnect.apple.com> → **Benutzer und Zugriff** →
   Tab **Integrationen** → **App Store Connect API** (früher „Keys").
2. **+** → Name vergeben, Rolle **App Manager** → **Generieren**.
3. Die `.p8`-Datei **herunterladen** (geht nur einmal!). Notieren:
   - **Key ID** (z. B. `A1B2C3D4E5`)
   - **Issuer ID** (oben auf der Seite)

### 2. Code-Signing-Repository für `fastlane match`

`match` legt Zertifikate & Provisioning-Profile verschlüsselt in einem
**separaten, privaten** Git-Repo ab.

1. Auf GitHub ein **privates, leeres** Repo anlegen, z. B. `freshalert-certs`.
2. Lokal einmalig (Mac mit Xcode):
   ```sh
   bundle install
   export MATCH_GIT_URL="https://github.com/<user>/freshalert-certs.git"
   bundle exec fastlane match appstore
   ```
   Dabei wird ein **Passwort** für die Verschlüsselung gesetzt – merken, das ist
   später `MATCH_PASSWORD`.

### 3. GitHub-Secrets hinterlegen

Repo → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Inhalt |
|---|---|
| `ASC_KEY_ID` | Key ID aus Schritt 1 |
| `ASC_ISSUER_ID` | Issuer ID aus Schritt 1 |
| `ASC_KEY_CONTENT` | Inhalt der `.p8`-Datei, **Base64-codiert** (`base64 -i AuthKey_XXX.p8 \| pbcopy`) |
| `MATCH_GIT_URL` | URL des Zertifikats-Repos aus Schritt 2 |
| `MATCH_PASSWORD` | Verschlüsselungs-Passwort aus Schritt 2 |
| `MATCH_GIT_BASIC_AUTHORIZATION` | `<user>:<github-token>` Base64-codiert – damit die CI das private Cert-Repo klonen darf |

### 4. Lokal testen (optional, empfohlen)

```sh
bundle install
bundle exec fastlane test     # nur Tests
bundle exec fastlane beta     # vollständiger TestFlight-Lauf
```

## Beteiligte Dateien

| Datei | Zweck |
|---|---|
| `.github/workflows/ci.yml` | Build + Tests bei jedem PR / Push auf `main` |
| `.github/workflows/release.yml` | Merge nach `main` → TestFlight **+** App-Store-Einreichung |
| `fastlane/Fastfile` | Lanes `test`, `beta`, `release` |
| `fastlane/Appfile` | App-ID & Team-ID |
| `fastlane/Matchfile` | Konfiguration des Signing-Repos |
| `Gemfile` | Fastlane-Abhängigkeit |

Die Lane `release` ruft intern `beta` auf (bauen + TestFlight-Upload, **wartet**
auf Apples Build-Verarbeitung) und reicht den fertig verarbeiteten Build danach
über `deliver` zur Prüfung ein.

## Versionsnummern

- **`MARKETING_VERSION`** (sichtbare Version, z. B. `1.5.0`) wird bewusst im
  Projekt gesetzt, wenn du eine neue Nutzer-Version willst. **Wichtig:** Erhöhe
  sie, bevor du nach `main` mergst – Apple lehnt einen Build ab, dessen Version
  bereits veröffentlicht ist.
- **`CURRENT_PROJECT_VERSION`** (Build-Nummer) wird in der CI automatisch auf die
  Commit-Anzahl gesetzt – sie ist dadurch immer eindeutig und steigend. Du musst
  sie nicht mehr von Hand pflegen.

## Hinweise & Grenzen

- GitHub-Actions-`macos`-Runner sind kostenpflichtige Minuten (bei privaten
  Repos). Ein `release`-Lauf dauert nun länger (ca. 25–45 Min.), weil er auf
  Apples Build-Verarbeitung wartet, bevor er einreicht.
- Den Runner (`macos-15`) und `xcode-version` ggf. aktuell halten, wenn Apple
  neue Versionen veröffentlicht.
- Store-Texte, Screenshots und Preis werden weiterhin in App Store Connect
  gepflegt – die Pipeline lädt nur den Build hoch und reicht ihn ein. Beim
  **ersten** Release müssen diese Felder einmalig manuell befüllt sein
  (siehe `APP_STORE.md`), sonst scheitert die automatische Einreichung.
- Die Apple-Prüfung nach der Einreichung dauert weiterhin 24–48 h – das ist der
  einzige nicht automatisierbare Teil.
