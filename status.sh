#!/usr/bin/env bash
set -Eeuo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$PLUGIN_DIR/.env"
COMPOSE_FILE="$PLUGIN_DIR/compose.yaml"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

DC="docker compose"; $DC version &>/dev/null || DC="docker-compose"

echo "=== Containers ==="
$DC -f "$COMPOSE_FILE" ps || true
echo ""

has() { docker ps -a --format '{{.Names}}' | grep -q "^$1$"; }
run() { docker ps   --format '{{.Names}}' | grep -q "^$1$"; }

printf "%-16s : " "ollama"
if has "ollama"; then
  echo "$(run ollama && echo RUNNING || echo STOPPED)"
else
  echo "NOT INSTALLED"
fi

printf "%-16s : " "ollama-proxy"
if has "ollama-proxy"; then
  echo "$(run ollama-proxy && echo RUNNING || echo STOPPED)"
else
  echo "NOT INSTALLED"
fi

echo ""
if run "ollama"; then
  echo "=== Ollama info ==="
  docker exec ollama sh -c "ollama --version" || true
  echo "- Models:"
  docker exec ollama sh -c "ollama list || true" || true
fi

if [[ -n "${EXT_HOST:-}" && -n "${PROXY_PORT:-}" ]]; then
  scheme="http"; [[ "${ENABLE_TLS:-0}" -eq 1 ]] && scheme="https"
  echo ""
  echo "Gateway: ${scheme}://$EXT_HOST:$PROXY_PORT/ollama  (Authorization: Bearer <token>)"
  echo "Port bindings:"
  docker inspect -f '{{json .NetworkSettings.Ports}}' ollama-proxy 2>/dev/null || true
fi
