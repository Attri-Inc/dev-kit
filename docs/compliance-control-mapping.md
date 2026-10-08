# Compliance Control Mapping

Maps each kit gate to the compliance control(s) it (partially) satisfies, so a
green gate run **is** reusable audit evidence. The kit emits a machine-readable
`compliance-evidence.json` artifact on every gate run (which checks ran, their
results, commit, actor, timestamp — see the `gate-passed` job); this doc says
*what each result means* for an auditor.

> A control is rarely satisfied by one check alone — these are **contributing
> evidence**, not a certification. Frameworks overlap heavily (40–85%), so one
> gate often serves several at once.

> **Job packaging (cost optimization):** the quick checks now run as *steps*
> inside three grouped jobs — `hygiene` (identity, editorconfig, pr-size,
> commit-msg, codeowners, markdown, typos), `code-scan` (trojan-source, MCP
> allowlist, log-hygiene), and `dep-scan` (dep-cooldown, license, vuln-prioritize,
> malicious-deps, conftest) — rather than one job each. **Coverage is identical**;
> only the `compliance-evidence.json` `checks` keys changed from per-check to the
> three group ids. See `docs/cost-optimization.md`.

| Kit gate / action | SOC 2 | ISO 27001:2022 | NIST SSDF (800-218) | PCI-DSS 4.0 | HIPAA §164 |
|---|---|---|---|---|---|
| **Required PR + review** (governance) | CC8.1 | A.8.32 | PW.7 | 6.4.2 | — |
| **identity-check** (committer domain) | CC6.1 | A.8.2 | — | — | .312(d) |
| **detect-secrets + trufflehog** | CC6.1 | A.8.24 | PW.4 | 6.3.1 | .312(a) |
| **CodeQL/Semgrep/Bandit SAST** | CC7.1 | A.8.28 | PW.7, PW.8 | 6.2.4 | — |
| **pip-audit/npm-audit/Trivy SCA** | CC7.1 | A.8.8 | PW.4, RV.1 | 6.3.3 | — |
| **vuln-prioritize (KEV+EPSS)** | CC7.1 | A.8.8 | RV.1, RV.3 | 6.3.1 | — |
| **diff-coverage** (tests on new code) | CC8.1 | A.8.29 | PW.8 | 6.2.4 | — |
| **license-check** | — | A.5.32 | PS.3 | — | — |
| **SBOM (CycloneDX + SPDX)** | CC7.1 | A.8.30 | PS.3 | — | — |
| **Sigstore attest + verify-attestation** | CC7.1 | A.8.30 | PS.2, PS.3 | — | — |
| **OpenSSF Scorecard** | CC7.1 | A.8.28 | PO.3 | — | — |
| **migration-safety** | CC8.1 | A.8.32 | — | 6.5.x | .312(c) |
| **log-hygiene (no secrets/PII in logs)** | CC6.1 | A.8.12 | — | 3.x, 10.x | .312(b), Privacy |
| **CODEOWNERS check** | CC8.1 | A.5.2 | PW.7 | 6.4.2 | — |
| **pr-size-guard** | CC8.1 | A.8.32 | PW.7 | 6.4.2 | — |
| **conftest-policy** (policy-as-code) | CC7.1 | A.8.9 | PO.1 | 2.2 | .312(a) |
| **Branch protection / no-bypass** (manual; see governance-policy) | CC8.1 | A.8.4 | PS.1 | 6.4.1 | .312(a) |
| **compliance-evidence.json artifact** | CC3.2, CC8.1 | A.5.28 | — | 10.x | .312(b) |

## How to use the evidence

1. The `compliance-evidence` artifact on each gate run records the change ID
   (commit), who triggered it, when, and every gate's result — a tamper-evident,
   timestamped change-control record (SOC2 CC8.1 / PCI 6.4.2 / HIPAA audit).
2. For an audit, point the assessor at this mapping + the artifacts (and the
   nightly SBOM/attestation) rather than collecting screenshots.
3. **Gaps the kit does NOT evidence** (apply/track separately): access reviews,
   separation-of-duties on deploy approvals (GitHub environments — manual),
   immutable long-term log retention, and the org-level controls in
   [`governance-policy.md`](governance-policy.md) (2FA, push protection, base
   permission). The audit only proves what actually ran.

## Policy-as-code (Conftest/OPA)

The `conftest-policy` gate evaluates repo config (k8s manifests, Dockerfiles,
`terraform plan` JSON, any YAML/JSON) against **org Rego policies** — encode
custom controls (e.g. "all storage must declare encryption", "no `:latest`
images", "resources require a cost-center tag") as versioned, reviewed code.
It is **consume-if-present**: it runs only when the repo ships `policy/*.rego`
(or `.config/policy/*.rego`), so it is zero-impact until you adopt it.
