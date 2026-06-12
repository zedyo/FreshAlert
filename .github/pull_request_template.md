<!-- PR-Template — siehe CLAUDE.md → "Definition of Done" -->

## Was & Warum

<!-- 1-3 Sätze: was ändert sich aus Nutzer- oder System-Sicht, warum. -->

## ⚠️ Merge-Konsequenz

Jeder Merge nach `main` löst über `release.yml` automatisch einen
**TestFlight-Upload + App-Store-Einreichung** aus. Vorbedingungen erfüllt?

- [ ] CI „Build & Test" grün
- [ ] CI „SwiftLint" grün (oder bewusste Ausnahme dokumentiert)
- [ ] Nutzersichtbare Änderungen → `fastlane/metadata/de-DE/release_notes.txt`
      aktualisiert (deutscher Endnutzerton)
- [ ] `CHANGELOG.md`-Eintrag
- [ ] `MARKETING_VERSION` 6× in `project.pbxproj` gebumpt
- [ ] Tests für neue Logik vorhanden (siehe `CLAUDE.md` → DoD)
- [ ] In App Store Connect: „Paid Applications"-Vertrag aktiv, IAPs am Build
      (sonst leere Paywall — siehe `docs/MONETIZATION.md` §6)
- [ ] Datenschutz-URL in `PaywallView.swift` ist real (kein `TODO`)
- [ ] Privacy-Manifest (`PrivacyInfo.xcprivacy`) deckt neue Required-Reason-APIs
- [ ] `/code-review` und `/security-review` einmal über den Diff gelaufen
- [ ] Smoke-Test auf dem Gerät, was CI nicht beweisen kann (UI-Wirkung,
      Notification-Actions, Paywall-Retry)

## Wie getestet

<!-- CI-Lauf reicht für Compilation + Unit-Tests; UI-/Notification-/Store-Wirkung
     manuell auf dem Gerät prüfen. Konkrete Schritte hier auflisten. -->
