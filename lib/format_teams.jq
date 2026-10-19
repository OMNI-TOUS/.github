include "report_rows";

def heading($text): {type: "TextBlock", text: $text, weight: "Bolder"};

def facts($pairs):
  if ($pairs | length) == 0 then {type: "TextBlock", text: "Nenhum."}
  else {type: "FactSet", facts: $pairs | map({title: .[0], value: .[1]})}
  end;

def with_previous($has_previous):
  if $has_previous then [.[0], "\(.[1]) (anterior: \(.[2]))"] else [.[0], .[1]] end;

.metrics as $m
| (.previous != null) as $has_previous
| {
    type: "message",
    attachments: [{
      contentType: "application/vnd.microsoft.card.adaptive",
      content: {
        "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
        type: "AdaptiveCard",
        version: "1.4",
        body: [
          {type: "TextBlock", text: .title, weight: "Bolder", size: "Medium"},
          {type: "TextBlock", text: "Período: \(.from) a \(.to)", isSubtle: true, spacing: "None"},
          facts(summary_rows($m; .previous // {}) | map(with_previous($has_previous))),
          heading("Lead time por cliente (mediana / p90, dias)"),
          facts($m.lead_time_days.by_cliente | sorted_entries
            | map([.key, "\(.value.p50) / \(.value.p90) (\(.value.n) issues)"])),
          heading("SLA estourado por prioridade"),
          facts($m.sla_breaches | sorted_entries | map([.key, (.value | tostring)]))
        ],
        actions: [{type: "Action.OpenUrl", title: "Abrir board", url: .board_url}]
      }
    }]
  }
