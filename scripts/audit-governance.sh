#!/usr/bin/env bash
#
# audit-governance.sh
#
# Read-only audit of repository governance vs docs/governance-policy.md.
# Reports a per-repo PASS/FAIL matrix + an org-level summary so you can fix the
# gaps MANUALLY in GitHub (org rulesets / repo settings). Mutates NOTHING.
#
# Requires a token with admin-read on the repos (to read branch-protection /
# ruleset state). Run under your own org-admin `gh auth login`.
#
# Usage:
#   gh auth status                                  # must be authenticated (org admin)
#   bash scripts/audit-governance.sh <org>          # audit all non-archived repos in <org>
#   bash scripts/audit-governance.sh <org> repoA repoB   # audit specific repos
#
# Flags:
#   --json     emit machine-readable JSON instead of the table
#   --strict   exit non-zero if any repo has a gap (for CI use)
#
set -euo pipefail

ORG=""
JSON_OUTPUT=false
STRICT=false
REPOS_IN=()
for arg in "$@"; do
  case "$arg" in
    --json)   JSON_OUTPUT=true ;;
    --strict) STRICT=true ;;
    -*)       echo "Unknown flag: $arg" >&2; exit 2 ;;
    *)        if [ -z "$ORG" ]; then ORG="$arg"; else REPOS_IN+=("$arg"); fi ;;
  esac
done

if [ -z "$ORG" ]; then
  echo "Usage: $0 <org> [repo ...] [--json] [--strict]" >&2
  exit 2
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "::error::Not authenticated. Run 'gh auth login' as an org admin first." >&2
  exit 2
fi

# Resolve the repo list (names without the org/ prefix).
REPOS=()
if [ "${#REPOS_IN[@]}" -gt 0 ]; then
  REPOS=("${REPOS_IN[@]}")
else
  mapfile -t REPOS < <(gh repo list "$ORG" --no-archived --limit 1000 --json name --jq '.[].name' | sort)
fi

# Org-level (one-time) checks.
ORG_2FA="$(gh api "orgs/$ORG" --jq '.two_factor_requirement_enabled // "unknown"' 2>/dev/null || echo "unknown")"
ORG_BASE_PERM="$(gh api "orgs/$ORG" --jq '.default_repository_permission // "unknown"' 2>/dev/null || echo "unknown")"

# Per-repo policy evaluation. Echoes a TSV row: repo<TAB>k1=v ... for each check.
audit_repo() {
  local repo="$1" full="$ORG/$1"
  local default rules prot

  default="$(gh api "repos/$full" --jq '.default_branch' 2>/dev/null || echo "")"
  if [ -z "$default" ]; then
    printf '%s\tERROR=unreadable\n' "$repo"; return
  fi

  # Effective ruleset rules on the default branch (readable; [] if none).
  rules="$(gh api "repos/$full/rules/branches/$default" 2>/dev/null || echo '[]')"
  # Legacy branch protection (admin-only; {} / Not Found if none or no access).
  prot="$(gh api "repos/$full/branches/$default/protection" 2>/dev/null || echo '{}')"

  local rule_types pr_rule checks_rule
  rule_types="$(echo "$rules" | jq -r '[.[].type]' 2>/dev/null || echo '[]')"
  pr_rule="$(echo "$rules" | jq -c '[.[] | select(.type=="pull_request")][0] // empty' 2>/dev/null || echo '')"
  checks_rule="$(echo "$rules" | jq -c '[.[] | select(.type=="required_status_checks")][0] // empty' 2>/dev/null || echo '')"

  # G-checks (true/false). Consider BOTH rulesets and legacy protection.
  local protected requires_pr approvals blocks_fp gate_required codeowner_review signed onboarded codeowners_file
  protected=false; requires_pr=false; approvals=0; blocks_fp=false
  gate_required=false; codeowner_review=false; signed=false

  if [ "$(echo "$rules" | jq 'length' 2>/dev/null || echo 0)" -gt 0 ] \
     || [ "$(echo "$prot" | jq 'has("required_pull_request_reviews") or has("required_status_checks")' 2>/dev/null || echo false)" = "true" ]; then
    protected=true
  fi
  if [ -n "$pr_rule" ] || [ "$(echo "$prot" | jq 'has("required_pull_request_reviews")' 2>/dev/null || echo false)" = "true" ]; then
    requires_pr=true
  fi
  if [ -n "$pr_rule" ]; then
    approvals="$(echo "$pr_rule" | jq -r '.parameters.required_approving_review_count // 0')"
    codeowner_review="$(echo "$pr_rule" | jq -r '.parameters.require_code_owner_review // false')"
  fi
  if [ "$approvals" = "0" ]; then
    approvals="$(echo "$prot" | jq -r '.required_pull_request_reviews.required_approving_review_count // 0' 2>/dev/null || echo 0)"
  fi
  if echo "$rule_types" | jq -e 'index("non_fast_forward")' >/dev/null 2>&1 \
     || [ "$(echo "$prot" | jq -r '.allow_force_pushes.enabled // true' 2>/dev/null || echo true)" = "false" ]; then
    blocks_fp=true
  fi
  if [ -n "$checks_rule" ] && echo "$checks_rule" | jq -e '[.parameters.required_status_checks[]?.context] | index("Gate passed")' >/dev/null 2>&1; then
    gate_required=true
  elif echo "$prot" | jq -e '[.required_status_checks.contexts[]?] | index("Gate passed")' >/dev/null 2>&1; then
    gate_required=true
  fi
  if echo "$rule_types" | jq -e 'index("required_signatures")' >/dev/null 2>&1; then
    signed=true
  fi

  # File-presence checks.
  onboarded=false; codeowners_file=false
  gh api "repos/$full/contents/.github/workflows/attri-dev-kit.yml" >/dev/null 2>&1 && onboarded=true
  if gh api "repos/$full/contents/.github/CODEOWNERS" >/dev/null 2>&1 \
     || gh api "repos/$full/contents/CODEOWNERS" >/dev/null 2>&1 \
     || gh api "repos/$full/contents/docs/CODEOWNERS" >/dev/null 2>&1; then
    codeowners_file=true
  fi

  printf '%s\tprotected=%s\trequires_pr=%s\tapprovals=%s\tblocks_force_push=%s\tgate_required=%s\tcodeowner_review=%s\tcodeowners_file=%s\tsigned_commits=%s\tonboarded=%s\n' \
    "$repo" "$protected" "$requires_pr" "$approvals" "$blocks_fp" "$gate_required" "$codeowner_review" "$codeowners_file" "$signed" "$onboarded"
}

ROWS=()
for r in "${REPOS[@]}"; do
  [ -z "$r" ] && continue
  ROWS+=("$(audit_repo "$r")")
done

if [ "$JSON_OUTPUT" = true ]; then
  {
    printf '{"org":"%s","org_2fa_required":"%s","base_permission":"%s","repos":[' "$ORG" "$ORG_2FA" "$ORG_BASE_PERM"
    first=true
    for row in "${ROWS[@]}"; do
      repo="${row%%$'\t'*}"; rest="${row#*$'\t'}"
      $first || printf ','; first=false
      printf '{"repo":"%s"' "$repo"
      IFS=$'\t' read -ra KVS <<< "$rest"
      for kv in "${KVS[@]}"; do printf ',"%s":"%s"' "${kv%%=*}" "${kv#*=}"; done
      printf '}'
    done
    printf ']}\n'
  }
  exit 0
fi

# Human-readable report.
echo "════════════════════════════════════════════════════════════════════"
echo " Governance audit — $ORG   (read-only; fix gaps manually in GitHub)"
echo " Org 2FA required: $ORG_2FA    Base permission: $ORG_BASE_PERM"
echo "════════════════════════════════════════════════════════════════════"
GAPS=0
for row in "${ROWS[@]}"; do
  repo="${row%%$'\t'*}"; rest="${row#*$'\t'}"
  # A repo "passes" when the core controls (G1/G4/G5/G9 + an approval) hold.
  get() { echo "$rest" | tr '\t' '\n' | grep "^$1=" | cut -d= -f2; }
  fail=()
  [ "$(get protected)" = "true" ]        || fail+=("no-branch-protection(G1/G5)")
  [ "$(get requires_pr)" = "true" ]      || fail+=("no-require-PR(G1)")
  [ "$(get gate_required)" = "true" ]    || fail+=("gate-passed-not-required(G4)")
  [ "$(get blocks_force_push)" = "true" ] || fail+=("force-push-allowed(G5)")
  [ "$(get codeowners_file)" = "true" ]  || fail+=("no-CODEOWNERS(G7)")
  [ "$(get onboarded)" = "true" ]        || fail+=("kit-not-onboarded(G9)")
  [ "$(get approvals)" -ge 1 ] 2>/dev/null || fail+=("0-required-approvals(G2)")
  if [ "${#fail[@]}" -eq 0 ]; then
    printf '  ✅ %s\n' "$repo"
  else
    printf '  ❌ %-32s %s\n' "$repo" "${fail[*]}"
    GAPS=$((GAPS + 1))
  fi
done
echo "────────────────────────────────────────────────────────────────────"
printf ' %d/%d repos have governance gaps. See docs/governance-policy.md to fix.\n' "$GAPS" "${#ROWS[@]}"
[ "$ORG_2FA" = "true" ] || echo " ⚠️  Org-level: 2FA is NOT required for all members (O1)."
[ "$ORG_BASE_PERM" = "read" ] || echo " ⚠️  Org-level: base permission is '$ORG_BASE_PERM', not 'read' (O3)."

if [ "$STRICT" = true ] && [ "$GAPS" -gt 0 ]; then
  exit 1
fi
exit 0
