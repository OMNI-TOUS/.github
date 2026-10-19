def missing: "–";

def show: if . == null then missing else tostring end;

def pct: if . == null then missing else "\(.)%" end;

def lead_pair: if . == null then missing else "\(.p50) / \(.p90)" end;

def summary_rows($m; $p):
  [
    ["Issues fechadas", ($m.issues_closed | show), ($p.issues_closed | show)],
    ["PRs mergeados", ($m.prs_merged | show), ($p.prs_merged | show)],
    ["PRs com card vinculado", ($m.linked_share_pct | pct), ($p.linked_share_pct | pct)],
    ["Lead time (mediana / p90, dias)", ($m.lead_time_days.all | lead_pair), ($p.lead_time_days.all | lead_pair)],
    ["Issues abertas", ($m.open_issues | show), ($p.open_issues | show)],
    ["Abertas há mais de 30 dias", ($m.open_over_30d | show), ($p.open_over_30d | show)],
    ["Abertas há mais de 90 dias", ($m.open_over_90d | show), ($p.open_over_90d | show)],
    ["Paradas (rótulo parado)", ($m.stale | show), ($p.stale | show)],
    ["Done no board, mas abertas", ($m.done_but_open | show), ($p.done_but_open | show)],
    ["PRs aguardando revisão", ($m.prs_waiting_review | show), ($p.prs_waiting_review | show)]
  ];

def sorted_entries: to_entries | sort_by(.key);
