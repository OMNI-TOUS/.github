#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CASES="$ROOT/tests/cases"
failures=0
total=0

fail() {
  echo "FAIL $1"
  failures=$((failures + 1))
}

run_case() {
  local filter="$1" input="$2" base="${2%.input.json}"
  total=$((total + 1))
  local actual
  if [ -f "$base.expected.md" ]; then
    if ! actual="$(jq -r -L "$ROOT/lib" -f "$ROOT/lib/$filter.jq" "$input" 2>&1)"; then
      fail "$filter/$(basename "$input"): $actual"
    elif ! diff "$base.expected.md" <(printf '%s\n' "$actual"); then
      fail "$filter/$(basename "$input")"
    fi
    return
  fi
  if ! actual="$(jq -L "$ROOT/lib" -f "$ROOT/lib/$filter.jq" "$input" 2>&1)"; then
    fail "$filter/$(basename "$input"): $actual"
  elif ! diff <(jq -S . "$base.expected.json") <(jq -S . <<<"$actual"); then
    fail "$filter/$(basename "$input")"
  fi
}

for dir in "$CASES"/*/; do
  filter="$(basename "$dir")"
  for input in "$dir"*.input.json; do
    run_case "$filter" "$input"
  done
done

echo "$((total - failures))/$total passed"
[ "$failures" -eq 0 ]
