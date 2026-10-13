#!/usr/bin/env bash
# repo-config: parse a consumer repo's devkit.ini and resolve it against the
# gate's inputs. Pure bash + awk + jq, so it runs in the detect job before any
# setup-* action and on a self-hosted runner with no Python.
#
# Env:
#   CONFIG_FILE          path of the ini to read; empty or missing => defaults
#   INPUTS_JSON          toJSON(inputs) of the calling gate (effective inputs)
#   CONFIG_SOURCE        free text for the summary, e.g. "the base branch 'main'"
#   CONFIG_PENDING       'true' when the PR changes the file (summary note)
#   GITHUB_OUTPUT        outputs target (optional; tests use --json instead)
#   GITHUB_STEP_SUMMARY  markdown summary target (optional)
# Flags:
#   --json               print the resolved object to stdout (used by tests)
#
# Never exits non-zero on a bad config: errors are surfaced as annotations and
# as the `errors` output, and gate-passed fails on them. Failing here would
# leave gate-passed skipped (no outputs from detect), which hides the cause.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRINT_JSON=false
[ "${1:-}" = "--json" ] && PRINT_JSON=true

CONFIG_FILE="${CONFIG_FILE:-}"
INPUTS_JSON="${INPUTS_JSON:-}"
[ -n "$INPUTS_JSON" ] || INPUTS_JSON='{}'
CONFIG_SOURCE="${CONFIG_SOURCE:-}"
CONFIG_PENDING="${CONFIG_PENDING:-false}"

# Settings the organisation owns. Never read from the file.
LOCKED='["runner","allowed-author-domains","identity-enforcement","secret-scan-historic-mode","attestation-frequency"]'

# checks.txt -> [{name, protected, description}]
CHECKS_JSON="$(awk -F'|' '
  /^[[:space:]]*(#|$)/ { next }
  { for (i = 1; i <= 3; i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i) }
    gsub(/\t/, " ", $3)
    printf "%s\t%s\t%s\n", $1, $2, $3 }
' "$HERE/checks.txt" | jq -R -s 'split("\n") | map(select(length > 0) | split("\t")
   | {name: .[0], protected: (.[1] == "yes"), description: .[2]})')"

FOUND=false
ENTRIES='[]'
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  FOUND=true
  # Tolerate a UTF-8 BOM and CRLF (Windows editors), then tokenise each line
  # into:  kind \t section \t key \t value \t line
  if [ "$(head -c 3 "$CONFIG_FILE" | od -An -tx1 | tr -d ' \n')" = "efbbbf" ]; then
    body="$(tail -c +4 "$CONFIG_FILE")"
  else
    body="$(cat "$CONFIG_FILE")"
  fi
  ENTRIES="$(printf '%s\n' "$body" | tr -d '\r' | awk -v OFS='\t' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^[ \t]*$/ { next }
    /^[ \t]*[#;]/ { next }
    /^[ \t]*\[[^]]*\][ \t]*$/ {
      s = $0; sub(/^[ \t]*\[/, "", s); sub(/\][ \t]*$/, "", s)
      section = tolower(trim(s))
      print "section", section, "", "", NR; next
    }
    /^[^=]+=/ {
      k = $0; sub(/=.*/, "", k); k = tolower(trim(k))
      v = $0; sub(/^[^=]*=/, "", v); v = trim(v)
      if (v ~ /^".*"$/ && length(v) >= 2) { v = substr(v, 2, length(v) - 2) }
      gsub(/\t/, " ", v)
      print "entry", section, k, v, NR; next
    }
    { l = $0; gsub(/\t/, " ", l); print "bad", section, "", l, NR }
  ' | jq -R -s 'split("\n") | map(select(length > 0) | split("\t")
      | {kind: .[0], section: .[1], key: .[2], value: .[3], line: (.[4] | tonumber)})')"
fi

RESOLVED="$(jq -n \
  --argjson entries "$ENTRIES" --argjson inputs "$INPUTS_JSON" \
  --argjson checks "$CHECKS_JSON" --argjson locked "$LOCKED" --argjson found "$FOUND" \
  -f "$HERE/resolve.jq")"

# Annotations point at the file in the checkout. On a PR that changes the file
# the line numbers refer to the base-branch copy, which is what was read.
jq -r '.warnings[] | "::warning file=devkit.ini,line=\(.line)::devkit.ini: \(.msg)"' <<<"$RESOLVED"
jq -r '.errors[]   | "::error file=devkit.ini,line=\(.line)::devkit.ini: \(.msg)"'   <<<"$RESOLVED"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "found=$(jq -r '.found' <<<"$RESOLVED")"
    echo "enabled=$(jq -r '.enabled' <<<"$RESOLVED")"
    echo "reason=$(jq -r '.reason' <<<"$RESOLVED")"
    echo "skip=$(jq -r '.skip_list' <<<"$RESOLVED")"
    echo "skips-json=$(jq -c '.skips' <<<"$RESOLVED")"
    echo "settings=$(jq -c '.settings' <<<"$RESOLVED")"
    echo "overridden=$(jq -c '.overridden' <<<"$RESOLVED")"
    echo "errors=$(jq -r '.errors | length' <<<"$RESOLVED")"
    echo "warnings=$(jq -r '.warnings | length' <<<"$RESOLVED")"
  } >> "$GITHUB_OUTPUT"
fi

if [ "$FOUND" = true ] && [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  jq -r --arg src "$CONFIG_SOURCE" --arg pending "$CONFIG_PENDING" '
    def cell: tostring | gsub("\\|"; "\\\\|");
    def row(k; v): "| `\(k | cell)` | \(v | cell) |";
    [ "## devkit.ini",
      "Read from \($src)."
        + (if $pending == "true" then " **This PR changes `devkit.ini`; the new version applies after merge.**" else "" end),
      "",
      (if .enabled then "Kit: enabled."
       else "Kit: **disabled** by `[kit] enabled = false` (" + (if .reason == "" then "no reason given" else .reason end) + ")." end),
      "",
      (if (.skips | length) > 0 then
         ["| Skipped check | Reason |", "|---|---|"] + (.skips | to_entries | map(row(.key; .value))) + [""]
       else ["No checks skipped.", ""] end),
      (if (.overridden | length) > 0 then
         ["| Setting | Value from devkit.ini |", "|---|---|"] + (.overridden | to_entries | map(row(.key; .value))) + [""]
       else [] end),
      (if (.errors | length) > 0 then
         ["**Errors (the gate fails until these are fixed):**"] + (.errors | map("- line \(.line): \(.msg)")) + [""]
       else [] end),
      (if (.warnings | length) > 0 then
         ["**Warnings:**"] + (.warnings | map("- line \(.line): \(.msg)")) + [""]
       else [] end)
    ] | flatten | .[]' <<<"$RESOLVED" >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$PRINT_JSON" = true ]; then
  echo "$RESOLVED"
fi
