#!/usr/bin/env bash
# scan.sh — core detection logic for lint-disable-detector.
# Designed to be testable in isolation (no GH Actions context required).
#
# Usage:
#   scan.sh --files-list <path>      # newline-separated file paths
#   scan.sh --json                   # output JSON to stdout
#   scan.sh --markdown               # output markdown table
#
# Outputs JSON:
#   {"findings": [{...}], "ai_authored_count": N}

set -euo pipefail

# Python suppression patterns (extended regex)
PY_PATTERNS='# *(noqa|type: ?ignore|pyright: ?ignore|pylint: ?disable|flake8: ?noqa|mypy: ?ignore-errors|pragma: ?no cover|yapf: ?disable|black: ?skip)'

# JS/TS suppression patterns
TS_PATTERNS='(//|/\*) *(eslint-disable|eslint-disable-next-line|eslint-disable-line|@ts-ignore|@ts-expect-error|@ts-nocheck|istanbul ignore|prettier-ignore)'

# File-scope exclusions (always)
EXCLUDE_GLOB='\.github/|^tests/|/tests/|_test\.(py|ts|tsx|go)$|\.test\.(ts|tsx|js)$|\.spec\.(ts|tsx|js)$|node_modules/|vendor/|dist/|build/'

# AI-author detection: returns "true" if the most recent commit touching a line
# matches AI heuristics. Best-effort; may return "false" in shallow checkouts.
is_ai_authored() {
  local file="$1"
  local lineno="$2"
  local commit_sha
  commit_sha=$(git blame --line-porcelain -L "$lineno,$lineno" "$file" 2>/dev/null | head -1 | awk '{print $1}')
  [ -z "$commit_sha" ] && echo "false" && return
  local committer_email author_email msg
  committer_email=$(git show -s --format='%ce' "$commit_sha" 2>/dev/null)
  author_email=$(git show -s --format='%ae' "$commit_sha" 2>/dev/null)
  msg=$(git show -s --format='%B' "$commit_sha" 2>/dev/null)
  if echo "$committer_email $author_email" | grep -qiE 'claude|attri-bot|\[bot\]'; then
    echo "true"; return
  fi
  if echo "$msg" | grep -qiE 'Generated with Claude Code|Co-Authored-By: Claude'; then
    echo "true"; return
  fi
  echo "false"
}

parse_args() {
  FILES_LIST=""
  OUTPUT_FORMAT="json"
  while [ $# -gt 0 ]; do
    case "$1" in
      --files-list) FILES_LIST="$2"; shift 2 ;;
      --json) OUTPUT_FORMAT="json"; shift ;;
      --markdown) OUTPUT_FORMAT="markdown"; shift ;;
      *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
  done
}

scan_file() {
  local file="$1"
  local language pattern
  case "$file" in
    *.py) language="python"; pattern="$PY_PATTERNS" ;;
    *.ts|*.tsx|*.js|*.jsx) language="ts"; pattern="$TS_PATTERNS" ;;
    *) return 0 ;;
  esac
  # Find lines with disable directive.
  # grep exits 1 when no lines match, which under `set -o pipefail` (above)
  # would propagate through scan_file -> the wrapper's `SCAN_OUT=$(...)` and
  # crash the action *before* it emits the empty-result JSON. Force the left
  # side of the pipe to always succeed so an "all-clean" file list resolves
  # to `{"findings": [], "ai_authored_count": 0}` instead of exit 1.
  { grep -nE "$pattern" "$file" 2>/dev/null || true; } | while IFS=: read -r lineno content; do
    # I2 fix: justification must come AFTER the disable directive on the same line.
    # Find the position of the first disable match, then check whether the
    # substring after it contains a justification. Using awk with match() avoids
    # sed-delimiter conflicts (the patterns contain both '/' and '|') and works
    # on both GNU and BSD userland.
    local after_disable
    after_disable=$(awk -v pat="$pattern" -v line="$content" 'BEGIN{
      if (match(line, pat)) {
        print substr(line, RSTART + RLENGTH)
      }
    }')
    # A justification must be MEANINGFUL. The previous check accepted any
    # single non-space char (e.g. "# reason: x"), so the inline bypass was
    # gamed with one keystroke and never reviewed. Require the reason text
    # (after the marker, on the same line, AFTER the disable) to be at least
    # 15 non-space characters and contain at least 2 words. Weaker reasons
    # fall through and are flagged like an unjustified disable. (audit M3)
    local reason_text reason_len reason_words
    reason_text=$(awk 'match($0, /(#|\/\/)[ \t]*reason:[ \t]*/){print substr($0, RSTART+RLENGTH)}' <<<"$after_disable")
    if [ -n "$reason_text" ]; then
      reason_len=$(printf '%s' "$reason_text" | tr -d '[:space:]' | wc -c | tr -d ' ')
      reason_words=$(printf '%s' "$reason_text" | grep -oE '[A-Za-z0-9]+' | wc -l | tr -d ' ')
      if [ "$reason_len" -ge 15 ] && [ "$reason_words" -ge 2 ]; then
        continue
      fi
    fi
    # I6 fix: literal tabs in content corrupt the TSV→jq pipeline because
    # split("\t") produces extra fields. Replace tabs with 4 spaces so the
    # row remains parseable while preserving the visible content.
    content="${content//$'\t'/    }"
    local ai
    ai=$(is_ai_authored "$file" "$lineno")
    printf '%s\t%s\t%s\t%s\t%s\n' "$file" "$lineno" "$language" "$ai" "$content"
  done
}

main() {
  parse_args "$@"
  if [ -z "$FILES_LIST" ]; then
    echo '{"findings": [], "ai_authored_count": 0}'
    exit 0
  fi

  local findings_tsv
  findings_tsv=$(while IFS= read -r f; do
    [ -z "$f" ] && continue
    # Apply file-scope exclusion
    if echo "$f" | grep -qE "$EXCLUDE_GLOB"; then
      continue
    fi
    scan_file "$f"
  done < "$FILES_LIST")

  if [ "$OUTPUT_FORMAT" = "json" ]; then
    if [ -z "$findings_tsv" ]; then
      echo '{"findings": [], "ai_authored_count": 0}'
      exit 0
    fi
    echo "$findings_tsv" | jq -R -s '
      split("\n") | map(select(length > 0)) | map(split("\t") | {
        file: .[0], line: (.[1]|tonumber), language: .[2],
        ai_authored: (.[3] == "true"), content: .[4]
      }) | {findings: ., ai_authored_count: ([.[] | select(.ai_authored)] | length)}
    '
  else
    echo "$findings_tsv"
  fi
}

main "$@"
