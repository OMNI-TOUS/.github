#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
  echo "usage: $0 weekly|monthly" >&2
  exit 2
}

[ $# -eq 1 ] || usage
KIND="$1"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

WEEK_DAYS=7
MONTHLY_LABEL="relatorio-mensal"
METRICS_MARKER="<!-- metrics:"
REPORT_REPO="${REPORT_REPO:-}"
SLA_DAYS="${SLA_DAYS:-"{}"}"
TEAMS_WEBHOOK_URL="${TEAMS_WEBHOOK_URL:-}"

case "$KIND" in
  weekly)
    FROM="$(days_ago "$WEEK_DAYS")"
    TO="$(days_ago 0)"
    TITLE="Resumo semanal"
    ;;
  monthly)
    TO="$(jq -rn 'now | gmtime | .[2] = 1 | mktime - 86400 | strftime("%Y-%m-%d")')"
    FROM="$(jq -rn --arg to "$TO" '$to | strptime("%Y-%m-%d") | .[2] = 1 | mktime | strftime("%Y-%m-%d")')"
    TITLE="Relatório mensal ${FROM:0:7}"
    ;;
  *) usage ;;
esac

normalize() {
  jq -n --arg context "$CARD_LINK_CONTEXT" --slurpfile issues "$1" --slurpfile prs "$2" \
    '{context: $context, issues: $issues[0], prs: $prs[0]}' | run_jq normalize_search
}

collect() {
  search_nodes "org:$ORG is:issue is:closed reason:completed closed:$FROM..$TO" "$ISSUE_FIELDS" > "$WORK/closed.json"
  search_nodes "org:$ORG is:pr is:merged merged:$FROM..$TO" "$PR_FIELDS" > "$WORK/merged.json"
  search_nodes "org:$ORG is:issue is:open archived:false" "$ISSUE_FIELDS" > "$WORK/open_issues.json"
  search_nodes "org:$ORG is:pr is:open draft:false archived:false" "$PR_FIELDS" > "$WORK/open_prs.json"
  normalize "$WORK/closed.json" "$WORK/merged.json" > "$WORK/period.json"
  normalize "$WORK/open_issues.json" "$WORK/open_prs.json" > "$WORK/snapshot.json"
}

compute_metrics() {
  jq -n --argjson project "$PROJECT_NUMBER" --arg now "$(now_iso)" --arg stale_label "$STALE_LABEL" \
    --argjson review_wait_days "$REVIEW_WAIT_DAYS" --argjson sla_days "$SLA_DAYS" \
    --slurpfile period "$WORK/period.json" --slurpfile snapshot "$WORK/snapshot.json" \
    '{
      config: {project: $project, now: $now, stale_label: $stale_label,
               review_wait_days: $review_wait_days, sla_days: $sla_days},
      closed_issues: $period[0].issues,
      merged_prs: $period[0].prs,
      open_issues: $snapshot[0].issues,
      open_prs: $snapshot[0].prs
    }' | run_jq metrics > "$WORK/metrics.json"
}

previous_metrics() {
  if [ "$KIND" != "monthly" ] || [ -z "$REPORT_REPO" ]; then
    echo null
    return
  fi
  gh issue list -R "$ORG/$REPORT_REPO" --label "$MONTHLY_LABEL" --state all --limit 1 --json body --jq '.[0].body // ""' \
    | sed -n "s/^$METRICS_MARKER \(.*\) -->$/\1/p" | grep . || echo null
}

render() {
  jq -n --arg title "$TITLE" --arg from "$FROM" --arg to "$TO" --arg board_url "$BOARD_URL" \
    --slurpfile metrics "$WORK/metrics.json" --argjson previous "$(previous_metrics)" \
    '{title: $title, from: $from, to: $to, board_url: $board_url, metrics: $metrics[0], previous: $previous}' \
    > "$WORK/report_input.json"
  run_jq format_report -r "$WORK/report_input.json" > "$WORK/report.md"
  run_jq format_teams "$WORK/report_input.json" > "$WORK/teams.json"
}

post_teams() {
  [ -n "$TEAMS_WEBHOOK_URL" ] || { echo "teams: skipped (no webhook)"; return; }
  curl -fsS -X POST -H "Content-Type: application/json" --data @"$WORK/teams.json" "$TEAMS_WEBHOOK_URL" > /dev/null
  echo "teams: posted"
}

open_monthly_issue() {
  [ "$KIND" = "monthly" ] || return 0
  [ -n "$REPORT_REPO" ] || { echo "monthly issue: skipped (no REPORT_REPO)"; return; }
  printf '\n\n%s %s -->\n' "$METRICS_MARKER" "$(jq -c . "$WORK/metrics.json")" >> "$WORK/report.md"
  gh label create "$MONTHLY_LABEL" -R "$ORG/$REPORT_REPO" --force > /dev/null
  gh issue create -R "$ORG/$REPORT_REPO" --title "$TITLE" --label "$MONTHLY_LABEL" --body-file "$WORK/report.md" > /dev/null
  echo "monthly issue: created"
}

collect
compute_metrics
render

if [ "${SHOW_REPORT:-false}" = true ] && is_dry_run; then
  cat "$WORK/report.md"
fi
echo "report: $(wc -c < "$WORK/report.md" | tr -d ' ') bytes"

if is_dry_run; then
  echo "dry run: nothing posted"
  exit 0
fi
post_teams
open_monthly_issue
