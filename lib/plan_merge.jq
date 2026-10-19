def draft: .type == "DRAFT_ISSUE";

def open: .state == "OPEN";

def first_filled: first(.[] | select(. != null and . != "")) // null;

.config as $config
| .target_content_ids as $on_target
| [.source_items[] | select(draft | not)] as $content
| [$content[] | select(open)] as $open
| [$open[] | select(.content_id | IN($on_target[]) | not)] as $to_copy
| {
    copy: $to_copy | map({
      content_id,
      status,
      priority: $config.priority_map[.priority // ""],
      card_jira: (.card_jira | first_filled),
      produto: $config.produto_by_repo[.repo // ""]
    }),
    already_on_target: (($open | length) - ($to_copy | length)),
    skipped_closed: (($content | length) - ($open | length)),
    skipped_drafts: ([.source_items[] | select(draft)] | length)
  }
