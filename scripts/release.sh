#!/usr/bin/env bash
set -euo pipefail

DATE="$(TZ=Asia/Tokyo date +%Y%m%d)"
LAST="$(git ls-remote --tags --refs origin "refs/tags/v${DATE}.0.*" \
  | sed "s|.*refs/tags/v${DATE}\.0\.||" | grep -E '^[0-9]+$' \
  | sort -n | tail -n 1 || true)"
TAG="v${DATE}.0.$((${LAST:--1} + 1))"

if [ "${DRY_RUN:-}" = "1" ]; then
  echo "$TAG"
  exit 0
fi

gh release create "$TAG" --target main --title "$TAG" --generate-notes
