#!/usr/bin/env bash
set -euo pipefail

if ! printf '%s' "${SHA:-}" | grep -Eq '^[0-9a-f]{40}$'; then
  echo "::error::コミットの SHA が不正です: '${SHA:-}'"
  exit 1
fi

TAGS="type=raw,value=sha-${SHA::7}"
if [ -n "${VERSION:-}" ]; then
  TAGS="$TAGS"$'\n'"type=raw,value=${VERSION}"
  case "$VERSION" in
    *-*) ;;
    *) TAGS="$TAGS"$'\n'"type=raw,value=latest" ;;
  esac
fi

{
  echo "tags<<EOF"
  echo "$TAGS"
  echo "EOF"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"
echo "$TAGS"
