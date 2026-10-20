#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

STATUS_OK="Card vinculado"
STATUS_MISSING="Sem card: use 'Closes $ORG/<repo>#<n>' ou o rótulo $SKIP_LABEL"

load_project() {
  load_project_fields "$PROJECT_NUMBER" > "$WORK/project.json"
}

priority_options() {
  jq -c --arg name "$PRIORITY_FIELD" '[.fields[] | select(.name == $name) | .options[].name]' "$WORK/project.json"
}

project_id() {
  jq -r .id "$WORK/project.json"
}

commit_statuses() {
  gh api "repos/$ORG/$1/commits/$2/status" --jq '[.statuses[] | {context, state}]'
}

with_statuses() {
  local pr repo sha
  while read -r pr; do
    repo="$(jq -r .repository.name <<<"$pr")"
    sha="$(jq -r .headRefOid <<<"$pr")"
    jq --argjson statuses "$(commit_statuses "$repo" "$sha")" '. + {statuses: $statuses}' <<<"$pr"
  done < <(jq -c '.[]' "$1") | jq -s .
}

collect() {
  search_nodes "org:$ORG is:issue is:open archived:false" "$ISSUE_FIELDS" > "$WORK/issues.json"
  search_nodes "org:$ORG is:pr is:open archived:false" "$PR_FIELDS" > "$WORK/prs_raw.json"
  with_statuses "$WORK/prs_raw.json" > "$WORK/prs.json"
  jq -n --arg context "$CARD_LINK_CONTEXT" \
    --slurpfile issues "$WORK/issues.json" --slurpfile prs "$WORK/prs.json" \
    '{context: $context, issues: $issues[0], prs: $prs[0]}' > "$WORK/raw.json"
  run_jq normalize_search "$WORK/raw.json" > "$WORK/normalized.json"
}

plan() {
  jq --argjson project "$PROJECT_NUMBER" --arg now "$(now_iso)" \
    --argjson stale_days "$STALE_DAYS" --arg stale_label "$STALE_LABEL" --arg skip_label "$SKIP_LABEL" \
    --slurpfile produto "$ROOT/config/produto-por-repo.json" \
    --argjson priority_options "$(priority_options)" \
    '. + {config: {project: $project, now: $now, stale_days: $stale_days, stale_label: $stale_label,
                   skip_label: $skip_label, produto_by_repo: $produto[0], priority_options: $priority_options}}' \
    "$WORK/normalized.json" | run_jq plan_sync > "$WORK/actions.json"
}

add_item() {
  local item_id
  item_id="$(add_to_project "$WORK/project.json" "$(jq -r .content_id <<<"$1")")"
  set_option "$WORK/project.json" "$item_id" "Produto" "$(jq -r '.produto // empty' <<<"$1")"
  set_option "$WORK/project.json" "$item_id" "$PRIORITY_FIELD" "$(jq -r '.priority // empty' <<<"$1")"
}

set_priority() {
  set_option "$WORK/project.json" "$(jq -r .item_id <<<"$1")" "$PRIORITY_FIELD" "$(jq -r .priority <<<"$1")"
}

remove_item() {
  gh api graphql -f project="$(project_id)" -f item="$(jq -r .item_id <<<"$1")" -f query='
    mutation($project: ID!, $item: ID!) {
      deleteProjectV2Item(input: {projectId: $project, itemId: $item}) { deletedItemId }
    }' > /dev/null
}

add_label() {
  gh api -X POST "repos/$ORG/$(jq -r .repo <<<"$1")/issues/$(jq -r .number <<<"$1")/labels" \
    -f "labels[]=$(jq -r .label <<<"$1")" > /dev/null
}

remove_label() {
  gh api -X DELETE "repos/$ORG/$(jq -r .repo <<<"$1")/issues/$(jq -r .number <<<"$1")/labels/$(jq -r .label <<<"$1")" > /dev/null
}

set_status() {
  local state description="$STATUS_MISSING"
  state="$(jq -r .state <<<"$1")"
  [ "$state" = "success" ] && description="$STATUS_OK"
  gh api -X POST "repos/$ORG/$(jq -r .repo <<<"$1")/statuses/$(jq -r .sha <<<"$1")" \
    -f state="$state" -f context="$CARD_LINK_CONTEXT" -f description="$description" \
    -f target_url="$GUIDE_URL" > /dev/null
}

apply() {
  local failures=0 action type error
  while IFS= read -r action; do
    type="$(jq -r .type <<<"$action")"
    if ! error="$("$type" "$action" 2>&1)"; then
      echo "failed: $type ($(short_error <<<"$error"))"
      failures=$((failures + 1))
    fi
  done < <(jq -c '.[]' "$WORK/actions.json")
  echo "failures: $failures"
  [ "$failures" -eq 0 ]
}

load_project
collect
plan

echo "open issues: $(jq '.issues | length' "$WORK/normalized.json"), open PRs: $(jq '.prs | length' "$WORK/normalized.json")"
jq -r 'group_by(.type)[] | "\(.[0].type): \(length)"' "$WORK/actions.json"

if is_dry_run; then
  echo "dry run: no changes made"
  exit 0
fi
apply
