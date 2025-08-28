#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV="$ROOT/.env"; source "$ENV"
if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi

$DC -f "$ROOT/docker-compose.yml" up -d ollama proxy

# wait ollama
echo "• waiting for ollama..."
for i in {1..30}; do docker exec ollama ollama --version >/dev/null 2>&1 && break || sleep 1; done

# print info
SCHEME="http"; [[ "${ENABLE_TLS:-0}" -eq 1 ]] && SCHEME="https"
BASE="$SCHEME://$EXT_HOST:$PROXY_PORT"
echo ""
echo "======== Secure Access ========"
echo "Health:  $BASE/healthz"
echo "Native:  $BASE/api/tags"
echo "OpenAI:  $BASE/v1/chat/completions"
echo "Header:  apikey: <YOUR_TOKEN>   or   Authorization: Bearer <YOUR_TOKEN>"
echo "Test:"
echo "  curl -i '$BASE' -H 'apikey: <YOUR_TOKEN>'"
echo "  curl -i '$BASE/api/tags' -H 'Authorization: Bearer <YOUR_TOKEN>'"
command -v qrencode >/dev/null 2>&1 && { echo "QR (URL)"; qrencode -t ANSIUTF8 "$BASE"; }
echo "================================"
