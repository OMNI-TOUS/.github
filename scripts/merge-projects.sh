#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

SOURCE_PROJECT="${SOURCE_PROJECT:-4}"
TARGET_PROJECT="${TARGET_PROJECT:-$PROJECT_NUMBER}"
PRIORITY_MAP='{"P0": "urgente", "P1": "normal", "P2": "baixa"}'
ITEMS_PAGE_SIZE=100

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

project_items() {
  gh api graphql --paginate -F number="$1" -f org="$ORG" -f query="
    query(\$org: String!, \$number: Int!, \$endCursor: String) {
      organization(login: \$org) { projectV2(number: \$number) {
        items(first: $ITEMS_PAGE_SIZE, after: \$endCursor) {
          pageInfo { hasNextPage endCursor }
          nodes {
            type
            content {
              ... on Issue { id repository { name } }
              ... on PullRequest { id repository { name } }
            }
            status: fieldValueByName(name: \"Status\") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
            priority: fieldValueByName(name: \"Priority\") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
            jira1: fieldValueByName(name: \"Card Jira\") { ... on ProjectV2ItemFieldTextValue { text } }
            jira2: fieldValueByName(name: \"Card Jira (2)\") { ... on ProjectV2ItemFieldTextValue { text } }
            jira3: fieldValueByName(name: \"Card Jira (3)\") { ... on ProjectV2ItemFieldTextValue { text } }
          }
        }
      } }
    }" --jq '.data.organization.projectV2.items.nodes[]' | jq -s .
}

flatten_items() {
  jq 'map({
    content_id: .content.id,
    type,
    repo: .content.repository.name,
    status: .status.name,
    priority: .priority.name,
    card_jira: [.jira1.text, .jira2.text, .jira3.text]
  })' "$1"
}

plan() {
  project_items "$SOURCE_PROJECT" > "$WORK/source_raw.json"
  project_items "$TARGET_PROJECT" > "$WORK/target_raw.json"
  flatten_items "$WORK/source_raw.json" > "$WORK/source.json"
  jq -n --argjson priority_map "$PRIORITY_MAP" \
    --slurpfile produto "$ROOT/config/produto-por-repo.json" \
    --slurpfile source "$WORK/source.json" --slurpfile target "$WORK/target_raw.json" \
    '{
      config: {priority_map: $priority_map, produto_by_repo: $produto[0]},
      target_content_ids: [$target[0][].content.id | select(. != null)],
      source_items: $source[0]
    }' | run_jq plan_merge > "$WORK/plan.json"
}

copy_item() {
  local project="$WORK/target.json" item_id
  item_id="$(add_to_project "$project" "$(jq -r .content_id <<<"$1")")"
  set_option "$project" "$item_id" "Status" "$(jq -r '.status // empty' <<<"$1")"
  set_option "$project" "$item_id" "Priority" "$(jq -r '.priority // empty' <<<"$1")"
  set_option "$project" "$item_id" "Produto" "$(jq -r '.produto // empty' <<<"$1")"
  set_text "$project" "$item_id" "Card Jira" "$(jq -r '.card_jira // empty' <<<"$1")"
}

load_project_fields "$TARGET_PROJECT" > "$WORK/target.json"
plan

jq -r '"to copy: \(.copy | length), already on target: \(.already_on_target), drafts skipped: \(.skipped_drafts)"' "$WORK/plan.json"

if is_dry_run; then
  echo "dry run: no changes made"
  exit 0
fi
jq -e '[.fields[].name] | index("Card Jira") and index("Produto")' "$WORK/target.json" > /dev/null \
  || { echo "target project needs the Produto and Card Jira fields: run scripts/setup-project.sh first" >&2; exit 1; }

failures=0
while IFS= read -r item; do
  if ! error="$(copy_item "$item" 2>&1)"; then
    echo "failed: copy ($(short_error <<<"$error"))"
    failures=$((failures + 1))
  fi
done < <(jq -c '.copy[]' "$WORK/plan.json")
echo "failures: $failures"
[ "$failures" -eq 0 ]
