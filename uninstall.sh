#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi
$DC -f "$ROOT/docker-compose.yml" down -v --remove-orphans || true
read -rp "Remove downloaded models (data/ollama)? [y/N] " ans
[[ "$ans" =~ ^[Yy]$ ]] && sudo rm -rf "$ROOT/data/ollama"
echo "✔ uninstalled"
