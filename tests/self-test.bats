#!/usr/bin/env bats
# Tests against real planted-bad-state fixtures (built by tests/build-fixtures.sh).
# Run with: bats tests/self-test.bats

setup_file() {
  ROOT="$(git rev-parse --show-toplevel)"
  export ROOT
  bash "$ROOT/tests/build-fixtures.sh" >/dev/null
}

setup() {
  ROOT="$(git rev-parse --show-toplevel)"
}

# ─── Static structure ───────────────────────────────────────────────

@test "detect-stack action exists and is composite YAML" {
  [ -f "$ROOT/.github/actions/detect-stack/action.yml" ]
  grep -q "using: 'composite'" "$ROOT/.github/actions/detect-stack/action.yml"
}

@test "detect-stack detects repo Node version and gate threads it to the TS job" {
  # Honors .nvmrc / .node-version / engines so an Astro-22 repo isn't built on Node 20.
  grep -q '^  node-version:' "$ROOT/.github/actions/detect-stack/action.yml"
  grep -q '\.nvmrc' "$ROOT/.github/actions/detect-stack/action.yml"
  grep -q 'engines.node' "$ROOT/.github/actions/detect-stack/action.yml"
  grep -q 'node-version: ${{ steps.detect.outputs.node-version }}' "$ROOT/.github/workflows/gate.yml"
  grep -qF "node-version: \${{ needs.detect.outputs.node-version || '20' }}" "$ROOT/.github/workflows/gate.yml"
}

@test "identity-check rejects .local emails" {
  grep -qF '.local' "$ROOT/.github/actions/identity-check/action.yml"
}

@test "identity-check rejects gmail addresses" {
  grep -qE 'gmail' "$ROOT/.github/actions/identity-check/action.yml"
}

@test "identity-check is off by default (empty allowed-domains skips it)" {
  grep -qF "if [ -z '\${{ inputs.allowed-domains }}' ]; then" "$ROOT/.github/actions/identity-check/action.yml"
  awk '/allowed-author-domains:/{f=1} f&&/default:/{print; exit}' "$ROOT/.github/workflows/gate.yml" | grep -qF "default: ''"
}

@test "gate defaults to GitHub-hosted runners; self-test pins them (no fork PRs on self-hosted)" {
  awk '/^      runner:/{f=1} f&&/default:/{print; exit}' "$ROOT/.github/workflows/gate.yml" | grep -qF "default: 'ubuntu-latest'"
  grep -qE '^      runner: ubuntu-latest$' "$ROOT/.github/workflows/self-test.yml"
}

@test "identity-check has enforcement parameter" {
  grep -q 'enforcement:' "$ROOT/.github/actions/identity-check/action.yml"
}

@test "pr-size-guard ships defaults of 400 / 600" {
  grep -q "default: '400'" "$ROOT/.github/actions/pr-size-guard/action.yml"
  grep -q "default: '600'" "$ROOT/.github/actions/pr-size-guard/action.yml"
}

@test "migration-safety covers SQL DROP TABLE" {
  grep -qF 'DROP' "$ROOT/.github/actions/migration-safety/action.yml"
  grep -qF 'TABLE|COLUMN|INDEX|SCHEMA' "$ROOT/.github/actions/migration-safety/action.yml"
}

@test "migration-safety covers Alembic op.drop_*" {
  grep -qF 'op\.(drop_table|drop_column|drop_index|drop_constraint)' "$ROOT/.github/actions/migration-safety/action.yml"
}

@test "gate.yml has auto tier resolution from branch name" {
  grep -q 'INPUT_TIER' "$ROOT/.github/workflows/gate.yml"
  grep -qE 'dev-\*|develop|integration|migration' "$ROOT/.github/workflows/gate.yml"
}

@test "gate.yml routes to all 8 per-language workflows" {
  for lang in python typescript java go terraform docker shell csharp; do
    grep -q "_${lang}.yml" "$ROOT/.github/workflows/gate.yml"
  done
}

@test "gate.yml supply-chain attests artifact, not just SBOM" {
  grep -q 'build-artifact' "$ROOT/.github/workflows/gate.yml"
  grep -q 'subject-path:' "$ROOT/.github/workflows/gate.yml"
}

@test "gate.yml honors .attri-dev-kit-skip" {
  grep -qF '.attri-dev-kit-skip' "$ROOT/.github/workflows/gate.yml"
}

@test "gate.yml skips pr-size on onboarding PR" {
  grep -q 'onboarding-pr' "$ROOT/.github/workflows/gate.yml"
}

@test "every example uses tier: auto" {
  for f in "$ROOT/examples"/*/.github/workflows/attri-dev-kit.yml; do
    grep -q 'tier: auto' "$f"
  done
}

@test "every example pins to @main (the kit's canonical reference)" {
  # Policy: the kit tracks main and has no version tags, so examples must
  # reference it as @main.
  grep -rq '@main' "$ROOT/examples/"
  ! grep -r '@v1[^.0-9]' "$ROOT/examples/" --include='*.yml' --include='*.yaml' \
    || (echo "Examples should pin @main (the kit has no version tags)"; false)
}

@test "all baseline policies exist" {
  for f in ruff.toml biome.json .gitleaks.toml tflint.hcl .editorconfig .hadolint.yaml lefthook.yml .pre-commit-config.yaml; do
    [ -f "$ROOT/policies/$f" ]
  done
}

# ─── Fixture-driven tests (uses .git history) ────────────────────────

@test "fixture local-email-author has .local commit" {
  cd "$ROOT/tests/fixtures/local-email-author"
  git log -1 --format='%ae' | grep -qE '\.local$'
}

@test "fixture gmail-author has @gmail.com commit" {
  cd "$ROOT/tests/fixtures/gmail-author"
  git log -1 --format='%ae' | grep -qE '@gmail\.com$'
}

@test "fixture oversized-pr branch has +700 line diff" {
  cd "$ROOT/tests/fixtures/oversized-pr"
  ADDS=$(git diff --numstat main feature/huge | awk '{a+=$1} END{print a}')
  [ "$ADDS" -ge 700 ]
}

@test "fixture risky-migration-sql contains DROP TABLE" {
  grep -q 'DROP TABLE' "$ROOT/tests/fixtures/risky-migration-sql/migrations/001_drop.sql"
}

@test "fixture risky-migration-alembic contains op.drop_table" {
  grep -qF 'op.drop_table' "$ROOT/tests/fixtures/risky-migration-alembic/alembic/versions/001_drop.py"
}

@test "fixture vulnerable-tf has plaintext RDS password" {
  grep -q 'PlaintextPassword' "$ROOT/tests/fixtures/vulnerable-tf/main.tf"
}

@test "fixture bad-dockerfile uses :latest and runs as root" {
  grep -q 'FROM ubuntu:latest' "$ROOT/tests/fixtures/bad-dockerfile/Dockerfile"
  grep -q 'USER root' "$ROOT/tests/fixtures/bad-dockerfile/Dockerfile"
}

@test "fixture clean-baseline has no secrets" {
  ! grep -r 'sk-' "$ROOT/tests/fixtures/clean-baseline/" 2>/dev/null
}

@test "fixture kit-onboarding-pr only changes attri-dev-kit.yml on the branch" {
  cd "$ROOT/tests/fixtures/kit-onboarding-pr"
  CHANGED=$(git diff --name-only main chore/onboard)
  [ "$CHANGED" = ".github/workflows/attri-dev-kit.yml" ]
}

# ─── Essential composite actions ────────────────────────────────────

@test "actions/build-artifact exists" {
  [ -f "$ROOT/.github/actions/build-artifact/action.yml" ]
}

@test "actions/detect-secrets uses both detect-secrets and trufflehog OSS" {
  grep -q 'detect-secrets' "$ROOT/.github/actions/detect-secrets/action.yml"
  grep -q 'trufflehog' "$ROOT/.github/actions/detect-secrets/action.yml"
  grep -q 'only-verified' "$ROOT/.github/actions/detect-secrets/action.yml"
}

@test "secret-in-env fixture actually contains planted secrets (not empty in CI)" {
  # Regression guard for audit H11: the .env is .gitignored, so without
  # build-fixtures.sh recreating it the fixture was silently empty in CI.
  [ -f "$ROOT/tests/fixtures/secret-in-env/.env" ]
  grep -q 'AWS_SECRET_ACCESS_KEY' "$ROOT/tests/fixtures/secret-in-env/.env"
}

@test "detect-secrets behaviorally flags the planted secrets (when installed)" {
  # Real behavioral coverage: run the scanner the kit uses and assert it fires.
  # Skips gracefully where detect-secrets isn't installed (e.g. some dev boxes);
  # CI installs detect-secrets==1.5.0 so this runs there.
  command -v detect-secrets >/dev/null || skip "detect-secrets not installed"
  run bash -c "cd '$ROOT/tests/fixtures/secret-in-env' && detect-secrets scan .env | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d[\"results\"] else 1)'"
  [ "$status" -eq 0 ]
}

@test "diff-coverage action exists, is composite, and is warn-first by default" {
  [ -f "$ROOT/.github/actions/diff-coverage/action.yml" ]
  grep -q "using: 'composite'" "$ROOT/.github/actions/diff-coverage/action.yml"
  grep -qE "default: 'warn'" "$ROOT/.github/actions/diff-coverage/action.yml"
}

@test "diff-coverage gate is wired into all coverage-capable language workflows" {
  for w in _python _go _typescript _java _csharp; do
    grep -q 'actions/diff-coverage' "$ROOT/.github/workflows/$w.yml"
  done
}

@test "verify-attestation action exists and is composite" {
  [ -f "$ROOT/.github/actions/verify-attestation/action.yml" ]
  grep -q "using: 'composite'" "$ROOT/.github/actions/verify-attestation/action.yml"
}

@test "policies ship a .gitattributes line-ending template (LF for shell)" {
  [ -f "$ROOT/policies/.gitattributes" ]
  grep -qE '\*\.sh +text +eol=lf' "$ROOT/policies/.gitattributes"
}

@test "lockfile integrity: go mod verify + dotnet --locked-mode + TS frozen-lockfile" {
  grep -q 'go mod verify' "$ROOT/.github/workflows/_go.yml"
  grep -q 'dotnet restore --locked-mode' "$ROOT/.github/workflows/_csharp.yml"
  grep -q -- '--frozen-lockfile' "$ROOT/.github/workflows/_typescript.yml"
}

@test "editorconfig job has a CRLF shell-script safety net" {
  grep -q 'Shell scripts must be LF' "$ROOT/.github/workflows/gate.yml"
}

@test "license-check action exists, is composite, warn-first, denies A?GPL" {
  [ -f "$ROOT/.github/actions/license-check/action.yml" ]
  grep -q "using: 'composite'" "$ROOT/.github/actions/license-check/action.yml"
  grep -qE "default: 'warn'" "$ROOT/.github/actions/license-check/action.yml"
  grep -q 'A?GPL' "$ROOT/.github/actions/license-check/action.yml"
}

@test "gate.yml wires license-scan job and requires it in gate-passed" {
  grep -q 'actions/license-check' "$ROOT/.github/workflows/gate.yml"
  grep -q 'actions/license-check' "$ROOT/.github/workflows/gate.yml"
  # present in the gate-passed needs list
  awk '/gate-passed:/{f=1} f&&/- dep-scan/{print "found"}' "$ROOT/.github/workflows/gate.yml" | grep -q found
}

@test "provenance verification is wired into the gate self-check" {
  # Gate verifies its own freshly-created artifact attestation (self-check).
  # Closes sign-without-verify.
  grep -q 'actions/verify-attestation' "$ROOT/.github/workflows/gate.yml"
  # No stray inline `gh attestation verify` left behind (must go through the action).
  ! grep -rq 'gh attestation verify' "$ROOT/.github/workflows/"
}

@test "diff-coverage behaviorally fails below threshold / passes above (when installed)" {
  # Real behavioral coverage: build a tiny repo where a feature branch adds
  # 4 changed lines, 2 covered (50%), and assert diff-cover's exit codes.
  command -v diff-cover >/dev/null || skip "diff-cover not installed"
  D="$(mktemp -d)"
  (
    cd "$D"
    git init -q -b main && git config user.email t@t.io && git config user.name t
    printf 'def a():\n    return 1\n' > foo.py
    git add -A && git commit -q -m base
    git checkout -q -b feature
    printf 'def a():\n    return 1\n\ndef b(x):\n    if x:\n        return 2\n    return 3\n' > foo.py
    git add -A && git commit -q -m feature
    cat > coverage.xml <<'XML'
<?xml version="1.0" ?>
<coverage version="1.0"><packages><package name="." line-rate="0.5"><classes>
<class name="foo" filename="foo.py" line-rate="0.5"><lines>
<line number="4" hits="1"/><line number="5" hits="1"/>
<line number="6" hits="0"/><line number="7" hits="0"/>
</lines></class></classes></package></packages></coverage>
XML
  )
  run bash -c "cd '$D' && diff-cover coverage.xml --compare-branch main --fail-under 80"
  [ "$status" -ne 0 ]   # 50% < 80% → fail
  run bash -c "cd '$D' && diff-cover coverage.xml --compare-branch main --fail-under 40"
  [ "$status" -eq 0 ]   # 50% >= 40% → pass
}

@test "cost A1: quick checks consolidated into hygiene/code-scan/dep-scan, all required" {
  for j in hygiene code-scan dep-scan; do
    grep -q "^  $j:" "$ROOT/.github/workflows/gate.yml"
    awk -v g="- $j" '/gate-passed:/{f=1} f&&$0 ~ g{print "found"}' "$ROOT/.github/workflows/gate.yml" | grep -q found
  done
  # each grouped check runs even if a prior one fails (so a dev sees all findings)
  [ "$(grep -c 'if: ${{ !cancelled()' "$ROOT/.github/workflows/gate.yml")" -ge 12 ]
  # the merged checks' actions are still wired (as steps)
  for a in identity-check codeowners-check trojan-source-scan mcp-allowlist log-hygiene \
           dep-supply-chain license-check vuln-prioritize malicious-deps conftest-policy pr-size-guard; do
    grep -q "actions/$a@" "$ROOT/.github/workflows/gate.yml"
  done
}

@test "cost A2: detect emits docs-only; expensive jobs skip on it but secrets-scan does NOT" {
  grep -q 'docs-only:' "$ROOT/.github/workflows/gate.yml"
  grep -q 'id: docsonly' "$ROOT/.github/workflows/gate.yml"
  [ "$(grep -cE "has-[a-z]+ == 'true'.*docs-only != 'true'" "$ROOT/.github/workflows/gate.yml")" -eq 8 ]
  ln=$(grep -n '^  secrets-scan:' "$ROOT/.github/workflows/gate.yml" | cut -d: -f1)
  ! sed -n "${ln},$((ln+4))p" "$ROOT/.github/workflows/gate.yml" | grep -q 'docs-only'
}

@test "cost A4: artifact-retention-days input + retention-days on the 3 gate uploads" {
  grep -q 'artifact-retention-days:' "$ROOT/.github/workflows/gate.yml"
  [ "$(grep -c 'retention-days: ${{ inputs.artifact-retention-days }}' "$ROOT/.github/workflows/gate.yml")" -eq 3 ]
}

@test "scripts are all executable" {
  for f in install-pilot.sh pin-actions-to-sha.sh audit-governance.sh; do
    [ -x "$ROOT/scripts/$f" ]
  done
}

@test "compliance: control-mapping doc, evidence emission, conftest policy action" {
  [ -f "$ROOT/docs/compliance-control-mapping.md" ]
  [ -f "$ROOT/.github/actions/conftest-policy/action.yml" ]
  grep -q "using: 'composite'" "$ROOT/.github/actions/conftest-policy/action.yml"
  # gate emits machine-readable evidence + wires conftest into the required gate
  grep -q 'Emit compliance evidence' "$ROOT/.github/workflows/gate.yml"
  grep -q 'compliance-evidence' "$ROOT/.github/workflows/gate.yml"
  awk '/gate-passed:/{f=1} f&&/- dep-scan/{print "found"}' "$ROOT/.github/workflows/gate.yml" | grep -q found
}

@test "trojan-source-scan: BiDi + homoglyph across source, excludes fixtures, wired + required" {
  [ -f "$ROOT/.github/actions/trojan-source-scan/action.yml" ]
  grep -q "using: 'composite'" "$ROOT/.github/actions/trojan-source-scan/action.yml"
  grep -q '0400' "$ROOT/.github/actions/trojan-source-scan/action.yml"   # Cyrillic range (homoglyph)
  grep -q 'tests/fixtures' "$ROOT/.github/actions/trojan-source-scan/action.yml"  # excluded
  grep -q 'actions/trojan-source-scan' "$ROOT/.github/workflows/gate.yml"
  awk '/gate-passed:/{f=1} f&&/- code-scan/{print "found"}' "$ROOT/.github/workflows/gate.yml" | grep -q found
}

@test "mcp-allowlist action: approved-server enforcement, wired + required" {
  [ -f "$ROOT/.github/actions/mcp-allowlist/action.yml" ]
  grep -q "using: 'composite'" "$ROOT/.github/actions/mcp-allowlist/action.yml"
  grep -q 'mcpServers' "$ROOT/.github/actions/mcp-allowlist/action.yml"
  grep -q 'actions/mcp-allowlist' "$ROOT/.github/workflows/gate.yml"
  awk '/gate-passed:/{f=1} f&&/- code-scan/{print "found"}' "$ROOT/.github/workflows/gate.yml" | grep -q found
}

@test "dep-supply-chain action: cooldown + confusion, wired + required" {
  [ -f "$ROOT/.github/actions/dep-supply-chain/action.yml" ]
  grep -q "using: 'composite'" "$ROOT/.github/actions/dep-supply-chain/action.yml"
  grep -qE "default: 'warn'" "$ROOT/.github/actions/dep-supply-chain/action.yml"
  grep -qi 'cooldown' "$ROOT/.github/actions/dep-supply-chain/action.yml"
  grep -qi 'dependency-confusion' "$ROOT/.github/actions/dep-supply-chain/action.yml"
  grep -q 'actions/dep-supply-chain' "$ROOT/.github/workflows/gate.yml"
  awk '/gate-passed:/{f=1} f&&/- dep-scan/{print "found"}' "$ROOT/.github/workflows/gate.yml" | grep -q found
}

@test "malicious-deps action: composite, OSV malicious-packages (MAL-*), wired + required" {
  [ -f "$ROOT/.github/actions/malicious-deps/action.yml" ]
  grep -q "using: 'composite'" "$ROOT/.github/actions/malicious-deps/action.yml"
  grep -q 'osv-scanner' "$ROOT/.github/actions/malicious-deps/action.yml"
  grep -q 'MAL-' "$ROOT/.github/actions/malicious-deps/action.yml"
  grep -q 'actions/malicious-deps' "$ROOT/.github/workflows/gate.yml"
  awk '/gate-passed:/{f=1} f&&/- dep-scan/{print "found"}' "$ROOT/.github/workflows/gate.yml" | grep -q found
}

@test "vuln-prioritize action: composite, warn-first, uses CISA KEV + EPSS feeds" {
  [ -f "$ROOT/.github/actions/vuln-prioritize/action.yml" ]
  grep -q "using: 'composite'" "$ROOT/.github/actions/vuln-prioritize/action.yml"
  grep -qE "default: 'warn'" "$ROOT/.github/actions/vuln-prioritize/action.yml"
  grep -q 'known_exploited_vulnerabilities.json' "$ROOT/.github/actions/vuln-prioritize/action.yml"
  grep -q 'api.first.org/data/v1/epss' "$ROOT/.github/actions/vuln-prioritize/action.yml"
}

@test "gate.yml wires vuln-prioritize job and requires it in gate-passed" {
  grep -q 'actions/vuln-prioritize' "$ROOT/.github/workflows/gate.yml"
  awk '/gate-passed:/{f=1} f&&/- dep-scan/{print "found"}' "$ROOT/.github/workflows/gate.yml" | grep -q found
}

@test "_csharp.yml runs Semgrep SAST with C# rulesets + guarded SARIF upload" {
  # Semgrep is pip-installed, not run via `container: semgrep/semgrep` — the
  # image required a Docker daemon on the runner for no benefit.
  grep -q 'pip install .*semgrep==' "$ROOT/.github/workflows/_csharp.yml"
  ! grep -qE '^\s*container:' "$ROOT/.github/workflows/_csharp.yml"
  grep -q 'p/csharp' "$ROOT/.github/workflows/_csharp.yml"
  grep -q 'security-events: write' "$ROOT/.github/workflows/_csharp.yml"
  # SARIF upload guarded for private repos (no GHAS)
  grep -q '!github.event.repository.private' "$ROOT/.github/workflows/_csharp.yml"
}

@test "CI tooling runs without a Docker daemon except the image build path" {
  # No job-level containers and no `docker run` anywhere.
  ! grep -rqE '^\s*container:' "$ROOT/.github/workflows/"
  ! grep -rqE '(^|[[:space:]])docker[[:space:]]+run' "$ROOT/.github/"
  # Docker-in-container wrapper actions replaced by binaries/packages.
  # Match `uses:` references only — prose in comments may still name them.
  ! grep -rqE 'uses:[[:space:]]*wagoid/commitlint-github-action' "$ROOT/.github/"
  ! grep -rqE 'uses:[[:space:]]*hadolint/hadolint-action' "$ROOT/.github/"
  # reviewdog/action-actionlint is a Docker action pulled from ghcr.io.
  ! grep -rqE 'uses:[[:space:]]*reviewdog/action-actionlint' "$ROOT/.github/"
  # Trivy: only the image scan (which needs a built image) may use trivy-action.
  [ "$(grep -rcE 'uses:[[:space:]]*aquasecurity/trivy-action' "$ROOT/.github/" | awk -F: '{s+=$2} END {print s}')" -eq 1 ]
  grep -q 'aquasecurity/trivy-action' "$ROOT/.github/workflows/_docker.yml"
  grep -rq 'aquasecurity/setup-trivy' "$ROOT/.github/"
}

@test "tool setup is match-or-download so the ubuntu-latest fallback still works" {
  # Self-hosted runner images preinstall these tools; GitHub-hosted runners do
  # not. Every site must detect the version and install when it is absent,
  # otherwise a fallback to ubuntu-latest breaks the gate entirely.
  grep -q "steps.semgrep.outputs.present" "$ROOT/.github/workflows/_typescript.yml"
  grep -q "steps.semgrep.outputs.present" "$ROOT/.github/workflows/_csharp.yml"
  grep -q "steps.trivy.outputs.present" "$ROOT/.github/workflows/_terraform.yml"
  grep -q "steps.trivy.outputs.present" "$ROOT/.github/actions/license-check/action.yml"
  grep -q "steps.trivy.outputs.present" "$ROOT/.github/actions/vuln-prioritize/action.yml"
  # Trivy's baked DB does not exist on GitHub-hosted runners, so --skip-db-update
  # must be conditional or every fallback scan fails.
  grep -q 'skip-db-update' "$ROOT/.github/actions/vuln-prioritize/action.yml"
  grep -q 'mtime +1' "$ROOT/.github/actions/vuln-prioritize/action.yml"
  # commitlint falls back to npm install when /opt/commitlint is absent.
  grep -q '/opt/commitlint/node_modules' "$ROOT/.github/workflows/gate.yml"
  grep -q 'npm install --prefix' "$ROOT/.github/workflows/gate.yml"
}

@test "frontend-quality action: composite, warn-first, consume-if-present (lhci + size budgets)" {
  [ -f "$ROOT/.github/actions/frontend-quality/action.yml" ]
  grep -q "using: 'composite'" "$ROOT/.github/actions/frontend-quality/action.yml"
  grep -qE "default: 'warn'" "$ROOT/.github/actions/frontend-quality/action.yml"
  grep -q 'lhci' "$ROOT/.github/actions/frontend-quality/action.yml"
  grep -q 'size-limit' "$ROOT/.github/actions/frontend-quality/action.yml"
}

@test "_typescript.yml wires the frontend-quality job" {
  grep -q '^  frontend-quality:' "$ROOT/.github/workflows/_typescript.yml"
  grep -q 'actions/frontend-quality' "$ROOT/.github/workflows/_typescript.yml"
}

@test "log-hygiene action: composite, warn-first, value-adjacency (no prose FP)" {
  [ -f "$ROOT/.github/actions/log-hygiene/action.yml" ]
  grep -q "using: 'composite'" "$ROOT/.github/actions/log-hygiene/action.yml"
  grep -qE "default: 'warn'" "$ROOT/.github/actions/log-hygiene/action.yml"
  # uses the "used as a value" refinement, not a bare keyword match
  grep -q 'SEC_USED' "$ROOT/.github/actions/log-hygiene/action.yml"
}

@test "gate.yml wires log-hygiene job and requires it in gate-passed" {
  grep -q 'actions/log-hygiene' "$ROOT/.github/workflows/gate.yml"
  awk '/gate-passed:/{f=1} f&&/- code-scan/{print "found"}' "$ROOT/.github/workflows/gate.yml" | grep -q found
}

@test "codeowners-check action: composite, warn-first, uses GitHub's errors API" {
  [ -f "$ROOT/.github/actions/codeowners-check/action.yml" ]
  grep -q "using: 'composite'" "$ROOT/.github/actions/codeowners-check/action.yml"
  grep -qE "default: 'warn'" "$ROOT/.github/actions/codeowners-check/action.yml"
  grep -q 'codeowners/errors' "$ROOT/.github/actions/codeowners-check/action.yml"
}

@test "gate.yml wires codeowners job + requires it; template shipped; kit dogfoods catch-all" {
  grep -q 'actions/codeowners-check' "$ROOT/.github/workflows/gate.yml"
  awk '/gate-passed:/{f=1} f&&/- hygiene/{print "found"}' "$ROOT/.github/workflows/gate.yml" | grep -q found
  [ -f "$ROOT/policies/CODEOWNERS.template" ]
  grep -qE '^\*[[:space:]]+\S' "$ROOT/CODEOWNERS"   # kit's own CODEOWNERS has a catch-all
}

@test "governance policy + read-only audit script exist (Phase 2 audit-first)" {
  [ -f "$ROOT/docs/governance-policy.md" ]
  [ -x "$ROOT/scripts/audit-governance.sh" ]
  # audit is read-only: it must never call a mutating gh/git verb
  ! grep -qE 'gh api +-X +(POST|PUT|PATCH|DELETE)|gh api +--method +(POST|PUT|PATCH|DELETE)' "$ROOT/scripts/audit-governance.sh"
  # usage guard: missing org arg exits non-zero
  run bash "$ROOT/scripts/audit-governance.sh"
  [ "$status" -ne 0 ]
}

@test "all 3 issue templates exist" {
  for f in bug feature config; do
    [ -f "$ROOT/.github/ISSUE_TEMPLATE/$f.yml" ]
  done
}

@test "_python.yml supports poetry/pipenv/uv/pdm/pip lockfiles" {
  for pm in poetry pipenv uv pdm pip; do
    grep -q "pm=$pm" "$ROOT/.github/workflows/_python.yml"
  done
}

@test "_typescript.yml has build job" {
  grep -q 'name: Build' "$ROOT/.github/workflows/_typescript.yml"
}

@test "_docker.yml fans out across multiple Dockerfiles" {
  grep -q 'matrix:' "$ROOT/.github/workflows/_docker.yml"
  grep -q 'discover' "$ROOT/.github/workflows/_docker.yml"
}

@test "_terraform.yml has optional plan job" {
  grep -q 'enable-plan' "$ROOT/.github/workflows/_terraform.yml"
}

@test "no references to removed actions in gate.yml" {
  ! grep -E 'load-config|kill-switch-check|slack-summary|license-finder|frontend-perf|cost-tracker|readme-badge' "$ROOT/.github/workflows/gate.yml"
}

@test "no removed workflow files exist" {
  for f in _frontend-perf.yml nightly-status.yml; do
    [ ! -f "$ROOT/.github/workflows/$f" ]
  done
}

@test "no removed actions exist" {
  for d in load-config kill-switch-check slack-summary license-finder frontend-perf cost-tracker readme-badge; do
    [ ! -d "$ROOT/.github/actions/$d" ]
  done
}

# ─── AI-validation actions (Tier 1 additions) ────────────────────────

@test "actions/ai-provenance exists and detects bot patterns" {
  [ -f "$ROOT/.github/actions/ai-provenance/action.yml" ]
  grep -q 'noreply@anthropic\.com' "$ROOT/.github/actions/ai-provenance/action.yml"
  grep -q 'Co-Authored-By' "$ROOT/.github/actions/ai-provenance/action.yml"
}

@test "actions/agent-rule-scanner detects all 7 rule classes" {
  [ -f "$ROOT/.github/actions/agent-rule-scanner/action.yml" ]
  for rule in 'hidden-unicode' 'prompt-injection-marker' 'hidden-comment-imperative' 'shell-escape' 'mcp-suspicious-command' 'claude-bypass-mode' 'skill-frontmatter-hijack'; do
    grep -q "$rule" "$ROOT/.github/actions/agent-rule-scanner/action.yml"
  done
}

@test "actions/import-existence covers Python + npm + Go" {
  [ -f "$ROOT/.github/actions/import-existence/action.yml" ]
  grep -q 'pypi.org/pypi' "$ROOT/.github/actions/import-existence/action.yml"
  grep -q 'registry.npmjs.org' "$ROOT/.github/actions/import-existence/action.yml"
  grep -q 'pkg.go.dev' "$ROOT/.github/actions/import-existence/action.yml"
}

@test "actions/import-existence parses TOML manifests section-aware, not line by line" {
  # pyproject.toml / Pipfile config keys (coverage omit, ruff exclude, mypy module…)
  # once read as "packages" and blocked a real PR. Only dependency tables count now.
  grep -q 'new_python_deps.py' "$ROOT/.github/actions/import-existence/action.yml"
  [ -x "$ROOT/.github/actions/import-existence/new_python_deps.py" ]
  python3 -c 'import tomllib' 2>/dev/null || skip "python3 >= 3.11 needed for tomllib"
  base="$(mktemp)"; head="$(mktemp)"
  cat > "$base" <<'TOML'
[project]
dependencies = ["requests>=2"]
TOML
  cat > "$head" <<'TOML'
[project]
dependencies = ["requests>=2", "brand-new-dep>=1 ; python_version > '3.8'"]
[project.optional-dependencies]
dev = ["pytest"]
[tool.coverage.run]
branch = true
omit = ["conftest.py"]
[tool.ruff]
extend-exclude = ["build"]
[[tool.mypy.overrides]]
module = "yaml.*"
[tool.poetry.dependencies]
python = "^3.12"
[tool.poetry.group.dev.dependencies]
poetry-only-dep = "^1.0"
TOML
  run python3 "$ROOT/.github/actions/import-existence/new_python_deps.py" "$base" "$head"
  [ "$status" -eq 0 ]
  [ "$output" = $'brand-new-dep\npoetry-only-dep\npytest' ]
  # a missing base means every dependency is new; config keys still never appear
  run python3 "$ROOT/.github/actions/import-existence/new_python_deps.py" /nonexistent "$head"
  [ "$status" -eq 0 ]
  [[ "$output" != *"omit"* && "$output" != *"module"* && "$output" != *"branch"* ]]
  [[ "$output" == *"requests"* ]]
  rm -f "$base" "$head"
}

@test "actions/exception-swallow covers all 5 languages" {
  [ -f "$ROOT/.github/actions/exception-swallow/action.yml" ]
  for lang in python js/ts java/cs go any; do
    grep -q "flag .* $lang" "$ROOT/.github/actions/exception-swallow/action.yml"
  done
}

@test "actions/test-delta has tests-not-needed escape hatch" {
  [ -f "$ROOT/.github/actions/test-delta/action.yml" ]
  grep -q 'tests-not-needed' "$ROOT/.github/actions/test-delta/action.yml"
}

@test "actions/test-delta supports skip + configurable bypass-label inputs" {
  grep -q 'skip:' "$ROOT/.github/actions/test-delta/action.yml"
  grep -q 'bypass-label:' "$ROOT/.github/actions/test-delta/action.yml"
  # honored in the script body
  grep -q 'SKIP' "$ROOT/.github/actions/test-delta/action.yml"
  grep -q 'BYPASS_LABEL' "$ROOT/.github/actions/test-delta/action.yml"
}

@test "test-delta bypass is wired gate.yml -> _ai-verification.yml -> action" {
  grep -q 'skip-test-delta:' "$ROOT/.github/workflows/gate.yml"
  grep -q 'test-delta-bypass-label:' "$ROOT/.github/workflows/gate.yml"
  grep -q 'skip-test-delta:' "$ROOT/.github/workflows/_ai-verification.yml"
  grep -q 'skip: ' "$ROOT/.github/workflows/_ai-verification.yml"
}

@test "_ai-verification.yml workflow exists and includes all 5 jobs" {
  [ -f "$ROOT/.github/workflows/_ai-verification.yml" ]
  for job in 'agent-rule-scan' 'import-existence' 'exception-swallow' 'test-delta' 'claude-security-review'; do
    grep -q "$job:" "$ROOT/.github/workflows/_ai-verification.yml"
  done
}

@test "gate.yml wires ai-provenance + ai-verification" {
  grep -q 'ai-provenance:' "$ROOT/.github/workflows/gate.yml"
  grep -q 'ai-verification:' "$ROOT/.github/workflows/gate.yml"
  grep -q '_ai-verification.yml' "$ROOT/.github/workflows/gate.yml"
}

@test "gitleaks ships auth-bypass + default-secret rules" {
  grep -q 'auth-bypass-marker' "$ROOT/policies/.gitleaks.toml"
  grep -q 'id = "default-secret-key"' "$ROOT/policies/.gitleaks.toml"
}

@test "CLAUDE.md.template exists with the kit's conventions" {
  [ -f "$ROOT/policies/CLAUDE.md.template" ]
  grep -qF 'Co-Authored-By: Claude' "$ROOT/policies/CLAUDE.md.template"
  grep -qF 'No personal Gmail, no `*.local`' "$ROOT/policies/CLAUDE.md.template"
}

@test ".claude/settings.json.template exists with Anthropic-mandated denies" {
  [ -f "$ROOT/policies/.claude/settings.json.template" ]
  grep -q 'dangerously-skip-permissions' "$ROOT/policies/.claude/settings.json.template"
  grep -q 'bypassPermissions' "$ROOT/policies/.claude/settings.json.template"
}

# ─── Release-path friction reductions (points 1–5) ──────────────────

@test "cross-OS test matrix is opt-in (default ubuntu) and only on py/ts/go" {
  for w in _python _go _typescript; do
    grep -qF 'os: ${{ fromJSON(inputs.test-os) }}' "$ROOT/.github/workflows/$w.yml"
    grep -qF "default: '[\"ubuntu-latest\"]'" "$ROOT/.github/workflows/$w.yml"   # default = no change
  done
  # java/csharp have no test-os matrix, so gate.yml must NOT pass them test-os
  ! grep -q 'test-os' "$ROOT/.github/workflows/_java.yml"
  ! grep -q 'test-os' "$ROOT/.github/workflows/_csharp.yml"
  [ "$(grep -cF 'test-os: ${{ inputs.test-os }}' "$ROOT/.github/workflows/gate.yml")" -eq 3 ]
}

@test "pr-size-guard applies per-language density weighting (default on)" {
  grep -q 'size-weighting' "$ROOT/.github/actions/pr-size-guard/action.yml"
  grep -q 'weight_pct' "$ROOT/.github/actions/pr-size-guard/action.yml"
  # verbose languages weighted below dense ones
  grep -qE '\*\.go\)\s*echo 55' "$ROOT/.github/actions/pr-size-guard/action.yml"
  grep -qE '\*\.py\|.*echo 100' "$ROOT/.github/actions/pr-size-guard/action.yml"
  # JS gets a higher allowance than Python (weight 0.60 -> effective hard ~1000 vs 600)
  grep -qE '\*\.js\|.*echo 60' "$ROOT/.github/actions/pr-size-guard/action.yml"
}

@test "pr-size-guard keeps standard 400/600 defaults (backward-compatible)" {
  grep -q "default: '400'" "$ROOT/.github/actions/pr-size-guard/action.yml"
  grep -q "default: '600'" "$ROOT/.github/actions/pr-size-guard/action.yml"
}

@test "pr-size-guard adds promotion-intent limits (P5)" {
  grep -q 'promotion-hard-limit' "$ROOT/.github/actions/pr-size-guard/action.yml"
  grep -q 'promotion-base-globs' "$ROOT/.github/actions/pr-size-guard/action.yml"
  grep -q 'promotion-head-globs' "$ROOT/.github/actions/pr-size-guard/action.yml"
  grep -qF 'Promotion PR detected' "$ROOT/.github/actions/pr-size-guard/action.yml"
}

@test "pr-size-guard excludes markdown files from line count by default" {
  grep -qE '^\s*\*\.md\s*$' "$ROOT/.github/actions/pr-size-guard/action.yml"
}

@test "migration-safety separates blocking errors from advisory warnings (P1)" {
  grep -q 'ERRORS=0' "$ROOT/.github/actions/migration-safety/action.yml"
  grep -q 'WARN=0' "$ROOT/.github/actions/migration-safety/action.yml"
  grep -q 'strict-warnings' "$ROOT/.github/actions/migration-safety/action.yml"
}

@test "migration-safety suppresses index warnings on new tables (P1)" {
  grep -q 'NEW_CONTEXT' "$ROOT/.github/actions/migration-safety/action.yml"
  grep -qF 'CREATE\s+TABLE' "$ROOT/.github/actions/migration-safety/action.yml"
}

@test "migration-safety actually checks the dba-approved label (P1)" {
  grep -q 'approval-label' "$ROOT/.github/actions/migration-safety/action.yml"
  grep -q 'has_approval' "$ROOT/.github/actions/migration-safety/action.yml"
}

@test "migration-safety still covers SQL DROP and Alembic op.drop_* (regression)" {
  grep -qF 'TABLE|COLUMN|INDEX|SCHEMA' "$ROOT/.github/actions/migration-safety/action.yml"
  grep -qF 'op\.(drop_table|drop_column|drop_index|drop_constraint)' "$ROOT/.github/actions/migration-safety/action.yml"
}

@test "_python.yml deps-vulns is delta- and remediability-aware (P2/P4)" {
  grep -q 'vuln-delta-only' "$ROOT/.github/workflows/_python.yml"
  grep -q 'vuln-block-unfixable' "$ROOT/.github/workflows/_python.yml"
  grep -qF 'git worktree add --detach /tmp/base-tree' "$ROOT/.github/workflows/_python.yml"
  grep -qF 'pip-audit -r requirements.txt -f json' "$ROOT/.github/workflows/_python.yml"
}

@test "_docker.yml exposes opt-in reproducible Trivy DB (P3)" {
  grep -q 'trivy-skip-db-update' "$ROOT/.github/workflows/_docker.yml"
  grep -q 'skip-db-update:' "$ROOT/.github/workflows/_docker.yml"
}

@test "_typescript.yml hardens non-build installs with --ignore-scripts" {
  # 3 non-build jobs (ESLint, tsc, deps-vulns) harden npm install...
  [ "$(grep -c 'npm ci --ignore-scripts ;;' "$ROOT/.github/workflows/_typescript.yml")" -eq 3 ]
  # ...while BUILD-CLASS jobs (test, frontend-quality) are intentionally left
  # un-hardened because a postinstall lifecycle script may be required to build.
  [ "$(grep -c 'npm ci ;;' "$ROOT/.github/workflows/_typescript.yml")" -eq 2 ]
}

@test "tool-presence probes tolerate a missing tool under set -e" {
  # `shell: bash` runs a step with -e, so a bare `have="$(tool --version ...)"`
  # exits 127 when the tool is absent — which is precisely the case the install
  # branch below each probe exists to handle, leaving that branch unreachable on
  # any runner that does not already ship the tool. Each probe must close with
  # `|| true` INSIDE the command substitution so the lookup can fail and still
  # fall through to the install.
  #
  # Scanned repo-wide and matching HAVE= as well as have=: the first version of
  # this test named only the three files fixed at the time, so six further
  # probes (four in .github/actions/, two in language workflows) stayed broken
  # until a consumer pinned to ubuntu-latest hit them on a production PR.
  #
  # Parens must balance, not just end in `|| true)"`. Appending the guard after
  # the substitution instead of inside it —
  #     have="$(trivy --version | awk '{print $2}') || true)"
  # — still ends in `|| true)"`, still leaves -e to kill the step, and adds an
  # unbalanced paren. A substring check accepts it; counting does not.
  probes=$(grep -rEh '(have|HAVE)="\$\(' "$ROOT/.github/workflows" "$ROOT/.github/actions")
  total=$(printf '%s\n' "$probes" | grep -cE '(have|HAVE)="\$\(')
  guarded=$(printf '%s\n' "$probes" | awk '
    /\|\| true\)"[[:space:]]*$/ {
      opens = gsub(/\(/, "(")
      closes = gsub(/\)/, ")")
      if (opens == closes) n++
    }
    END { print n + 0 }')
  [ "$total" -gt 0 ]
  [ "$guarded" -eq "$total" ]
}

@test "all 4 .claude/hooks scripts exist and are executable" {
  for h in protect-files.sh check-bash-safety.sh check-git-push.sh quality-gate.sh; do
    [ -x "$ROOT/policies/.claude/hooks/$h" ]
  done
}

# ─── New AI-validation fixtures ──────────────────────────────────────

@test "fixture prompt-injection-clauded contains all 3 vector classes" {
  grep -q '<!--.*curl.*bash.*-->' "$ROOT/tests/fixtures/prompt-injection-clauded/CLAUDE.md"
  grep -qE 'You are now' "$ROOT/tests/fixtures/prompt-injection-clauded/CLAUDE.md"
  grep -qE 'curl.*\| bash' "$ROOT/tests/fixtures/prompt-injection-clauded/CLAUDE.md"
}

@test "fixture slopsquat-pkg has obvious fake package names" {
  grep -q 'this-package-definitely-does-not-exist' "$ROOT/tests/fixtures/slopsquat-pkg/requirements.txt"
  grep -q 'this-npm-pkg-definitely-does-not-exist' "$ROOT/tests/fixtures/slopsquat-pkg/package.json"
}

@test "fixture exception-swallow plants all swallow patterns" {
  grep -qE 'except:\s*$' "$ROOT/tests/fixtures/exception-swallow/handler.py"
  grep -qF 'catch (_)' "$ROOT/tests/fixtures/exception-swallow/handler.ts"
  grep -qE 'bypass.*auth' "$ROOT/tests/fixtures/exception-swallow/handler.py"
}

@test "fixture no-test-delta has prod code but no tests" {
  [ -d "$ROOT/tests/fixtures/no-test-delta/src" ]
  [ ! -d "$ROOT/tests/fixtures/no-test-delta/tests" ]
  [ ! -d "$ROOT/tests/fixtures/no-test-delta/test" ]
}

@test "fixture ai-no-trailer has bot commit then human-with-trailer commit" {
  cd "$ROOT/tests/fixtures/ai-no-trailer"
  git log --format='%ae' | grep -qx 'noreply@anthropic.com'
  # Most recent commit should have the trailer
  git log -1 --format='%B' | grep -qF 'Co-Authored-By: Claude'
}
