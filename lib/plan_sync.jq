include "common";

def known_form_priority($config):
  .form_priority as $priority
  | if $priority != null and ($config.priority_options | index($priority)) != null then $priority else null end;

def add_item($config):
  {type: "add_item", content_id: .id, produto: $config.produto_by_repo[.repo], priority: known_form_priority($config)};

def priority_action($config):
  board_item($config.project) as $item
  | known_form_priority($config) as $priority
  | if $item != null and $item.priority == null and $priority != null
    then {type: "set_priority", item_id: $item.item_id, priority: $priority}
    else empty end;

def label_grace_seconds: 60;

def last_activity: [.updatedAt] + .linked_pr_updates | max;

def stale($config): days_between(last_activity; $config.now) > $config.stale_days;

def active_after_label($label):
  .labeled_at[$label] as $at
  | $at != null
    and (((.updatedAt | fromdate) - ($at | fromdate) > label_grace_seconds)
         or any(.linked_pr_updates[]; . > $at));

def stale_label_action($config):
  if has_label($config.stale_label) then
    (if active_after_label($config.stale_label) then {type: "remove_label", repo, number, label: $config.stale_label} else empty end)
  elif stale($config) then {type: "add_label", repo, number, label: $config.stale_label}
  else empty end;

def issue_actions($config):
  (if on_board($config.project) then empty else add_item($config) end),
  stale_label_action($config),
  priority_action($config);

def pr_actions($config):
  ((.linked or has_label($config.skip_label)) as $ok
   | (if $ok then "success" else "failure" end) as $state
   | (if ($state | ascii_upcase) != .card_link_state
      then {type: "set_status", repo, sha, state: $state}
      else empty end),
     (if .linked then
        (board_item($config.project) | if . then {type: "remove_item", item_id} else empty end)
      elif $ok or on_board($config.project) then empty
      else add_item($config) end));

.config as $config
| [(.issues[] | issue_actions($config)), (.prs[] | pr_actions($config))]
