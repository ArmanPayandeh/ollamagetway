#!/usr/bin/env bash
set -Eeuo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$PLUGIN_DIR/compose.yaml"

DC="docker compose"; $DC version &>/dev/null || DC="docker-compose"

usage(){ echo "Usage: ./stop.sh [ollama|proxy|all]  (default: all)"; }

case "${1:-all}" in
  "ollama") $DC -f "$COMPOSE_FILE" stop ollama || true;;
  "proxy")  $DC -f "$COMPOSE_FILE" stop proxy  || true;;
  "all")    $DC -f "$COMPOSE_FILE" stop || true;;
  *) usage; exit 1;;
esac

echo "✔ Done"
