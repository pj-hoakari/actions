#!/usr/bin/env bash
set -euo pipefail

RAW="${INPUT_VERSION:-}"
if [ -z "$RAW" ] && [ "${GITHUB_REF_TYPE:-}" = "tag" ]; then
  RAW="$GITHUB_REF_NAME"
fi
if [ -z "$RAW" ]; then
  echo "::error::バージョンを決定できません（workflow_dispatch ではタグを選ぶか version 入力が必要です）"
  exit 1
fi

VERSION="${RAW#v}"
SEMVER='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'
if ! printf '%s' "$VERSION" | grep -Eq "$SEMVER"; then
  echo "::error::想定外のタグ/バージョン形式: '${RAW}'（vX.Y.Z または vX.Y.Z-suffix。例: v0.1.0, v0.1.0-rc）"
  exit 1
fi

SHA="${GITHUB_SHA:-$(git rev-parse HEAD)}"
TAG="v$VERSION"
TAG_SHA="$(git ls-remote origin "refs/tags/$TAG" "refs/tags/$TAG^{}" | tail -n 1 | cut -f 1)"
if [ -z "$TAG_SHA" ]; then
  echo "::error::タグ ${TAG} がリモートにありません（task release でタグとリリースを作成してください）"
  exit 1
fi
if [ "$TAG_SHA" != "$SHA" ]; then
  echo "::error::タグ ${TAG} (${TAG_SHA}) が実行中のコミット (${SHA}) を指していません（workflow_dispatch ではタグを選んで実行してください）"
  exit 1
fi

LATEST="$(git ls-remote --tags --refs origin 'refs/tags/v*' \
  | sed 's|.*refs/tags/v||' | grep -E "$SEMVER" \
  | sed 's/-/~/' | sort -V | tail -n 1 | sed 's/~/-/')"
if [ "$LATEST" != "$VERSION" ]; then
  echo "::error::${TAG} は最新のバージョンではありません（最新: v${LATEST}）"
  exit 1
fi

TAGS="$VERSION,sha-${SHA::7}"
case "$VERSION" in
  *-*) ;;
  *) TAGS="$TAGS,latest" ;;
esac

{
  echo "version=$VERSION"
  echo "tags=$TAGS"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"
echo "version: $VERSION (tags: $TAGS)"
