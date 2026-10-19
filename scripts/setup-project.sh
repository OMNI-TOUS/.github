#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PRODUTO_OPTIONS_FILE="$ROOT/config/produto-por-repo.json"
TAMANHO_OPTIONS='["P", "M", "G"]'
CLIENTE_OPTIONS='["Prodesp"]'
TEXT_FIELDS='["Card Jira"]'
DATE_FIELDS='["Início", "Previsão"]'
OPTION_COLOR="GRAY"

desired_fields() {
  jq -n --slurpfile produto "$PRODUTO_OPTIONS_FILE" --argjson tamanho "$TAMANHO_OPTIONS" --argjson cliente "$CLIENTE_OPTIONS" \
    --argjson text "$TEXT_FIELDS" --argjson date "$DATE_FIELDS" '
    [{name: "Produto", dataType: "SINGLE_SELECT", options: ($produto[0] | [.[]] | unique)},
     {name: "Tamanho", dataType: "SINGLE_SELECT", options: $tamanho},
     {name: "Cliente", dataType: "SINGLE_SELECT", options: $cliente}]
    + ($text | map({name: ., dataType: "TEXT"}))
    + ($date | map({name: ., dataType: "DATE"}))'
}

missing_fields() {
  jq --slurpfile existing "$WORK/project.json" \
    '[.[] | select(.name | IN($existing[0].fields[].name) | not)]' "$WORK/desired.json"
}

create_field() {
  jq --arg project "$(jq -r .id "$WORK/project.json")" --arg color "$OPTION_COLOR" '{
    query: "mutation($input: CreateProjectV2FieldInput!) { createProjectV2Field(input: $input) { clientMutationId } }",
    variables: {input: ({projectId: $project, name, dataType}
      + if .options then {singleSelectOptions: (.options | map({name: ., color: $color, description: ""}))} else {} end)}
  }' <<<"$1" | gh api graphql --input - > /dev/null
}

load_project_fields "$PROJECT_NUMBER" > "$WORK/project.json"
desired_fields > "$WORK/desired.json"
missing_fields > "$WORK/missing.json"

jq -r '"fields to create: \(length)", (.[] | "  \(.name) (\(.dataType))")' "$WORK/missing.json"

if is_dry_run; then
  echo "dry run: no changes made"
  exit 0
fi

while IFS= read -r field; do
  create_field "$field"
  echo "created: $(jq -r .name <<<"$field")"
done < <(jq -c '.[]' "$WORK/missing.json")
