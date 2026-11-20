#!/usr/bin/env bash
# Copia consistente del SQLite (usa .backup) y conserva las últimas 14.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p backups
sqlite3 data/db.sqlite ".backup 'backups/db-$(date +%F).sqlite'"
ls -1t backups/db-*.sqlite | tail -n +15 | xargs -I{} rm -f {}
