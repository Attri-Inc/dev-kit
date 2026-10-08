# attri-dev-kit

> Reusable GitHub Actions workflow library: tiered CI quality and security gates for any repo.
> Opt-in. Multi-language. License-clean. Zero side effects on repos that don't call it.

---

## What it is

A single reusable workflow + a small set of composite actions that any repo can opt into by adding **one file** to `.github/workflows/`. The kit auto-detects the language stack and runs lint, type-check, tests, secret-scanning, identity-check, PR-size-guard, and supply-chain checks at three tiers: `dev`, `qa/uat`, and `main`.

Built almost entirely from existing, license-clean OSS GitHub Actions (MIT, Apache-2.0, BSD). The only original code is `identity-check`, `detect-stack`, `detect-secrets`, `pr-size-guard`, `migration-safety`, and `build-artifact` — all thin shell wrappers around proven tools.

## Why it exists

Commit audits of real organizations keep finding the same failure classes: live committed credentials, direct unreviewed pushes to protected branches, commits from personal or machine-local emails, auth bypasses merged to production, and PRs too large to review. The kit gates new code against those patterns.

## Opt in

Copy this into any repo at `.github/workflows/attri-dev-kit.yml`:

```yaml
name: Attri Dev Kit
on:
  push:
    branches: [main, master, dev, dev-*, develop, qa, uat, staging]
    paths-ignore: ['**/*.md', 'docs/**', '.github/ISSUE_TEMPLATE/**', '.github/CODEOWNERS', 'LICENSE', '*.txt', '.gitignore', '.editorconfig']
  pull_request:
    branches: [main, master, dev, dev-*, develop, qa, uat, staging, release/*]
    paths-ignore: ['**/*.md', 'docs/**', '.github/ISSUE_TEMPLATE/**', '.github/CODEOWNERS', 'LICENSE', '*.txt', '.gitignore', '.editorconfig']
  schedule:
    - cron: '17 7 * * *'   # daily nightly attestation (Scorecard + SBOM + Sigstore)
concurrency:
  group: attri-dev-kit-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
permissions:
  contents: read
  pull-requests: write
  security-events: write
  id-token: write
  attestations: write
  actions: read
jobs:
  attri-dev-kit:
    uses: Attri-Inc/dev-kit/.github/workflows/gate.yml@main
    with:
      tier: auto
      languages: auto
      fail-on: high
    # The kit needs no secrets. Pass only the optional ones you use. Avoid
    # `secrets: inherit`: it hands every repo and org secret to this workflow.
    # secrets:
    #   GOOGLE_CHAT_WEBHOOK_URL: ${{ secrets.GOOGLE_CHAT_WEBHOOK_URL }}  # alert on gate failure
    #   ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}              # claude-code-security-review
```

The `paths-ignore`, `schedule`, and `concurrency` blocks are not optional — they reduce per-repo Actions spend by ~50% (docs PRs skip CI, nightly attestation, force-push cancellation). Pick the example matching your stack from [`examples/`](examples/) for stack-specific overrides.

## What runs at each tier

| Check | dev | qa/uat | main |
|---|:---:|:---:|:---:|
| Workflow YAML lint (actionlint) | ✅ | ✅ | ✅ |
| Secret scan (detect-secrets + trufflehog OSS verified-only) | ✅ HEAD~1 | ✅ history | ✅ history |
| Identity check (committer email policy) | ✅ warn | ✅ fail | ✅ fail |
| Conventional commits (PR title) | ✅ warn | ✅ warn | ✅ warn |
| Editorconfig | ✅ | ✅ | ✅ |
| Per-language lint + format + type-check | ✅ | ✅ | ✅ |
| Unit tests | ✅ | ✅ | ✅ |
| Full test suite + coverage | — | ✅ | ✅ |
| Per-language security SAST | — | ✅ | ✅ |
| Dependency vulnerability scan | — | ✅ | ✅ |
| PR size guard (hard 600 / soft 400) | ✅ | ✅ | ✅ |
| Markdown lint + typo check | — | ✅ | ✅ |
| Container scan (hadolint + trivy + dockle) | — | ✅ if Dockerfile | ✅ |
| IaC scan (checkov + trivy) | — | ✅ if `*.tf` | ✅ |
| OpenSSF Scorecard | — | — | ✅ nightly* |
| SBOM (Syft, CycloneDX + SPDX) | — | — | ✅ nightly* |
| Sigstore keyless signing of artifact | — | — | ✅ nightly* |
| Migration safety check (SQL + Alembic + Django) | — | — | ✅ per-merge |
| Google Chat alert on failure | ✅† | ✅† | ✅† |

† Fires only when the caller passes the `GOOGLE_CHAT_WEBHOOK_URL` secret — see [Failure notifications](#failure-notifications-google-chat).

\* By default, attestation jobs run **once daily** on the `schedule:` cron in your wrapper workflow (see examples). This saves ~$80-100/mo of Actions minutes per active org. Set `attestation-frequency: per-commit` in the gate call to restore per-merge signing (legacy behavior). Migration safety always runs per-merge regardless.

## Failure notifications (Google Chat)

When any gate job fails, the kit posts a card to a Google Chat space with the
repo, branch, commit, who triggered it, the specific jobs/steps that failed,
and a link to the run.

**Setup (~2 min):**

1. In the target Google Chat space: **Apps & integrations → Manage webhooks →
   Add webhook**. Copy the URL (`https://chat.googleapis.com/v1/spaces/…`).
   (Your Workspace admin must allow incoming webhooks if they're disabled.)
2. In GitHub: **your org → Settings → Secrets and variables → Actions →
   New organization secret** named `GOOGLE_CHAT_WEBHOOK_URL`, paste the URL.
   Scope it to the repos that should alert.
3. In each repo's wrapper workflow, pass it to the gate:
   ```yaml
   secrets:
     GOOGLE_CHAT_WEBHOOK_URL: ${{ secrets.GOOGLE_CHAT_WEBHOOK_URL }}
   ```

Repos that don't pass the secret don't notify — the action no-ops on an empty
webhook. The URL is the only credential, so treat it as a secret; no GCP
project or service account is required for one-way alerts.

## AI-verification checks

Hard-block PRs introducing AI-generated patterns the deep-research pass surfaced as the highest-risk classes. Wired into `_ai-verification.yml` and required by `gate-passed`.

- **`lint-disable`** — blocks PRs that add unjustified `# noqa`, `# type: ignore`, `// @ts-ignore`, `// eslint-disable`, etc. Bypass via inline `# reason: <why>` or `lint-disable-approved` PR label. Escalates message when the disable was added by an AI-authored commit.

## Supported languages

Auto-detected via file presence. Override with `languages: python,terraform` etc. if needed.

| Language | Tools |
|---|---|
| Python | Ruff, mypy, Bandit, pip-audit, pytest (poetry/pipenv/uv/pdm/pip) |
| TypeScript / JavaScript | Biome (default) or ESLint+Prettier, tsc, Semgrep, npm audit, jest/vitest |
| Java | Checkstyle, SpotBugs, OWASP Dependency-Check, Maven/Gradle |
| Go | golangci-lint, govulncheck, `go test` |
| Terraform | terraform fmt+validate, TFLint, Checkov, Trivy IaC, optional Infracost + remote `plan` |
| Docker | hadolint + Trivy + Dockle (matrix-fan-out across all Dockerfiles) |
| Shell | ShellCheck, shfmt |
| C# | dotnet format, build, test |

## Documentation

- [Onboarding checklist](docs/per-repo-onboarding-checklist.md) — three steps, five minutes
- [Tier specification](docs/tier-spec.md) — exactly what runs where, why
- [Language support](docs/languages.md) — per-stack details
- [Allowlist format](docs/allowlist.md) — silencing reviewed false positives
- [Upgrading the kit](docs/upgrading.md) — version migration
- [Tooling rationale](docs/tooling-rationale.md) — why Sonar / Codacy / etc. are NOT in the kit
- [Kit scope](docs/scope.md) — what's in (CI), what's out (infra, monitoring, on-call)

## Examples

Each `examples/<stack>/` folder is a complete `.github/workflows/attri-dev-kit.yml` you can copy-paste.

- [`examples/python-fastapi`](examples/python-fastapi)
- [`examples/nextjs-app`](examples/nextjs-app)
- [`examples/go-mcp-server`](examples/go-mcp-server)
- [`examples/terraform-iac`](examples/terraform-iac)
- [`examples/java-spring`](examples/java-spring)
- [`examples/multi-language-monorepo`](examples/multi-language-monorepo)

## Onboarding helper

```bash
./scripts/install-pilot.sh /path/to/target-repo <stack>
# stack ∈ {python, typescript, go, terraform, java, monorepo}
```

Drops `.github/workflows/attri-dev-kit.yml` into the target repo on a new branch. Open the PR yourself — the kit never auto-pushes.

## Versioning

The kit tracks `main`. Consumers reference `gate.yml@main`.

- **No release ceremony, no version tags.** Merge to main = ship.
- **Pinning a SHA has a limit** — it does not freeze the composite actions.
  See [Upgrading](docs/upgrading.md#pinning-strategy).
- **Branch protection on main is the safety net.** The kit gates itself on every
  PR; broken commits don't reach main.
- **Nightly attestation** of the latest main commit: Sigstore-keyless-signed
  via OIDC with SLSA L3 provenance attached. Latency SLA: within 24h of
  merge. For per-merge signing (legacy behavior), set
  `attestation-frequency: per-commit` in the gate call — increases monthly
  Actions spend by ~$80-100 for the average active repo.

## Escape hatch

Drop a `.attri-dev-kit-skip` file in your repo root with a one-line reason. The kit no-ops with a notice. Useful for empty/legacy repos.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).

## Security

To report a vulnerability in the kit itself, see [SECURITY.md](SECURITY.md).
