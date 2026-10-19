#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

LABELS_FILE="$ROOT/config/labels.json"
DEFAULT_LABELS='["bug", "documentation", "duplicate", "enhancement", "good first issue", "help wanted", "invalid", "question", "wontfix"]'
REPO_LIMIT=200
PRUNE=false

[ "${1:-}" = "--prune" ] && PRUNE=true

repos() {
  gh repo list "$ORG" --no-archived --limit "$REPO_LIMIT" --json name --jq '.[].name'
}

label_in_use() {
  local query
  query="$(jq -rn --arg q "repo:$ORG/$1 label:\"$2\"" '$q | @uri')"
  [ "$(gh api "search/issues?q=$query" --jq .total_count)" -gt 0 ]
}

unused_default_labels() {
  local repo="$1" name
  while IFS= read -r name; do
    label_in_use "$repo" "$name" || echo "$name"
  done < <(gh label list -R "$ORG/$repo" --limit "$REPO_LIMIT" --json name \
    | jq -r --argjson defaults "$DEFAULT_LABELS" '.[].name | select(IN($defaults[]))')
}

sync_repo() {
  local repo="$1" label
  while IFS= read -r label; do
    gh label create "$(jq -r .name <<<"$label")" -R "$ORG/$repo" --force \
      --color "$(jq -r .color <<<"$label")" --description "$(jq -r .description <<<"$label")" > /dev/null
  done < <(jq -c '.[]' "$LABELS_FILE")
}

prune_repo() {
  local repo="$1" name
  while IFS= read -r name; do
    gh label delete "$name" -R "$ORG/$repo" --yes > /dev/null
  done < <(unused_default_labels "$repo")
}

count=0
while IFS= read -r repo; do
  count=$((count + 1))
  is_dry_run && continue
  sync_repo "$repo"
  if [ "$PRUNE" = true ]; then prune_repo "$repo"; fi
done < <(repos)

echo "repos: $count, labels per repo: $(jq length "$LABELS_FILE"), prune: $PRUNE"
if is_dry_run; then echo "dry run: no changes made"; fi
