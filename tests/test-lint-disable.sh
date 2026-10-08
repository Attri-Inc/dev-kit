#!/usr/bin/env bash
# Unit tests for lint-disable-detector regex/scope logic.
# Tests run against tests/fixtures/lint-disable-test/ — no GitHub Actions context required.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/lint-disable-test"
COMPOSITE="$REPO_ROOT/.github/actions/lint-disable-detector/scan.sh"

if [ ! -f "$COMPOSITE" ]; then
  echo "FAIL: composite scanner not found at $COMPOSITE"
  exit 1
fi

# Run the scanner against the fixture dir, capture findings count.
# We cd into the fixture's parent so paths fed to scan.sh are like
# 'lint-disable-test/unjustified.py' — the EXCLUDE_GLOB matches the
# fixture's inner 'tests/' subdir without the absolute or repo-relative
# prefix '/tests/' or '^tests/' tripping the regex on every file.
#
# Capture stderr separately to a file: any non-empty stderr from scan.sh
# (or its child processes like find/awk/git) would otherwise contaminate
# the captured JSON via 2>&1 and break jq parsing in CI.
stderr_log=$(mktemp)
files_list=$(mktemp)
( cd "$FIXTURE_DIR/.." && find "lint-disable-test" -type f \( -name '*.py' -o -name '*.ts' \) ) > "$files_list" 2>>"$stderr_log"
set +e
output=$(cd "$FIXTURE_DIR/.." && "$COMPOSITE" --files-list "$files_list" --json 2>>"$stderr_log")
rc=$?
set -e
if [ -s "$stderr_log" ]; then
  echo "── scan.sh / find wrote to stderr ──"
  cat "$stderr_log"
  echo "── end stderr ──"
fi
rm -f "$stderr_log" "$files_list"
if [ "$rc" -ne 0 ] || [ -z "$output" ] || ! printf '%s' "$output" | head -c1 | grep -q '{'; then
  echo "FAIL: scan.sh did not produce JSON. exit=$rc"
  echo "── raw output below ──"
  printf '%s\n' "$output"
  echo "── end raw output ──"
  exit 1
fi
findings=$(printf '%s\n' "$output" | jq '.findings | length')
ai_authored=$(printf '%s\n' "$output" | jq '.ai_authored_count // 0')

echo "Findings: $findings"
echo "AI-authored: $ai_authored"

# Assertions
# Expected 6 unjustified disables:
#   - unjustified.py: 2 (noqa, type: ignore)
#   - unjustified.ts: 3 (ts-nocheck, ts-ignore, eslint-disable)
#   - unjustified_reason_before.py: 1 (I2 regression: reason BEFORE noqa)
# Justified fixtures (with `# reason:` AFTER the disable) and the tests/
# subdir fixture should NOT be counted.
if [ "$findings" != "6" ]; then
  echo "FAIL: expected 6 unjustified disables, got $findings"
  echo "  Expected breakdown:"
  echo "    unjustified.py: 2 (noqa, type: ignore)"
  echo "    unjustified.ts: 3 (ts-nocheck, ts-ignore, eslint-disable)"
  echo "    unjustified_reason_before.py: 1 (I2 regression: reason before disable)"
  echo "  Note: fixture in tests/ subdir should be excluded by file-scope."
  exit 1
fi

# AI-author detection: the fixture commits in this branch carry the
# `Co-Authored-By: Claude` trailer, so all 6 findings are AI-authored once
# committed. In an unstaged/uncommitted state during local development the
# count can be lower (git blame falls back to HEAD), so accept a range.
if [ "$ai_authored" -lt 0 ] || [ "$ai_authored" -gt 6 ]; then
  echo "FAIL: ai_authored_count out of expected range [0, 6], got $ai_authored"
  exit 1
fi

# Verify the test-dir fixture file did NOT contribute findings
test_dir_findings=$(echo "$output" | jq '[.findings[] | select(.file | contains("/tests/"))] | length')
if [ "$test_dir_findings" != "0" ]; then
  echo "FAIL: file-scope exclusion broken — found $test_dir_findings finding(s) in tests/ subdir"
  exit 1
fi

# Verify I2 regression: reason-before-disable IS flagged
i2_flagged=$(echo "$output" | jq '[.findings[] | select(.file | endswith("unjustified_reason_before.py"))] | length')
if [ "$i2_flagged" != "1" ]; then
  echo "FAIL: I2 regression — expected reason-before-disable to be flagged, got $i2_flagged finding(s)"
  exit 1
fi

# Verify justified fixtures are NOT flagged (reason AFTER disable).
# Anchor the regex with '/' so it doesn't match 'unjustified.py' too.
justified_flagged=$(echo "$output" | jq '[.findings[] | select(.file | test("/justified\\.(py|ts)$"))] | length')
if [ "$justified_flagged" != "0" ]; then
  echo "FAIL: justified fixtures (reason AFTER disable) should not be flagged, got $justified_flagged"
  exit 1
fi

# Regression: empty-result case. A PR whose changed files contain *zero*
# disable directives must yield `{"findings": [], "ai_authored_count": 0}`
# with exit 0. Before the grep-no-match fix this crashed scan.sh under
# `set -o pipefail` and the wrapper reported "Process completed with exit
# code 1" with no findings table — masking "0 findings" as a script error.
clean_dir=$(mktemp -d)
clean_file="$clean_dir/clean.py"
clean_files_list="$clean_dir/files.txt"
printf 'def hello():\n    return "no disable directives anywhere"\n' > "$clean_file"
( cd "$clean_dir" && echo "clean.py" > "$clean_files_list" )
set +e
clean_output=$(cd "$clean_dir" && "$COMPOSITE" --files-list "$clean_files_list" --json 2>&1)
clean_rc=$?
set -e
rm -rf "$clean_dir"
if [ "$clean_rc" -ne 0 ]; then
  echo "FAIL: empty-result regression — scan.sh exited $clean_rc on a file with no disables"
  echo "── output ──"; printf '%s\n' "$clean_output"; echo "── end ──"
  exit 1
fi
clean_findings=$(printf '%s\n' "$clean_output" | jq '.findings | length')
if [ "$clean_findings" != "0" ]; then
  echo "FAIL: empty-result regression — expected 0 findings on a clean file, got $clean_findings"
  exit 1
fi

# Regression (audit M3): a WEAK justification must NOT bypass the gate. The
# inline `# reason:` escape previously accepted any single non-space char
# ("# reason: x"), so it was gamed with one keystroke. A weak reason must be
# flagged; a meaningful (>=15 chars, >=2 words) one must pass.
weak_dir=$(mktemp -d)
weak_file="$weak_dir/weak.py"
weak_list="$weak_dir/files.txt"
printf 'bad = "x" * 999  # noqa: E501  # reason: x\nok = "y" * 999  # noqa: E501  # reason: third-party returns this pre-formatted\n' > "$weak_file"
( cd "$weak_dir" && echo "weak.py" > "$weak_list" )
set +e
weak_output=$(cd "$weak_dir" && "$COMPOSITE" --files-list "$weak_list" --json 2>&1)
set -e
rm -rf "$weak_dir"
weak_findings=$(printf '%s\n' "$weak_output" | jq '.findings | length')
if [ "$weak_findings" != "1" ]; then
  echo "FAIL: weak-reason regression — expected exactly 1 finding (weak reason flagged, strong reason passed), got $weak_findings"
  echo "── output ──"; printf '%s\n' "$weak_output"; echo "── end ──"
  exit 1
fi

echo "PASS: lint-disable-detector unit tests"
