#!/usr/bin/env bash
# Construit les exécutables Dart du moteur de synchronisation (dart build cli : les exécutables natifs embarquent SQLite).
# Usage : packages/sync_dart/construire.sh [mere fileul mobile]   (par défaut : tout ce qui existe dans bin/)
set -euo pipefail
cd "$(dirname "$0")"
cibles=("$@"); [ ${#cibles[@]} -eq 0 ] && cibles=($(ls bin | sed 's/\.dart$//'))
for c in "${cibles[@]}"; do
  echo "→ $c"; rm -rf "build/${c}_bundle"; dart build cli -t "bin/${c}.dart" -o "build/${c}_bundle" > /dev/null
done
