#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API="$ROOT/apikeys.conf"

read -rp "Username label for this key: " USER
if command -v openssl >/dev/null 2>&1; then
  RAND="$(openssl rand -hex 16)"
else
  RAND="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
fi
KEY="secret-$RAND"
echo "\"$KEY\" \"$USER\";" >> "$API"
echo "• Added to apikeys.conf: $USER"
echo "$KEY"
