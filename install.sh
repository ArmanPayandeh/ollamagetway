#!/usr/bin/env bash
set -Eeuo pipefail

# ========= Paths =========
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV="$ROOT/.env"
COMPOSE="$ROOT/docker-compose.yml"
NGINX_CONF="$ROOT/nginx.conf"
APIKEYS="$ROOT/apikeys.conf"
DATA_DIR="$ROOT/data/ollama"

# ========= Checks =========
need() { command -v "$1" >/dev/null 2>&1 || { echo "✖ required: $1"; exit 1; }; }
need docker
if docker compose version >/dev/null 2>&1; then DC="docker compose"; else need docker-compose; DC="docker-compose"; fi

# optional tools
for t in jq qrencode openssl; do command -v "$t" >/dev/null 2>&1 || MISSING="$MISSING $t"; done
if [[ -n "${MISSING:-}" ]] && command -v apt-get >/dev/null 2>&1; then
  echo "• installing optional tools:${MISSING}"
  sudo apt-get update -y && sudo apt-get install -y jq qrencode openssl || true
fi

mkdir -p "$DATA_DIR"

# ========= Interactive cfg =========
read -rp "Public port (gateway): [8999] " PROXY_PORT; PROXY_PORT="${PROXY_PORT:-8999}"
read -rp "External host/IP for clients (for info only): [auto] " EXT_HOST
if [[ -z "${EXT_HOST:-}" ]]; then EXT_HOST="$(hostname -I 2>/dev/null | awk '{print $1}')" || true; EXT_HOST="${EXT_HOST:-127.0.0.1}"; fi
read -rp "Allowed CORS origins (comma or *): [*] " ALLOWED; ALLOWED="${ALLOWED:-*}"
read -rp "Enable TLS with your cert/key? [y/N] " ans
ENABLE_TLS=0; CERT=""; KEY=""
if [[ "$ans" =~ ^[Yy]$ ]]; then
  read -rp "Path to cert (fullchain): " CERT
  read -rp "Path to key  (privkey): " KEY
  if [[ -f "$CERT" && -f "$KEY" ]]; then ENABLE_TLS=1; else echo "⚠ cert/key not found, TLS disabled."; fi
fi

# GPU
USE_GPU=0
if command -v nvidia-smi >/dev/null 2>&1; then
  read -rp "Enable NVIDIA GPU? [y/N] " g; [[ "$g" =~ ^[Yy]$ ]] && USE_GPU=1
fi

# ========= .env =========
cat > "$ENV" <<EOF
EXT_HOST=$EXT_HOST
PROXY_PORT=$PROXY_PORT
ALLOWED_ORIGINS=$ALLOWED
ENABLE_TLS=$ENABLE_TLS
TLS_CERT_PATH=$CERT
TLS_KEY_PATH=$KEY
USE_GPU=$USE_GPU
OLLAMA_PORT=11434
EOF
echo "• wrote $ENV"

# ========= docker-compose.yml =========
if [[ "$ENABLE_TLS" -eq 1 ]]; then
  MAP_PORT="      - \"\${PROXY_PORT}:8443\""
  TLS_MOUNTS="      - \${TLS_CERT_PATH}:/etc/ssl/certs/ollama.crt:ro
      - \${TLS_KEY_PATH}:/etc/ssl/private/ollama.key:ro"
else
  MAP_PORT="      - \"\${PROXY_PORT}:8080\""
  TLS_MOUNTS=""
fi

GPU_LINE=""
if [[ "$USE_GPU" -eq 1 ]]; then
  GPU_LINE="    gpus: all"
fi

cat > "$COMPOSE" <<YAML
name: ollama-secure
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    environment:
      - OLLAMA_HOST=0.0.0.0
    volumes:
      - ./data/ollama:/root/.ollama
    expose:
      - "\${OLLAMA_PORT}"
    restart: unless-stopped
    networks: [net]
$GPU_LINE

  proxy:
    image: nginx:1.25-alpine
    container_name: ollama-proxy
    depends_on: [ollama]
    ports:
$MAP_PORT
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./apikeys.conf:/etc/nginx/apikeys.conf:ro
$TLS_MOUNTS
    restart: unless-stopped
    networks: [net]

networks:
  net: { driver: bridge }
YAML
echo "• wrote $COMPOSE"

# ========= nginx.conf =========
# این کانفیگ: بدون add_header داخل if، پشتیبانی Bearer و apikey، CORS، ریت‌لیمیت،
# map برای استخراج توکن، و include فایل apikeys.conf (توکن -> یوزرنیم)
cat > "$NGINX_CONF" <<'NGINX'
worker_processes auto;
events { worker_connections 1024; }
http {
  map_hash_max_size 4096;
  map_hash_bucket_size 128;

  # combine apikey (custom header) / Authorization: Bearer
  map $http_authorization $bearer_token {
    default "";
    "~*^Bearer\s+(?<t>[^ ]+)$" $t;
  }
  map $http_apikey $api_from_header { default ""; }
  map "$api_from_header$bearer_token" $api_key_value {
    default "$api_from_header$bearer_token";
  }

  # token -> username (valid users)  | file contains:  "token" "username";
  map $api_key_value $api_user { default ""; include /etc/nginx/apikeys.conf; }

  # user -> authorized?
  map $api_user $is_auth { default 0; "" 0; ~.+ 1; }

  # rate limit
  limit_req_zone $binary_remote_addr zone=api:10m rate=20r/s;

  upstream ollama_up { server ollama:11434; }

  # ---------- HTTP ----------
  server {
    listen 8080;

    # health (no auth)
    location = /healthz { add_header Content-Type application/json; return 200 '{"ok":true}'; }

    # CORS (global)
    add_header Access-Control-Allow-Origin * always;
    add_header Access-Control-Allow-Methods "GET, POST, PUT, PATCH, DELETE, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Authorization, Content-Type, apikey" always;
    add_header Access-Control-Allow-Credentials true always;

    # OpenAI-compatible v1 (proxy as-is)
    location ^~ /v1/ {
      if ($request_method = OPTIONS) { return 204; }
      if ($is_auth = 0) {
        add_header WWW-Authenticate 'Bearer realm="ollama-secure", error="invalid_token"' always;
        return 401;
      }
      limit_req zone=api burst=40 nodelay;
      proxy_http_version 1.1;
      proxy_read_timeout 3600s;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_pass http://ollama_up;
    }

    # Native Ollama REST (/api/*) اگر خواستی مستقیم بزنی
    location ^~ /api/ {
      if ($request_method = OPTIONS) { return 204; }
      if ($is_auth = 0) {
        add_header WWW-Authenticate 'Bearer realm="ollama-secure", error="invalid_token"' always;
        return 401;
      }
      limit_req zone=api burst=40 nodelay;
      proxy_http_version 1.1;
      proxy_read_timeout 3600s;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_pass http://ollama_up;
    }

    # root check
    location = / { return 200 "Ollama is running\n"; }
  }

  # ---------- HTTPS (optional) ----------
  server {
    listen 8443 ssl;
    ssl_certificate     /etc/ssl/certs/ollama.crt;
    ssl_certificate_key /etc/ssl/private/ollama.key;

    location = /healthz { add_header Content-Type application/json; return 200 '{"ok":true}'; }

    add_header Access-Control-Allow-Origin * always;
    add_header Access-Control-Allow-Methods "GET, POST, PUT, PATCH, DELETE, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Authorization, Content-Type, apikey" always;
    add_header Access-Control-Allow-Credentials true always;

    location ^~ /v1/ {
      if ($request_method = OPTIONS) { return 204; }
      if ($is_auth = 0) {
        add_header WWW-Authenticate 'Bearer realm="ollama-secure", error="invalid_token"' always;
        return 401;
      }
      limit_req zone=api burst=40 nodelay;
      proxy_http_version 1.1; proxy_read_timeout 3600s;
      proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr;
      proxy_pass http://ollama_up;
    }

    location ^~ /api/ {
      if ($request_method = OPTIONS) { return 204; }
      if ($is_auth = 0) {
        add_header WWW-Authenticate 'Bearer realm="ollama-secure", error="invalid_token"' always;
        return 401;
      }
      limit_req zone=api burst=40 nodelay;
      proxy_http_version 1.1; proxy_read_timeout 3600s;
      proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr;
      proxy_pass http://ollama_up;
    }

    location = / { return 200 "Ollama is running (TLS)\n"; }
  }
}
NGINX
echo "• wrote $NGINX_CONF"

# ========= apikeys.conf =========
[[ -f "$APIKEYS" ]] || cat > "$APIKEYS" <<'AK'
# Format: "token" "username";
# Example:
# "secret-1234567890abcdef" "arman";
AK
echo "• ensured $APIKEYS"

echo "✅ Install finished. Next: ./start.sh"
