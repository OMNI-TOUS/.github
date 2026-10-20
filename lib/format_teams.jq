include "report_rows";

def none: "Nenhum.";

def summary_widths: [3, 1, 1];

def summary_widths_without_previous: [3, 1];

def action_widths: [2, 1, 5];

def text($value): {type: "TextBlock", text: $value, wrap: true};

def heading($value): {type: "TextBlock", text: $value, weight: "Bolder", spacing: "Large"};

def cell: {type: "TableCell", items: [text(.)]};

def header_cell: {type: "TableCell", items: [text(.) + {weight: "Bolder"}]};

def table($widths; $header; $rows):
  {
    type: "Table",
    columns: ($widths | map({width: .})),
    firstRowAsHeaders: true,
    showGridLines: false,
    rows: [{type: "TableRow", cells: ($header | map(header_cell))}]
      + ($rows | map({type: "TableRow", cells: map(cell)}))
  };

def action_table:
  table(action_widths; ["Item", "Dias", "Título"]; .items | map(["[\(.ref)](\(.url))", (.days | tostring), .title]));

def remaining: .total - (.items | length);

def action_section($title; $list):
  heading("\($title) (\($list.total))"),
  (if $list.total == 0 then text(none)
   else ($list | action_table), ($list | remaining | if . > 0 then text("e mais \(.)") + {isSubtle: true} else empty end)
   end);

def summary_table($m; $previous):
  summary_rows($m; $previous // {}) as $rows
  | if $previous == null then table(summary_widths_without_previous; ["Indicador", "Valor"]; $rows | map(.[:2]))
    else table(summary_widths; ["Indicador", "Atual", "Anterior"]; $rows)
    end;

.metrics as $m
| {
    type: "message",
    attachments: [{
      contentType: "application/vnd.microsoft.card.adaptive",
      content: {
        "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
        type: "AdaptiveCard",
        version: "1.5",
        body: [
          {type: "TextBlock", text: .title, weight: "Bolder", size: "Medium"},
          {type: "TextBlock", text: "Período: \(.from) a \(.to)", isSubtle: true, spacing: "None"},
          summary_table($m; .previous),
          action_section("Travados em In progress / In review"; $m.actions.stuck),
          action_section("PRs sem revisão"; $m.actions.prs_waiting_review),
          action_section("Novas sem responsável ou prioridade"; $m.actions.unowned),
          action_section("Bloqueados"; $m.actions.blocked),
          action_section("Sub-issues todas concluídas"; $m.actions.sub_issues_done),
          text("Lead time por cliente e SLA por prioridade: WIP") + {isSubtle: true, spacing: "Large"}
        ],
        actions: [{type: "Action.OpenUrl", title: "Abrir board", url: .board_url}]
      }
    }]
  }
