#!/usr/bin/env bash
set -Eeuo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$PLUGIN_DIR/.env"
COMPOSE_FILE="$PLUGIN_DIR/compose.yaml"
DATA_DIR="$PLUGIN_DIR/data"

DC="docker compose"; $DC version &>/dev/null || DC="docker-compose"

usage(){ echo "Usage: ./uninstall.sh [ollama|proxy|all]  (default: all)"; }

TARGET="${1:-all}"
case "$TARGET" in
  "ollama"|"proxy"|"all") ;;
  *) usage; exit 1;;
esac

if [[ "$TARGET" == "all" ]]; then
  $DC -f "$COMPOSE_FILE" down -v --remove-orphans || true
else
  $DC -f "$COMPOSE_FILE" rm -s -f "$TARGET" || true
fi

echo "Remove data as well? (models are large) [y/N]"
read -r ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
  case "$TARGET" in
    "ollama") sudo rm -rf "$DATA_DIR/ollama";;
    "proxy")  echo "No data for proxy.";;
    "all")    sudo rm -rf "$DATA_DIR";;
  esac
fi

echo "✔ Uninstall done."
