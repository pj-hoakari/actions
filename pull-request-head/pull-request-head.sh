#!/usr/bin/env bash
set -euo pipefail

if [ "${EVENT_NAME:-}" = "issue_comment" ]; then
  if [ "${COMMENT_IS_PULL_REQUEST:-}" != "true" ]; then
    echo "::error::プルリクエストではない Issue へのコメントです"
    exit 1
  fi
  case "${COMMENT_AUTHOR_ASSOCIATION:-}" in
    OWNER | MEMBER | COLLABORATOR) ;;
    *)
      echo "::error::コメントした人の権限が足りません（author_association: ${COMMENT_AUTHOR_ASSOCIATION:-なし}）"
      exit 1
      ;;
  esac
fi

NUMBER="${INPUT_NUMBER:-${EVENT_NUMBER:-}}"
if ! printf '%s' "$NUMBER" | grep -Eq '^[1-9][0-9]*$'; then
  echo "::error::プルリクエストの番号を決定できません: '${NUMBER}'"
  exit 1
fi

PR="$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${NUMBER}" \
  --jq '[.state, (.head.repo.full_name // ""), .head.sha, .head.ref] | @tsv')"
IFS=$'\t' read -r STATE HEAD_REPO SHA REF <<< "$PR"

if [ "$STATE" != "open" ]; then
  echo "::error::#${NUMBER} は開いていません（state: ${STATE}）"
  exit 1
fi
if [ "$HEAD_REPO" != "$GITHUB_REPOSITORY" ]; then
  echo "::error::#${NUMBER} は fork からのプルリクエストです（head: ${HEAD_REPO:-削除済み}）"
  exit 1
fi

TAG="sha-${SHA::7}"
{
  echo "number=$NUMBER"
  echo "sha=$SHA"
  echo "ref=$REF"
  echo "tag=$TAG"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"
echo "#${NUMBER}: ${REF} ${SHA} (${TAG})"
