#!/bin/bash
# SessionStart-Hook: injiziert den aktuellen Projektstand in jede neue
# Claude-Code-Session (stdout wird als Kontext der Session hinzugefügt).
# Ziel: Sessions können ohne manuelles "mach dich vertraut" nahtlos
# weiterarbeiten. Fehlertolerant — endet immer mit Exit 0.

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" 2>/dev/null || exit 0

echo "=== FreshAlert: automatischer Session-Kontext (SessionStart-Hook) ==="
echo

echo "--- Git-Stand ---"
echo "Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unbekannt')"
DIRTY=$(git status --porcelain 2>/dev/null | head -10)
if [ -n "$DIRTY" ]; then
  echo "Uncommittete Änderungen:"
  echo "$DIRTY"
else
  echo "Arbeitsverzeichnis sauber."
fi
echo
echo "Letzte Commits:"
git log --oneline -5 2>/dev/null || echo "(kein git log verfügbar)"
echo

if [ -f docs/HANDOFF.md ]; then
  echo "--- docs/HANDOFF.md (Session-Handoff, Stand der letzten Session) ---"
  cat docs/HANDOFF.md
else
  echo "--- HINWEIS: docs/HANDOFF.md fehlt ---"
  echo "Entweder ist alles erledigt (Datei wurde regulär gelöscht) oder die"
  echo "letzte Session hat ihre Pflicht verletzt. Stand ggf. aus CHANGELOG.md"
  echo "und offenen PRs rekonstruieren."
fi

echo
echo "=== Verbindlich (siehe CLAUDE.md) ==="
echo "1. 'AI-Arbeitsworkflow' und 'Definition of Done' in CLAUDE.md gelten für jede Code-Änderung."
echo "2. Diese Umgebung kann KEIN Swift kompilieren — Verifikation nur über PR + CI-Check 'Build & Test'."
echo "3. Am SESSION-ENDE: docs/HANDOFF.md aktualisieren (was getan, was offen, PR-/CI-Status)."

exit 0
