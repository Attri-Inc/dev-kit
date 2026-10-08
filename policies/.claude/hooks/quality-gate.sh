#!/usr/bin/env bash
# PostToolUse hook — runs lightweight quality checks after every Edit/Write.
# Keeps Claude's iteration loop tight by surfacing problems immediately.
set -euo pipefail

input=$(cat)
file=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null || echo "")
[ -z "$file" ] || [ ! -f "$file" ] && exit 0

# Per-language quick check — non-blocking by default
case "$file" in
  *.py)
    if command -v ruff >/dev/null; then
      out=$(ruff check --quiet "$file" 2>&1 || true)
      [ -n "$out" ] && echo "::notice::ruff:$out" >&2
    fi
    ;;
  *.ts|*.tsx|*.js|*.jsx)
    if [ -f biome.json ] && command -v biome >/dev/null; then
      out=$(biome check --reporter=summary "$file" 2>&1 || true)
      [ -n "$out" ] && echo "::notice::biome:$out" >&2
    fi
    ;;
  *.go)
    if command -v gofmt >/dev/null; then
      diff <(gofmt "$file") "$file" >/dev/null || echo "::notice::gofmt: $file needs formatting" >&2
    fi
    ;;
  *.tf)
    if command -v terraform >/dev/null; then
      terraform fmt -check "$file" >/dev/null 2>&1 || echo "::notice::terraform fmt needed: $file" >&2
    fi
    ;;
esac

exit 0
