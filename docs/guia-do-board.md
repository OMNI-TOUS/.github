# Guia do board

Board: https://github.com/orgs/OMNI-TOUS/projects/1

## Dia a dia

1. Abra a issue no repo do código, pelo formulário. Em poucos minutos ela aparece no board em Backlog.
2. No planejamento, preencha Priority e mova para Ready o que o time vai fazer. A visão Kanban mostra só o que saiu do Backlog.
3. Mova para In progress quando começar.
4. No PR, coloque `Closes OMNI-TOUS/<repo>#<número>`. O card vai para In review sozinho e para Done no merge.

Não precisa arrastar card para In review nem para Done.

## PR sem card

Bump de versão, ajuste de CI e afins: coloque o rótulo `sem-card`.

PR sem `Closes` e sem `sem-card` fica com o check `card-link` vermelho e aparece no board até ser ligado a uma issue. O check não bloqueia o merge.

## Rótulo `parado`

Issue sem atividade há 60 dias, nem nela nem no PR ligado, ganha `parado`. Nada fecha sozinho. Se voltar a ter atividade, o rótulo sai.

## Bloqueado

Mova o card para Bloqueado e comente o motivo na issue.

## Resumo semanal

Toda segunda sai um resumo no canal do Teams com o que foi entregue, PRs esperando revisão e issues paradas.
