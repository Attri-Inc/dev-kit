# Per-repo configuration: `devkit.ini`

Drop a `devkit.ini` at the root of a consumer repo to turn individual checks
off or change gate settings for that repo, without touching its workflow file.
The gate reads it on every run. Repos without the file see no change.

```ini
# devkit.ini
[kit]
enabled = true

[skip]
# check = reason   (one line per check; the reason is shown in the run summary)
python.type-check = mypy breaks on generated protobuf stubs, tracked in ENG-123
hygiene.typos = clinical vocabulary trips the dictionary

[settings]
# key = value   (keys are the gate's workflow inputs)
python-version = 3.12
python-test-command = uv run pytest -m "not slow"
pr-size-soft-limit = 600
fail-on = critical
```

## Format

- INI: `[section]` headers and `key = value` lines.
- `#` or `;` at the start of a line is a comment. Inline comments after a value
  are **not** supported, because reasons often contain `#`.
- Section names, keys and check names are case-insensitive. Values keep their case.
- A value may be wrapped in double quotes; the quotes are stripped. Everything
  after the first `=` is the value, so `=` inside a value is fine.
- A UTF-8 BOM and CRLF line endings are tolerated.
- When a key appears twice, the last one wins.

## Which copy of the file applies

| Event | Copy used |
|---|---|
| `push`, `schedule`, `workflow_dispatch` | The file at the pushed ref |
| `pull_request` | The file on the **base branch** |

A pull request cannot weaken the gate that is checking it. When a PR changes
`devkit.ini`, the run posts a notice and shows the diff in the *Detect stack*
job summary; the new copy takes effect once the PR is merged.

## What you see

- The *Detect stack* job summary lists every skipped check with its reason and
  every setting the file changed. A skip without a reason is still honoured but
  flagged there and as a warning annotation.
- The `compliance-evidence.json` artifact records the same under `config`, so
  audits can see exactly what a repo turned off and why.
- Unknown sections, keys, check names and values of the wrong type or outside
  the allowed set produce a **warning**; the entry is ignored.
- Trying to skip a protected check or set a locked setting produces an
  **error**: the entry is ignored, the run continues so you still see the
  other results, and `gate-passed` fails until the entry is removed.

## `[kit]`

| Key | Values | Meaning |
|---|---|---|
| `enabled` | `true` (default), `false` | `false` turns the whole kit off for the repo, exactly like the `.attri-dev-kit-skip` file. |
| `reason` | text | Shown in the run log when `enabled = false`. |

## `[skip]`

One line per check: `name = reason`. Names are listed below. A whole-job name
(for example `python`) skips that whole pipeline, including every `python.*`
entry. Skipped jobs show as *skipped* in the run, not failed, and
`gate-passed` treats them as passed.

Notes:

- `typescript.lint` covers both Biome and ESLint, whichever the repo uses.
- `sbom` also disables `attest`, which consumes the SBOM.
- `hygiene`, `code-scan`, `dep-scan` and `secrets-scan` cannot be skipped as
  whole jobs because each contains a protected check. Skip their individual
  steps instead.

### Protected checks

These are the kit's reason for existing and cannot be skipped from the file:

- `secrets-scan` — detect-secrets + trufflehog on the diff and history
- `hygiene.identity` — Committer email-domain policy
- `code-scan.trojan-source` — Trojan Source + homoglyph scan
- `dep-scan.malicious-deps` — OSV malicious-package scan

### All check names

Generated from `.github/actions/repo-config/checks.txt`, which is the single
source of truth; the self-test fails if this table and the file drift.

| Check | Protected | What it covers |
|---|---|---|
| `actionlint` |  | Lints the repo's own workflow files |
| `secrets-scan` | yes | detect-secrets + trufflehog on the diff and history |
| `ai-provenance` |  | Detects AI-authored commits and labels the PR |
| `ai-verification` |  | All AI-pattern checks (see ai-verification.* below) |
| `python` |  | The whole Python pipeline |
| `typescript` |  | The whole TypeScript/JavaScript pipeline |
| `java` |  | The whole Java pipeline |
| `go` |  | The whole Go pipeline |
| `terraform` |  | The whole Terraform pipeline |
| `docker` |  | The whole Docker pipeline |
| `shell` |  | The whole shell-script pipeline |
| `csharp` |  | The whole C# pipeline |
| `scorecard` |  | OpenSSF Scorecard (main tier, public repos) |
| `sbom` |  | SBOM generation; also disables attest, which consumes it |
| `attest` |  | Sigstore attestation of the build artifact |
| `migration-safety` |  | Destructive DB migration detection (main tier) |
| `hygiene.identity` | yes | Committer email-domain policy |
| `hygiene.editorconfig` |  | editorconfig-checker |
| `hygiene.lf` |  | CRLF shell-script detection |
| `hygiene.pr-size` |  | PR size guard (soft/hard line limits) |
| `hygiene.commit-msg` |  | Conventional-commit message lint |
| `hygiene.codeowners` |  | CODEOWNERS presence/coverage |
| `hygiene.markdownlint` |  | markdownlint (qa/main tiers) |
| `hygiene.typos` |  | Typo check (qa/main tiers) |
| `code-scan.trojan-source` | yes | Trojan Source + homoglyph scan |
| `code-scan.mcp-allowlist` |  | MCP server allowlist |
| `code-scan.log-hygiene` |  | Secrets/PII in log statements |
| `dep-scan.cooldown` |  | Dependency cooldown + confusion |
| `dep-scan.license` |  | License compliance |
| `dep-scan.vuln-prioritize` |  | KEV + EPSS vulnerability prioritisation |
| `dep-scan.malicious-deps` | yes | OSV malicious-package scan |
| `dep-scan.conftest` |  | Policy-as-code (Conftest) |
| `ai-verification.agent-rule-scan` |  | Prompt-injection scan of agent rule files |
| `ai-verification.import-existence` |  | Hallucinated-dependency check |
| `ai-verification.exception-swallow` |  | Swallowed-exception detector |
| `ai-verification.test-delta` |  | Code changed without tests |
| `ai-verification.lint-disable` |  | Unjustified lint-disable comments |
| `ai-verification.claude-security-review` |  | Claude security review (main tier) |
| `python.pre-commit` |  | Repo's own pre-commit hooks |
| `python.lint` |  | Ruff / Black |
| `python.type-check` |  | mypy |
| `python.security` |  | Bandit |
| `python.deps-vulns` |  | pip-audit |
| `python.test` |  | pytest |
| `python.diff-coverage` |  | Diff-coverage gate |
| `typescript.lint` |  | Biome or ESLint |
| `typescript.type-check` |  | tsc --noEmit |
| `typescript.security` |  | Semgrep |
| `typescript.deps-vulns` |  | npm audit |
| `typescript.test` |  | Test runner |
| `typescript.diff-coverage` |  | Diff-coverage gate |
| `typescript.build` |  | Production build |
| `typescript.frontend-quality` |  | Lighthouse + bundle budgets |
| `java.lint` |  | Checkstyle |
| `java.spotbugs` |  | SpotBugs |
| `java.deps-vulns` |  | OWASP Dependency-Check |
| `java.test` |  | Test runner |
| `java.diff-coverage` |  | Diff-coverage gate |
| `go.lint` |  | golangci-lint |
| `go.vulncheck` |  | govulncheck |
| `go.build` |  | go build |
| `go.test` |  | go test |
| `go.diff-coverage` |  | Diff-coverage gate |
| `terraform.fmt-validate` |  | terraform fmt + validate |
| `terraform.tflint` |  | tflint |
| `terraform.checkov` |  | Checkov |
| `terraform.plan` |  | terraform plan + PR comment |
| `terraform.trivy-iac` |  | Trivy IaC scan |
| `terraform.infracost` |  | Infracost (main tier) |
| `docker.hadolint` |  | hadolint |
| `docker.build-and-scan` |  | Build + Trivy image scan + Dockle |
| `shell.shellcheck` |  | shellcheck |
| `shell.shfmt` |  | shfmt |
| `csharp.security` |  | Semgrep |
| `csharp.format` |  | dotnet format |
| `csharp.build-test` |  | Build + tests |
| `csharp.diff-coverage` |  | Diff-coverage gate |

## `[settings]`

Any input of the public `gate.yml` can be set here, except the locked ones
below. The file wins over the consumer workflow's `with:` block, which wins
over the gate default:

```text
devkit.ini  >  workflow with:  >  gate default
```

Values are coerced to the input's type: numbers (`pr-size-soft-limit = 600`)
and booleans (`run-supply-chain = true`, also `yes`/`no`/`on`/`off`/`1`/`0`).
Enumerated keys are validated and a value outside the set is ignored with a
warning: `tier`, `fail-on`, every `*-enforcement` key, `commit-msg-fail-level`,
`python-pre-commit`, `vuln-prioritize-fail-on`.

Keys repos most often set:

| Key | Example | Notes |
|---|---|---|
| `languages` | `python,typescript` | Overrides stack auto-detection |
| `tier` | `qa` | Normally left on `auto` (resolved from the branch) |
| `fail-on` | `critical` | Severity threshold for scanners |
| `python-version` | `3.12` | |
| `python-test-command` | `uv run pytest -m "not slow"` | Replaces the default pytest invocation |
| `python-test-paths` | `tests/unit` | |
| `python-skip-mypy` | `true` | Same effect as skipping `python.type-check` |
| `test-os` | `["ubuntu-latest","macos-latest"]` | JSON list |
| `pr-size-soft-limit`, `pr-size-hard-limit` | `600`, `900` | |
| `diff-coverage-min`, `diff-coverage-enforcement` | `70`, `warn` | |
| `internal-scopes` | `@acme,acme-` | Dependency-confusion namespaces |
| `mcp-allowlist` | | Approved MCP servers |
| `dependency-cooldown-days` | `3` | |
| `build-command` | `make dist` | For the supply-chain artifact |
| `artifact-retention-days` | `14` | |

The full list is the `inputs:` block at the top of `.github/workflows/gate.yml`.

### Locked settings

Set by the organisation in its wrapper workflow and never read from the file:

- `runner`
- `allowed-author-domains`
- `identity-enforcement`
- `secret-scan-historic-mode`
- `attestation-frequency`

## Skipping individual unit tests

That is the job of your test runner, not the kit. Use pytest markers, Jest
`describe.skip`, and so on, or point `python-test-command` at a narrower
invocation. `[skip]` turns off kit checks, not your tests.

## Where the logic lives

- `.github/actions/repo-config/` — `parse.sh` (tokeniser, bash + awk),
  `resolve.jq` (rules), `checks.txt` (the list above), `action.yml` (which copy
  of the file to read).
- `tests/test-repo-config.sh` — unit tests against `tests/fixtures/repo-config/*.ini`.
- `gate.yml` — the `detect` job runs the action; every job and step tests
  `contains(needs.detect.outputs.skip, ',name,')`, and overridable inputs are read
  through `fromJSON(needs.detect.outputs.settings)['key']`.

Adding a new check: add its guard in the workflow, add a line to `checks.txt`,
regenerate the table above, and the self-test will keep the three in step.
