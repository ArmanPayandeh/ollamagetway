#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV="$ROOT/.env"; [[ -f "$ENV" ]] && source "$ENV"
if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi

echo "=== docker ps ==="
$DC -f "$ROOT/docker-compose.yml" ps || true
echo
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'ollama|ollama-proxy' || true
echo
echo "Health (if proxy up):"
curl -sS -m 2 "http://127.0.0.1:${PROXY_PORT:-8999}/healthz" || echo "not reachable"
