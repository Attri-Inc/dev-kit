# Tooling rationale

> Why the kit picks one tool over another. When a "should we add X?" question
> comes up, the answer should already be here.

---

## SonarQube / SonarCloud / SyncCube

**Status:** **Not in the kit.** Existing tools cover the same ground.

### What Sonar would give us

- Code-quality metrics (cognitive complexity, duplication, maintainability)
- Security hotspots (overlap with bandit / semgrep)
- Test-coverage tracking dashboards
- Multi-language support out of the box

### Why we don't add it

| Reason | Detail |
|---|---|
| **Overlap with existing kit tools** | bandit (Python security), pip-audit (deps), npm-audit (deps), trufflehog (secrets), claude-code-security-review (AI-specific patterns), and the kit's own AI-verification jobs already cover security and supply-chain. Code quality is covered by ruff / black / eslint / prettier per language. |
| **Cost** | SonarCloud is per-LOC for private repos; SonarQube is self-hosted ops burden. Marginal value vs. existing free tooling doesn't justify either. |
| **Dashboard fragmentation** | Sonar wants you to look at its dashboard. The kit's philosophy is "pass/fail at PR time, no separate dashboard." Adding another portal that nobody checks is worse than not having one. |
| **No demand signal** | Nobody has filed a kit issue asking for it. Decisions like this should come from real consumer demand, not "industry-standard tool" pressure. |

### When this might change

- A consumer repo files a kit issue with a specific gap they hit (e.g., "I need cyclomatic-complexity gating")
- Compliance audit explicitly requires SonarQube SAST coverage for SOC 2 / similar
- The kit's own ruff / bandit / semgrep coverage proves insufficient on a real incident

If any of those happen, reopen the question. Until then: existing tooling is the call.

---

## Other tools considered + rejected

| Tool | Status | Reason |
|---|---|---|
| Codacy | Not in kit | Same overlap argument as Sonar; commercial cost |
| Snyk (paid SAST) | Not in kit | trufflehog + pip-audit + npm-audit cover the secret + dep dimensions; OSS-tier Snyk is OK as a side-tool but not in the kit's required path |
| GitGuardian | Not in kit | Org-level GitHub secret scanning + trufflehog is enough |
| Coveralls / Codecov | Optional | Codecov is wired in via `codecov-action` when `CODECOV_TOKEN` is set; not required |

---

## Tools the kit DOES use, and why

| Tool | What it does | Why we picked it |
|---|---|---|
| `ruff` (Python) | Lint + format | Fastest, replaces flake8 + black + isort. Maintained, pinned. |
| `mypy` (Python) | Type check | Standard. Strict mode optional per repo. |
| `bandit` (Python) | Security lint | Free, fast, low false-positive on the rules we keep enabled. |
| `pip-audit` (Python) | Dep CVE check | Free, official PyPA tool. |
| `eslint` + `prettier` (TS/JS) | Lint + format | Standard. Honors repo's `.eslintrc` + `.prettierrc`. |
| `tsc --noEmit` (TS) | Type check | Standard. |
| `npm audit` (TS/JS) | Dep CVE check | Free, npm-native. |
| `trufflehog` (all langs) | Secret scan (verified-only) | Verifies live API keys, near-zero false-positive rate. |
| `detect-secrets` (all langs) | Secret scan (regex) | Catches what trufflehog doesn't; baseline-friendly. |
| `actionlint` | Workflow YAML lint | Catches half the GH Actions errors before runtime. |
| `shellcheck` | Bash lint | Standard. |
| `markdownlint` | Doc lint | Cheap, prevents broken README links. |
| `claude-code-security-review` | AI security patterns | Anthropic-maintained, catches AI-specific risks. |
| `sigstore/cosign` | Build attestation | Supply-chain trust signal. |
| `cyclonedx` + `spdx` SBOMs | Dependency manifest | Required for enterprise customers. |

---

## How to propose a new tool for the kit

1. Open a kit GitHub issue with: name, what it covers, what kit tool it'd replace or augment, license cost, runtime overhead.
2. Reference a real consumer repo where the absence of this tool led to a problem.
3. If accepted, ship it behind an opt-in input first.
4. Promote to default-on after 2 weeks of opt-in feedback.

If the proposal is "Sonar / Codacy / Snyk", read this doc first — odds are the answer is still no.

---

*Last updated: 2026-05-09. Update on each tool decision so the rationale stays current.*
