#!/usr/bin/env bash
set -euo pipefail

SUFFIX="${INPUT_TAG_SUFFIX:-}"
if [[ ! "$SUFFIX" =~ ^[A-Za-z0-9_.-]*$ ]]; then
  echo "::error::tag-suffix must contain only Docker tag characters"
  exit 1
fi

if [ -z "${INPUT_TAGS:-}" ]; then
  # Preserve the existing metadata-action rules for callers that only supply version.
  VERSION="${INPUT_VERSION:?version is required}"
  if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    echo "::error::version must be X.Y.Z or X.Y.Z-prerelease"
    exit 1
  fi
  LATEST=true
  case "$VERSION" in *-*) LATEST=false ;; esac
  RULES="type=semver,pattern={{version}},value=$VERSION
type=sha
type=raw,value=latest,enable=$LATEST"
  AUTO_LATEST=auto
else
  # Use exactly the resolved tags; metadata-action must not add its own latest tag.
  if [[ ! "$INPUT_TAGS" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*(,[A-Za-z0-9_][A-Za-z0-9_.-]*)*$ ]]; then
    echo "::error::tags must be a comma-separated list of non-empty Docker tags"
    exit 1
  fi
  IFS=',' read -r -a TAGS <<< "$INPUT_TAGS"
  RULES=""
  for TAG in "${TAGS[@]}"; do
    FINAL_TAG="$TAG$SUFFIX"
    if [[ ! "$TAG" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || [ "${#FINAL_TAG}" -gt 128 ]; then
      echo "::error::tags must be valid Docker tags and fit within 128 characters after suffixing"
      exit 1
    fi
    RULES="${RULES}type=raw,value=$TAG
"
  done
  AUTO_LATEST=false
fi

{
  echo "latest=$AUTO_LATEST"
  echo 'tags<<METADATA_TAG_RULES'
  printf '%s\n' "$RULES"
  echo METADATA_TAG_RULES
} >> "${GITHUB_OUTPUT:-/dev/stdout}"
