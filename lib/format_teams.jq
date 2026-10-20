include "report_rows";

def none: "Nenhum.";

def summary_widths: [3, 1, 1];

def summary_widths_without_previous: [3, 1];

def action_widths: [2, 1, 5];

def text($value): {type: "TextBlock", text: $value, wrap: true};

def heading($value): {type: "TextBlock", text: $value, weight: "Bolder", spacing: "Large"};

def cell: {type: "TableCell", items: [text(.)]};

def header_cell: {type: "TableCell", items: [text(.) + {weight: "Bolder"}]};

def table($widths; $rows):
  {
    type: "Table",
    columns: ($widths | map({width: .})),
    firstRowAsHeaders: false,
    showGridLines: false,
    rows: ($rows | map({type: "TableRow", cells: map(cell)}))
  };

def table($widths; $header; $rows):
  table($widths; $rows)
  | .firstRowAsHeaders = true
  | .rows = [{type: "TableRow", cells: ($header | map(header_cell))}] + .rows;

def action_rows: map(["[\(.ref)](\(.url))", (.days | tostring), .title]);

def more_label: "e mais \(.more | length)";

def more_link: text("[\(more_label)](\(.url))") + {isSubtle: true};

def more_toggle($id):
  {type: "ActionSet", actions: [{type: "Action.ToggleVisibility", title: more_label, targetElements: [$id]}]},
  (table(action_widths; .more | action_rows) + {id: $id, isVisible: false});

def action_section($title; $key):
  .[$key] as $list
  | heading("\($title) (\($list.total))"),
    (if $list.total == 0 then text(none)
     else table(action_widths; ["Item", "Dias", "Título"]; $list.items | action_rows),
       ($list | if (.more | length) == 0 then empty elif .url then more_link else more_toggle("more-\($key)") end)
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
        msteams: {width: "Full"},
        body: [
          {type: "TextBlock", text: .title, weight: "Bolder", size: "Medium"},
          {type: "TextBlock", text: "Período: \(.from) a \(.to)", isSubtle: true, spacing: "None"},
          summary_table($m; .previous),
          ($m.actions
            | action_section("Travados em In progress / In review"; "stuck"),
              action_section("PRs sem revisão"; "prs_waiting_review"),
              action_section("Novas sem responsável ou prioridade"; "unowned"),
              action_section("Bloqueados"; "blocked"),
              action_section("Sub-issues todas concluídas"; "sub_issues_done")),
          text("Lead time por cliente e SLA por prioridade: WIP") + {isSubtle: true, spacing: "Large"}
        ],
        actions: [{type: "Action.OpenUrl", title: "Abrir board", url: .board_url}]
      }
    }]
  }
