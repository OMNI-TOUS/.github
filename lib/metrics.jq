include "common";

def no_cliente: "(sem cliente)";

def nearest_rank($p): .[((length * $p) | ceil) - 1];

def lead_stats:
  if length == 0 then null
  else sort | {n: length, p50: nearest_rank(0.5), p90: nearest_rank(0.9)}
  end;

def stats_by(f): group_by(f) | map({key: (.[0] | f), value: (map(.days) | lead_stats)}) | from_entries;

.config as $config
| def age: days_between(.createdAt; $config.now);
  def board_field($name): board_item($config.project)[$name] // null;
  [.closed_issues[] | {
    repo,
    cliente: (board_field("cliente") // no_cliente),
    days: (days_between(.createdAt; .closedAt) | floor)
  }] as $lead
| {
    issues_closed: (.closed_issues | length),
    prs_merged: (.merged_prs | length),
    lead_time_days: {
      all: ($lead | map(.days) | lead_stats),
      by_repo: ($lead | stats_by(.repo)),
      by_cliente: ($lead | stats_by(.cliente))
    },
    open_issues: (.open_issues | length),
    stale: ([.open_issues[] | select(has_label($config.stale_label))] | length),
    done_but_open: ([.open_issues[] | select(board_field("status") == "Done")] | length),
    sla_breaches: ([.open_issues[]
        | board_field("priority") as $priority
        | select($priority != null and $config.sla_days[$priority] != null and age > $config.sla_days[$priority])
        | $priority]
      | group_by(.) | map({key: .[0], value: length}) | from_entries),
    prs_waiting_review: ([.open_prs[] | select(.reviews == 0 and age > $config.review_wait_days)] | length),
    linked_share_pct: (if (.merged_prs | length) == 0 then null
      else ([.merged_prs[] | select(.linked)] | length) * 100 / (.merged_prs | length) | round end)
  }
