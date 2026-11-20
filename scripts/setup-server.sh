#!/usr/bin/env bash
# Prepara y arranca el backend en el Mac mini (servidor) con OrbStack/Docker.
# Uso: ./scripts/setup-server.sh <url-git-del-repo>
set -euo pipefail

REPO_URL="${1:?Uso: ./setup-server.sh <url-git-del-repo>}"
DEST="$HOME/secret-satan-backend"

command -v docker >/dev/null || { echo "✗ Docker no encontrado. Abre OrbStack al menos una vez."; exit 1; }
docker info >/dev/null 2>&1 || { echo "✗ OrbStack no está en marcha. Ábrelo y repite."; exit 1; }
command -v git >/dev/null || { echo "✗ git no encontrado (instala las Command Line Tools)."; exit 1; }

if [ -d "$DEST/.git" ]; then
  git -C "$DEST" pull --ff-only
else
  git clone "$REPO_URL" "$DEST"
fi
cd "$DEST"

if [ ! -f .env ]; then
  ADMIN_TOKEN="$(openssl rand -hex 32)"
  read -r -p "TUNNEL_TOKEN de Cloudflare: " TUNNEL_TOKEN
  umask 077
  cat > .env <<EOF
ADMIN_TOKEN=$ADMIN_TOKEN
TUNNEL_TOKEN=$TUNNEL_TOKEN
BASE_URL=https://secretsanta.hdvillamil.dev
EOF
  echo
  echo "✓ .env creado. ADMIN_TOKEN para la app iOS (guárdalo ahora):"
  echo "  $ADMIN_TOKEN"
  echo
fi

mkdir -p data backups
docker compose up -d --build

# Copia de seguridad diaria (03:30) del SQLite con launchd.
PLIST="$HOME/Library/LaunchAgents/dev.hdvillamil.secretsatan.backup.plist"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>dev.hdvillamil.secretsatan.backup</string>
  <key>ProgramArguments</key><array><string>$DEST/scripts/backup.sh</string></array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>3</integer><key>Minute</key><integer>30</integer></dict>
</dict></plist>
EOF
chmod +x scripts/backup.sh
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo "✓ Listo. Comprueba: curl -s http://127.0.0.1:8080/health  y  https://secretsanta.hdvillamil.dev/health"
