#!/bin/sh
# SIGH-CNT — installe la tâche planifiée du serveur (Linux), toutes les 5 minutes.
# Usage : sh installer-linux.sh [chemin/vers/prototype_html]   (rejouable, ne duplique pas la ligne)
set -eu
RACINE="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
PHP="$(command -v php || true)"
[ -n "$PHP" ] || { echo "php introuvable dans le PATH" >&2; exit 1; }
[ -f "$RACINE/api/cron.php" ] || { echo "api/cron.php introuvable sous $RACINE" >&2; exit 1; }
JOURNAL="${SIGH_JOURNAL_CRON:-$RACINE/api/sauvegardes/cron.log}"
mkdir -p "$(dirname "$JOURNAL")"
LIGNE="*/5 * * * * $PHP $RACINE/api/cron.php >> $JOURNAL 2>&1 # SIGH-CNT"
( crontab -l 2>/dev/null | grep -v '# SIGH-CNT$' || true; echo "$LIGNE" ) | crontab -
echo "Tâche installée : $LIGNE"
echo "Vérification   : php $RACINE/api/cron.php --force   (puis écran « Tâches planifiées », M14)"
