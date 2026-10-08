# Tier Specification

What runs at each tier and why.

> **Job packaging:** the quick checks listed below run as *steps* inside three
> grouped jobs — `hygiene`, `code-scan`, `dep-scan` — to cut GitHub's per-job
> minute rounding (same checks, same coverage). See `docs/cost-optimization.md`.

## `tier: dev`
**Trigger:** push to `dev` branch, or PR with `base: dev`
**Target time:** under 2 minutes
**Goal:** stop bad code at the earliest possible point

| Job | What | Hard fails? |
|---|---|---|
| actionlint | Workflow YAML lint | Yes (warning level) |
| detect-secrets + trufflehog | Secret scan (verified-only; current tree at `dev`, full history at `qa`/`main`) | Yes |
| identity-check | Reject emails outside `allowed-author-domains` (`*.local`, Gmail, …). Off when the input is empty | Soft fail (warning only at `dev`) |
| commit-msg | Conventional Commits PR title | No by default (warn; set `commit-msg-fail-level: error` to block) |
| editorconfig | Whitespace/EOL policy | Yes |
| pr-size | Hard fail at 600 LOC, soft warn at 400 (PR only). Promotion PRs (dev→main etc.) use higher limits (1200/2000). Excludes lockfiles, generated files, and Markdown (`*.md`). **Language-weighted by default** (`pr-size-weighting`): verbose Go/Java/Terraform/C# count less per line than dense Python/TS, since the limit models review effort | Yes |
| Lang lint | Ruff / Biome / Checkstyle / golangci-lint / etc. | Yes |
| Lang type-check | mypy / tsc / etc. | Soft fail at dev |
| Lang test | pytest / vitest / go test / etc. | Yes |
| Cross-OS test matrix | Opt-in via `test-os` (default `["ubuntu-latest"]`). Set `["ubuntu-latest","macos-latest","windows-latest"]` to run Python/TS/Go tests cross-platform (libs/CLIs). Coverage/lint run once on Linux | — |
| Diff coverage | % of CHANGED lines covered by tests (patch coverage, via diff-cover) — `diff-coverage-min` default 80 | Warn by default (`diff-coverage-enforcement: fail` to block); PR-only |

## `tier: qa` and `tier: uat`
**Trigger:** PR with `base: qa` or `base: uat`
**Target time:** ~5 minutes
**Goal:** integration-ready code; full review and security checks

Adds on top of `dev`:

| Job | What |
|---|---|
| markdown-lint | Markdown style |
| typo-check | Documentation typos |
| identity-check | **Hard fail** at qa/uat (no soft) |
| Lang security | Bandit / Semgrep / SpotBugs / govulncheck |
| Lang dep-vulns | pip-audit / npm audit / OWASP Dep-Check. Blocks only vulns *introduced* by the PR that have a fix available; inherited or unpatchable vulns are advisory (tunable via `vuln-delta-only` / `vuln-block-unfixable`) |
| License compliance | Trivy-detected dependency licenses vs policy: DENY strong/network copyleft (GPL/AGPL/SSPL/…), WARN weak copyleft (LGPL/EPL/…), ALLOW permissive. Warn by default (`license-enforcement: fail` to block); reviewed exceptions in `.attri-dev-kit-license-allowlist` |
| Log hygiene (PR) | Changed lines: HIGH = secret/PII used as a value inside a log/print call; MEDIUM = stray debug print. Diff-scoped, warn by default (`log-hygiene-enforcement: fail` to block on HIGH) |
| Vuln prioritization | Ranks dependency CVEs by real-world exploitability: 🔴 CISA KEV (actively exploited), 🟠 EPSS ≥ threshold, ⚪ rest. Warn by default; `vuln-prioritize-enforcement: fail` blocks per `vuln-prioritize-fail-on` (kev/epss/both) |
| Malicious deps | OSV malicious-packages (MAL-*) — known backdoored packages in the dep tree, distinct from CVEs. Warn by default (`malicious-deps-enforcement: fail` strongly recommended) |
| Dep cooldown + confusion (PR) | Newly-added npm/PyPI deps published < `dependency-cooldown-days` (default 7) are flagged; internal-scope deps without a pinned private registry flagged (`internal-scopes`). Warn by default (`dep-supply-chain-enforcement`) |
| Trojan Source + homoglyph | Invisible/BiDi Unicode (CVE-2021-42574) + mixed-script (homoglyph) identifiers across all source (diff-scoped on PRs). Warn by default (`trojan-source-enforcement`) |
| MCP allowlist | MCP servers in `.mcp.json`/`mcp_servers.json` checked against `mcp-allowlist` (empty = inventory only). Warn by default (`mcp-allowlist-enforcement`) |
| Policy-as-code (Conftest) | Evaluates repo config against org Rego policies. Consume-if-present (runs only when `policy/*.rego` exists); warn by default (`conftest-enforcement`) |
| Compliance evidence | `gate-passed` emits `compliance-evidence.json` (gate results + commit/actor/timestamp) as an artifact for SOC2/ISO/PCI audit trails. See `docs/compliance-control-mapping.md` |
| CODEOWNERS (PR) | CODEOWNERS exists, validates via GitHub's `codeowners/errors` API, has a catch-all `*`. Warn by default (`codeowners-enforcement`) |
| Docker | hadolint + Trivy + Dockle (if `Dockerfile` present) |
| Terraform | Checkov + Trivy IaC (if `*.tf` present) |

## `tier: main`
**Trigger:** PR with `base: main`
**Target time:** ~10–15 minutes
**Goal:** production-grade artifact, audit-ready, signed

Adds on top of `qa/uat`:

| Job | What |
|---|---|
| OpenSSF Scorecard | Continuous repo health metrics → Security tab (nightly by default) |
| SBOM (Syft) | CycloneDX + SPDX, attached as artifact (nightly by default) |
| Sigstore attest | Keyless OIDC build provenance attestation (nightly by default — 24h SLA) |
| Attestation verify | The freshly-created attestation is verified back (`gh attestation verify`, advisory self-check). Closes "sign without verify". |
| Migration safety | Per-merge, never deferred. Hard-fails on destructive DDL (DROP, TRUNCATE, NOT NULL on populated columns); untimed indexes are **advisory** and suppressed on new/just-created tables. `migration: dba-approved` label waives a hard fail; `strict-warnings: true` re-promotes warnings to blocking |
| Infracost (if Terraform + key set) | PR-comment cost diff |

**Attestation frequency:** Scorecard, SBOM, and Sigstore signing only run on `schedule:` triggers by default — consumer adds a daily cron to their wrapper workflow (see examples). Saves ~$80-100/mo in Actions minutes per active org. Set `attestation-frequency: per-commit` in the gate call to restore per-merge attestation.

## Custom-tier overrides

Pass an explicit `tier` value if your branch model is non-standard:

```yaml
with:
  tier: main      # force prod-tier even on a PR to a non-main branch
  run-supply-chain: true
```

## Why this layering?

Research (Cisco SmartBear study, Google, BSSW) shows reviewer effectiveness drops sharply above 400 LOC. The kit fails the cheap things on every push and reserves expensive checks (SBOM/Sigstore/Scorecard) for the merge gate where they actually matter.

Audit-driven choices:
- **Hard 600-line PR limit at qa/uat/main** — caps the 50K-line mega-merges
- **Identity hard-fail at qa/uat** — stops 250+ pushes from `.local`/Gmail emails
- **Migration safety at main** — would have caught `psi_automation-be`'s `db.sqlite3` commit
- **Secret scan on every push** — would have caught `LM_product_be`'s live Postgres password
