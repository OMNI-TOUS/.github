def project_items:
  [.projectItems.nodes[] | {
    project: .project.number,
    item_id: .id,
    status: .status.name,
    priority: .priority.name,
    cliente: .cliente.name
  }];

def labels: [.labels.nodes[].name];

def labeled_at: reduce (.timelineItems.nodes[] | select(.label)) as $event ({}; .[$event.label.name] = $event.createdAt);

def linked_pr_updates: [.closedByPullRequestsReferences.nodes[].updatedAt];

def issue:
  {
    id, number, createdAt, updatedAt, closedAt,
    repo: .repository.name,
    labels: labels,
    labeled_at: labeled_at,
    linked_pr_updates: linked_pr_updates,
    project_items: project_items
  };

def card_link_state($context):
  first(.statuses[]? | select(.context == $context) | .state | ascii_upcase) // null;

def pr($context):
  {
    id, number, createdAt, mergedAt,
    repo: .repository.name,
    sha: .headRefOid,
    labels: labels,
    linked: (.closingIssuesReferences.totalCount > 0),
    reviews: .reviews.totalCount,
    card_link_state: card_link_state($context),
    project_items: project_items
  };

.context as $context
| {
    issues: [.issues[] | issue],
    prs: [.prs[] | pr($context)]
  }
