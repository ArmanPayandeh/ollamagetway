#!/usr/bin/env bash
set -Eeuo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$PLUGIN_DIR/.env"
COMPOSE_FILE="$PLUGIN_DIR/compose.yaml"
[[ -f "$ENV_FILE" ]] || { echo "✖ .env not found; please run ./install.sh first"; exit 1; }
set -a; source "$ENV_FILE"; set +a

DC="docker compose"; $DC version &>/dev/null || DC="docker-compose"

usage() {
  cat <<USAGE
Usage:
  ./start.sh [--rotate-key] [--pull "llama3:8b mistral:7b"] [--no-proxy]

Options:
  --rotate-key       : Generate new Bearer token and save it to .env
  --pull "<models>"  : Pull models after service start (separate from PULL_MODELS in .env)
  --no-proxy         : Start only ollama (without Nginx)
USAGE
}

ROTATE=0; EXTRA_PULL=""
NO_PROXY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rotate-key) ROTATE=1; shift;;
    --pull) EXTRA_PULL="$2"; shift 2;;
    --no-proxy) NO_PROXY=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown argument: $1"; usage; exit 1;;
  esac
done

if [[ "$ROTATE" -eq 1 ]]; then
  if command -v openssl &>/dev/null; then
    API_KEY="$(openssl rand -hex 32)"
  else
    API_KEY="$(head -c 64 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 64)"
  fi
  sed -i "s/^API_KEY=.*/API_KEY=$API_KEY/" "$ENV_FILE"
  echo "• New API_KEY saved."
  sed -i "s/map \$auth_token \$is_authorized {[^}]*}/map \$auth_token \$is_authorized {\
    default 0;\
    $API_KEY 1;\
  }/g" "$PLUGIN_DIR/nginx.conf"
fi

if [[ "$NO_PROXY" -eq 1 ]]; then
  $DC -f "$COMPOSE_FILE" up -d ollama
else
  $DC -f "$COMPOSE_FILE" up -d ollama proxy
fi

echo "• Waiting for ollama service to be ready..."
for i in {1..30}; do
  if docker exec ollama sh -c "ollama --version" &>/dev/null; then break; fi
  sleep 1
done

ALL_PULL="$(printf '%s %s' "${PULL_MODELS:-}" "${EXTRA_PULL:-}" | xargs -n1 | sort -u | xargs)"
if [[ -n "$ALL_PULL" ]]; then
  echo "• Pulling models: $ALL_PULL"
  for m in $ALL_PULL; do
    echo "  - $m"
    docker exec ollama sh -c "ollama pull '$m'" || true
  done
fi

BASE_SCHEME="http"
[[ "${ENABLE_TLS:-0}" -eq 1 ]] && BASE_SCHEME="https"
BASE_URL="$BASE_SCHEME://$EXT_HOST:$PROXY_PORT/ollama"

echo ""
echo "======== Secure Access ========"
echo "Base URL:"
echo "  $BASE_URL"
echo "Token (Bearer):"
echo "  $API_KEY"
echo "Test example:"
echo "  curl -H 'Authorization: Bearer $API_KEY' $BASE_URL/api/tags"
if command -v qrencode &>/dev/null; then
  echo ""
  echo "QR: URL"
  qrencode -t ANSIUTF8 "$BASE_URL" || true
  echo "QR: Token"
  qrencode -t ANSIUTF8 "$API_KEY" || true
fi
echo "================================"
