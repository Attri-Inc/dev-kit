# Kit scope — what's in, what's out

> Definitive boundary for `attri-dev-kit`. If something isn't here, it's out.
> "Is X in scope?" should be answerable from this doc in 10 seconds.

---

## In scope

The kit owns **CI gates**. Deployment (CD) is out of scope — see below.

### CI gate (`gate.yml`)

| Capability | Where |
|---|---|
| Workflow YAML lint (actionlint) | universal |
| Secret scanning (detect-secrets + trufflehog --only-verified) | universal |
| Committer-identity check (allowlisted email domains) | universal |
| Editorconfig + markdownlint + commit-msg lint + typo-check | universal |
| PR-size guard (with `pr-size: bypass-approved` label) | PR only |
| AI-provenance labeling | PR only |
| AI-specific verification: agent-rule-scan, import-existence, exception-swallow, test-delta gate, claude-code-security-review, **lint-disable-detector** | universal |
| Per-language pipeline: lint, format, type-check, tests, security, dep-CVE | per-language, auto-detected |
| Migration safety (Alembic + Django + raw SQL) | PR only |
| Supply-chain: OpenSSF Scorecard, CycloneDX + SPDX SBOM, Sigstore attestation | main tier |
| Google Chat alert on gate failure (repo, branch, commit, author, failed jobs/steps, run link) | universal, when `GOOGLE_CHAT_WEBHOOK_URL` org secret is set |

### Composite actions (callable directly)

`notify-gchat-ci` · `pr-size-guard` · `test-delta` · `detect-secrets` · `detect-stack` · `identity-check` · `ai-provenance` · `agent-rule-scanner` · `exception-swallow` · `import-existence` · `migration-safety` · `lint-disable-detector` · `build-artifact`

---

## Out of scope (and why)

### Deployment (CD)

- **Deploy workflows** — deploy targets differ too much between organizations (cloud, registry, rollout strategy) for one shared workflow. The kit checks code; how it ships is per-repo.

### Infrastructure provisioning

- **Terraform / Bicep / ARM templates** — different lifecycle (slow-changing, often per-environment-specific). The kit *scans* IaC, it does not apply it.
- **Cloud resource creation** — stand resources up manually or via your repo's own IaC.
- **DNS / networking** — out.

If you need an infra-provisioning kit, that's a separate project. Not blocking, but also not coming.

### Operational

- **Secret rotation** — the kit detects leaked secrets but does NOT rotate them. Rotation is a runbook + a call to your secret manager, not a CI step.
- **Monitoring / observability** — Datadog, SigNoz, OpenReplay setup: out. Each repo wires its own.
- **On-call / incident response** — PagerDuty, Opsgenie: out.
- **Runbooks** — the kit ships docs about itself; per-repo operational runbooks live in the repo.

### Code-quality dashboards

- **SonarQube / SonarCloud / Codacy** — see [`tooling-rationale.md`](./tooling-rationale.md) for the rationale. Pass/fail at PR time is the kit's contract; separate dashboards are out.

### Code authoring

- **Code generation / scaffolding** — the kit doesn't `init` new repos. Use `cookiecutter`, `degit`, or just copy from `examples/`.
- **Auto-fix / auto-PR** — the kit reports findings but does NOT push fixes back to consumer repos. By design.

### Per-repo testing infrastructure

- **Integration / e2e test orchestration** — kit runs unit + lint + security; integration/e2e is per-repo.
- **Test data fixtures, mock services, test containers** — per-repo.

---

## "Is this in scope?" decision tree

```
┌───────────────────────────────────────────────────────────────┐
│ Does it run on EVERY PR across the org?                       │
│                                                                │
│   YES  → in scope (or could be — open a kit issue)             │
│   NO   → out of scope (per-repo concern)                       │
│                                                                │
│ Does it write to consumer repos (PRs, force-pushes, etc.)?     │
│                                                                │
│   YES  → out of scope (kit is read-only on consumers)          │
│                                                                │
│ Does it require state outside GitHub Actions (cron, daemon)?   │
│                                                                │
│   YES  → out of scope (kit is stateless, GH-Actions-only)      │
└───────────────────────────────────────────────────────────────┘
```

---

## How to expand scope

Open a kit GitHub issue describing:

1. The problem (real, with a consumer-repo example)
2. Why it can't be solved per-repo
3. What kit primitive (workflow / composite / config input) would address it
4. Estimated maintenance burden on the kit team

If accepted, update this doc as part of the implementing PR.

---

*Boundary clarity is a feature. If you find yourself wishing the kit did X, check this doc first; if X isn't here AND has no decision-tree path to YES, it's intentionally out.*
