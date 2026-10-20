# shellcheck shell=bash

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ORG="OMNI-TOUS"
PROJECT_NUMBER="${PROJECT_NUMBER:-1}"
DRY_RUN="${DRY_RUN:-true}"

CARD_LINK_CONTEXT="card-link"
SKIP_LABEL="sem-card"
STALE_LABEL="parado"
PRIORITY_FIELD="Priority"
STALE_DAYS=60
REVIEW_WAIT_DAYS=2
STUCK_DAYS=14
ACTION_LIST_SIZE=5
SEARCH_PAGE_SIZE=50
LABEL_EVENTS_LIMIT=20
LINKED_PRS_LIMIT=10
GUIDE_URL="https://github.com/$ORG/.github/blob/main/docs/guia-do-board.md"
BOARD_URL="https://github.com/orgs/$ORG/projects/$PROJECT_NUMBER"

PROJECT_ITEM_FIELDS='projectItems(first: 10) { nodes {
  id
  project { number }
  status: fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { name updatedAt } }
  priority: fieldValueByName(name: "Priority") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
  cliente: fieldValueByName(name: "Cliente") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
} }'

ISSUE_FIELDS="... on Issue {
  id number title url body createdAt updatedAt closedAt
  repository { name }
  assignees { totalCount }
  labels(first: 20) { nodes { name } }
  timelineItems(itemTypes: [LABELED_EVENT], last: $LABEL_EVENTS_LIMIT) { nodes { ... on LabeledEvent { createdAt label { name } } } }
  closedByPullRequestsReferences(first: $LINKED_PRS_LIMIT, includeClosedPrs: true) { nodes { updatedAt } }
  $PROJECT_ITEM_FIELDS
}"

PR_FIELDS="... on PullRequest {
  id number title url createdAt mergedAt headRefOid
  repository { name }
  labels(first: 20) { nodes { name } }
  closingIssuesReferences { totalCount }
  reviews { totalCount }
  $PROJECT_ITEM_FIELDS
}"

run_jq() {
  local filter="$1"
  shift
  jq -L "$ROOT/lib" -f "$ROOT/lib/$filter.jq" "$@"
}

search_nodes() {
  local query="$1" fields="$2"
  gh api graphql --paginate \
    -f q="$query" \
    -f query="query(\$q: String!, \$endCursor: String) {
      search(query: \$q, type: ISSUE, first: $SEARCH_PAGE_SIZE, after: \$endCursor) {
        pageInfo { hasNextPage endCursor }
        nodes { $fields }
      }
    }" \
    --jq '.data.search.nodes[]' | jq -s .
}

is_dry_run() {
  [ "$DRY_RUN" = "true" ]
}

short_error() {
  grep -oE 'HTTP [0-9]{3}[^(]*' | head -1 || echo "unknown error"
}

days_ago() {
  jq -rn --argjson days "$1" 'now - $days * 86400 | strftime("%Y-%m-%d")'
}

now_iso() {
  jq -rn 'now | strftime("%Y-%m-%dT%H:%M:%SZ")'
}

load_project_fields() {
  gh api graphql -F number="$1" -f org="$ORG" -f query='
    query($org: String!, $number: Int!) {
      organization(login: $org) { projectV2(number: $number) {
        id
        fields(first: 50) { nodes {
          ... on ProjectV2FieldCommon { id name dataType }
          ... on ProjectV2SingleSelectField { options { id name } }
        } }
      } }
    }' --jq '.data.organization.projectV2 | {id, fields: .fields.nodes}'
}

field_id() {
  jq -r --arg name "$2" '.fields[] | select(.name == $name) | .id' "$1"
}

option_id() {
  jq -r --arg name "$2" --arg option "$3" \
    '.fields[] | select(.name == $name) | .options[]? | select(.name == $option) | .id' "$1"
}

add_to_project() {
  local project_file="$1" content_id="$2"
  gh api graphql -f project="$(jq -r .id "$project_file")" -f content="$content_id" -f query='
    mutation($project: ID!, $content: ID!) {
      addProjectV2ItemById(input: {projectId: $project, contentId: $content}) { item { id } }
    }' --jq '.data.addProjectV2ItemById.item.id'
}

set_field_value() {
  local project_file="$1" item_id="$2" field_name="$3" value="$4" field
  field="$(field_id "$project_file" "$field_name")"
  [ -n "$field" ] || return 0
  jq -n --arg project "$(jq -r .id "$project_file")" --arg item "$item_id" --arg field "$field" \
    --argjson value "$value" '{
      query: "mutation($project: ID!, $item: ID!, $field: ID!, $value: ProjectV2FieldValue!) { updateProjectV2ItemFieldValue(input: {projectId: $project, itemId: $item, fieldId: $field, value: $value}) { clientMutationId } }",
      variables: {project: $project, item: $item, field: $field, value: $value}
    }' | gh api graphql --input - > /dev/null
}

set_option() {
  local project_file="$1" item_id="$2" field_name="$3" option_name="$4" option
  [ -n "$option_name" ] || return 0
  option="$(option_id "$project_file" "$field_name" "$option_name")"
  [ -n "$option" ] || return 0
  set_field_value "$project_file" "$item_id" "$field_name" "$(jq -cn --arg id "$option" '{singleSelectOptionId: $id}')"
}

set_text() {
  local project_file="$1" item_id="$2" field_name="$3" text="$4"
  [ -n "$text" ] || return 0
  set_field_value "$project_file" "$item_id" "$field_name" "$(jq -cn --arg text "$text" '{text: $text}')"
}
