include "report_rows";

def wip: {type: "TextBlock", text: "WIP"};

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
          wip,
          heading("SLA estourado por prioridade"),
          wip
        ],
        actions: [{type: "Action.OpenUrl", title: "Abrir board", url: .board_url}]
      }
    }]
  }
