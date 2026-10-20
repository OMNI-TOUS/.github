include "common";

def no_cliente: "(sem cliente)";

def nearest_rank($p): .[((length * $p) | ceil) - 1];

def lead_stats:
  if length == 0 then null
  else sort | {n: length, p50: nearest_rank(0.5), p90: nearest_rank(0.9)}
  end;

def stuck_statuses: ["In progress", "In review"];

def blocked_status: "Bloqueado";

def action_item($days): {ref: "\(.repo)#\(.number)", url, title, days: ($days | floor)};

def action_list($size): sort_by(-.days) | {total: length, items: .[:$size]};

def stats_by(f): group_by(f) | map({key: (.[0] | f), value: (map(.days) | lead_stats)}) | from_entries;

.config as $config
| def age: days_between(.createdAt; $config.now);
  def board_field($name): board_item($config.project)[$name] // null;
  def status_age: days_between(board_field("status_since"); $config.now);
  def has_status($statuses): board_field("status") as $status | $statuses | index($status) != null;
  def all_sub_issues_done: (.sub_issues.total // 0) > 0 and .sub_issues.completed == .sub_issues.total;
  def waiting_review: .reviews == 0 and age > $config.review_wait_days;
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
    prs_waiting_review: ([.open_prs[] | select(waiting_review)] | length),
    linked_share_pct: (if (.merged_prs | length) == 0 then null
      else ([.merged_prs[] | select(.linked)] | length) * 100 / (.merged_prs | length) | round end),
    actions: {
      stuck: ([.open_issues[]
          | select(has_status(stuck_statuses) and board_field("status_since") != null and status_age > $config.stuck_days)
          | action_item(status_age)] | action_list($config.action_list_size)),
      prs_waiting_review: ([.open_prs[] | select(waiting_review) | action_item(age)] | action_list($config.action_list_size)),
      unowned: ([.open_issues[]
          | select(days_between($config.from; .createdAt) >= 0 and (.assignees == 0 or board_field("priority") == null))
          | action_item(age)] | action_list($config.action_list_size)),
      blocked: ([.open_issues[]
          | select(has_status([blocked_status]) and board_field("status_since") != null)
          | action_item(status_age)] | action_list($config.action_list_size)),
      sub_issues_done: ([.open_issues[]
          | select(all_sub_issues_done)
          | action_item(days_between(.sub_issues.last_closed_at; $config.now))] | action_list($config.action_list_size))
    }
  }
