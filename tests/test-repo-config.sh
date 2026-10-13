#!/usr/bin/env bash
# Unit tests for the repo-config (devkit.ini) parser.
# Runs parse.sh against tests/fixtures/repo-config/*.ini — no Actions context needed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$REPO_ROOT/tests/fixtures/repo-config"
PARSER="$REPO_ROOT/.github/actions/repo-config/parse.sh"
INPUTS="$(cat "$FIXTURES/inputs.json")"

pass=0; fail=0
check() { # check <label> <actual> <expected>
  if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; echo "   expected: $3"; echo "   actual:   $2"; fi
}
resolve() { # resolve <ini-file-or-empty> -> JSON on stdout (annotations dropped)
  CONFIG_FILE="$1" INPUTS_JSON="$INPUTS" bash "$PARSER" --json | grep -v '^::'
}
q() { jq -r "$2" <<<"$1"; }

# ── no file ───────────────────────────────────────────────────────────
r=$(resolve "")
check "no file: found=false"            "$(q "$r" .found)"                 "false"
check "no file: enabled"                "$(q "$r" .enabled)"               "true"
check "no file: skip list is ','"       "$(q "$r" .skip_list)"             ","
check "no file: settings == inputs"     "$(q "$r" '.settings == $in' --argjson in "$INPUTS" 2>/dev/null || jq -r --argjson in "$INPUTS" '.settings == $in' <<<"$r")" "true"
check "no file: no errors/warnings"     "$(q "$r" '(.errors|length) + (.warnings|length)')" "0"
r=$(resolve "$FIXTURES/does-not-exist.ini")
check "missing path behaves like no file" "$(q "$r" .found)"               "false"

# ── valid ─────────────────────────────────────────────────────────────
r=$(resolve "$FIXTURES/valid.ini")
check "valid: found"                    "$(q "$r" .found)"                 "true"
check "valid: skip list padded+sorted"  "$(q "$r" .skip_list)"             ",hygiene.typos,python.type-check,"
check "valid: reason kept"              "$(q "$r" '.skips["hygiene.typos"]')" "clinical vocabulary trips the dictionary"
check "valid: string setting"           "$(q "$r" '.settings["python-version"]')" "3.12"
check "valid: number coerced"           "$(q "$r" '.settings["pr-size-soft-limit"] | type')" "number"
check "valid: number value"             "$(q "$r" '.settings["pr-size-soft-limit"]')" "600"
check "valid: untouched input kept"     "$(q "$r" '.settings["fail-on"]')"  "high"
check "valid: overridden lists 2"       "$(q "$r" '.overridden | length')"  "2"
check "valid: clean"                    "$(q "$r" '(.errors|length) + (.warnings|length)')" "0"

# ── missing reason: warn, still skip ─────────────────────────────────
r=$(resolve "$FIXTURES/missing-reason.ini")
check "missing reason: still skipped"   "$(q "$r" .skip_list)"             ",hygiene.typos,"
check "missing reason: placeholder"     "$(q "$r" '.skips["hygiene.typos"]')" "(no reason given)"
check "missing reason: 1 warning"       "$(q "$r" '.warnings | length')"    "1"
check "missing reason: no error"        "$(q "$r" '.errors | length')"      "0"

# ── protected checks: error, not skipped; others still honoured ──────
r=$(resolve "$FIXTURES/protected.ini")
check "protected: 2 errors"             "$(q "$r" '.errors | length')"      "2"
check "protected: error names line"     "$(q "$r" '.errors[0].line')"        "2"
check "protected: not in skip list"     "$(q "$r" .skip_list)"             ",python.lint,"

# ── locked settings: error, not applied; others still applied ────────
r=$(resolve "$FIXTURES/locked.ini")
check "locked: 2 errors"                "$(q "$r" '.errors | length')"      "2"
check "locked: runner unchanged"        "$(q "$r" '.settings.runner')"       "ubuntu-latest"
check "locked: domains unchanged"       "$(q "$r" '.settings["allowed-author-domains"]')" ""
check "locked: fail-on applied"         "$(q "$r" '.settings["fail-on"]')"  "critical"

# ── unknown things: warn and ignore ──────────────────────────────────
r=$(resolve "$FIXTURES/unknown.ini")
check "unknown: 6 warnings"             "$(q "$r" '.warnings | length')"    "6"
check "unknown: 0 errors"               "$(q "$r" '.errors | length')"      "0"
check "unknown: nothing skipped"        "$(q "$r" .skip_list)"             ","
check "unknown: nothing overridden"     "$(q "$r" '.overridden | length')"  "0"
check "unknown: bad line reported"      "$(q "$r" '[.warnings[] | select(.msg | test("not a `key = value`"))] | length')" "1"

# ── type coercion + enums ────────────────────────────────────────────
r=$(resolve "$FIXTURES/types.ini")
check "types: bad number ignored"       "$(q "$r" '.settings["pr-size-soft-limit"]')" "400"
check "types: good number applied"      "$(q "$r" '.settings["pr-size-hard-limit"]')" "900"
check "types: 'yes' -> boolean true"    "$(q "$r" '.settings["run-supply-chain"]')" "true"
check "types: boolean type"             "$(q "$r" '.settings["run-supply-chain"] | type')" "boolean"
check "types: bad tier ignored"         "$(q "$r" '.settings.tier')"         "auto"
check "types: fail-on enum ok"          "$(q "$r" '.settings["fail-on"]')"  "critical"
check "types: enforcement case-sensitive, ignored" "$(q "$r" '.settings["license-enforcement"]')" "warn"
check "types: commit-msg level ok"      "$(q "$r" '.settings["commit-msg-fail-level"]')" "error"
check "types: 3 warnings"               "$(q "$r" '.warnings | length')"    "3"

# ── disabled kit ─────────────────────────────────────────────────────
r=$(resolve "$FIXTURES/disabled.ini")
check "disabled: enabled=false"         "$(q "$r" .enabled)"               "false"
check "disabled: reason"                "$(q "$r" .reason)"                "archived repo, read-only since 2026-09"

# ── quoting, '=' in values, case-insensitive names, last wins ────────
r=$(resolve "$FIXTURES/quoted.ini")
check "quoted: outer quotes stripped, inner kept" "$(q "$r" '.settings["python-test-command"]')" "uv run pytest -k 'a=b' -m \\\"not slow\\\""
check "quoted: list value"              "$(q "$r" '.settings.languages')"   "python,typescript"
check "quoted: name case-folded"        "$(q "$r" .skip_list)"             ",python.type-check,"
check "quoted: last duplicate wins"     "$(q "$r" '.skips["python.type-check"]')" "but the last entry wins"

# ── BOM + CRLF ───────────────────────────────────────────────────────
tmp="$(mktemp)"
printf '\xEF\xBB\xBF[skip]\r\nhygiene.typos = windows editor\r\n[settings]\r\npython-version = 3.13\r\n' > "$tmp"
r=$(resolve "$tmp")
check "bom+crlf: skip parsed"           "$(q "$r" .skip_list)"             ",hygiene.typos,"
check "bom+crlf: no stray CR in value"  "$(q "$r" '.settings["python-version"]')" "3.13"
check "bom+crlf: clean"                 "$(q "$r" '(.errors|length) + (.warnings|length)')" "0"
rm -f "$tmp"

# ── GITHUB_OUTPUT contract ───────────────────────────────────────────
out="$(mktemp)"
CONFIG_FILE="$FIXTURES/valid.ini" INPUTS_JSON="$INPUTS" GITHUB_OUTPUT="$out" bash "$PARSER" >/dev/null
check "outputs: skip"                   "$(grep '^skip=' "$out")"           "skip=,hygiene.typos,python.type-check,"
check "outputs: errors"                 "$(grep '^errors=' "$out")"         "errors=0"
check "outputs: settings is one line of JSON" "$(grep -c '^settings={' "$out")" "1"
check "outputs: all 9 keys present"     "$(grep -cE '^(found|enabled|reason|skip|skips-json|settings|overridden|errors|warnings)=' "$out")" "9"
rm -f "$out"

# ── GITHUB_STEP_SUMMARY ──────────────────────────────────────────────
sum="$(mktemp)"
CONFIG_FILE="$FIXTURES/protected.ini" INPUTS_JSON="$INPUTS" CONFIG_SOURCE="the base branch 'main'" CONFIG_PENDING=true GITHUB_STEP_SUMMARY="$sum" bash "$PARSER" >/dev/null
check "summary: header"                 "$(grep -c '^## devkit.ini' "$sum")" "1"
check "summary: pending note"           "$(grep -c 'applies after merge' "$sum")" "1"
check "summary: skipped table row"      "$(grep -c '| `python.lint` |' "$sum")" "1"
check "summary: errors listed"          "$(grep -c '^- line [0-9]*: ' "$sum")" "2"
rm -f "$sum"

# ── annotations ──────────────────────────────────────────────────────
ann="$(CONFIG_FILE="$FIXTURES/protected.ini" INPUTS_JSON="$INPUTS" bash "$PARSER")"
check "annotations: ::error lines"      "$(grep -c '^::error file=devkit.ini,line=' <<<"$ann")" "2"

# ── checks.txt is well-formed ────────────────────────────────────────
bad=$(grep -vE '^\s*(#|$)' "$REPO_ROOT/.github/actions/repo-config/checks.txt" | grep -vcE '^[a-z0-9.-]+\s*\|\s*(yes|no)\s*\|\s*\S' || true)
check "checks.txt: every line is name | yes/no | description" "$bad" "0"
dups=$(grep -vE '^\s*(#|$)' "$REPO_ROOT/.github/actions/repo-config/checks.txt" | awk -F'|' '{gsub(/ /,"",$1); print $1}' | sort | uniq -d | wc -l | tr -d ' ')
check "checks.txt: no duplicate names"  "$dups" "0"

echo
echo "repo-config parser: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "PASS: repo-config unit tests" || { echo "FAIL: repo-config unit tests"; exit 1; }
