include "report_rows";

def row($cells): "| " + ($cells | join(" | ")) + " |";

def table($header; $rows):
  [row($header), "|" + ($header | map("---|") | join(""))] + $rows | join("\n");

def lead_table($label; $stats):
  if ($stats | length) == 0 then "Nenhuma issue fechada no período."
  else table([$label, "Issues", "Mediana", "p90"];
    $stats | sorted_entries | map(row([.key, (.value.n, .value.p50, .value.p90 | tostring)])))
  end;

def sla_table($breaches):
  if ($breaches | length) == 0 then "Nenhum."
  else table(["Prioridade", "Issues"];
    $breaches | sorted_entries | map(row([.key, (.value | tostring)])))
  end;

.metrics as $m
| [
    "## \(.title)",
    "",
    "Período: \(.from) a \(.to)",
    "",
    table(["Indicador", "Atual", "Anterior"]; summary_rows($m; .previous // {}) | map(row(.))),
    "",
    "### Lead time por repositório",
    "",
    lead_table("Repositório"; $m.lead_time_days.by_repo),
    "",
    "### Lead time por cliente",
    "",
    lead_table("Cliente"; $m.lead_time_days.by_cliente),
    "",
    "### SLA estourado por prioridade",
    "",
    sla_table($m.sla_breaches)
  ]
| join("\n")
