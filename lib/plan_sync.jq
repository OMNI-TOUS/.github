include "common";

def add_item($config): {type: "add_item", content_id: .id, produto: $config.produto_by_repo[.repo]};

def issue_actions($config):
  (if on_board($config.project) then empty else add_item($config) end),
  (if days_between(.updatedAt; $config.now) > $config.stale_days and (has_label($config.stale_label) | not)
   then {type: "add_label", repo, number, label: $config.stale_label}
   else empty end);

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
