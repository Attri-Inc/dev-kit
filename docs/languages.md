# Language Support

Auto-detected via file presence. Override with `languages: python,terraform` etc. if you need to skip detection.

## Python

**Detected by:** `pyproject.toml`, `setup.py`, `requirements*.txt`, or any `*.py` file

| Tool | Action | License |
|---|---|---|
| Lint + format | [astral-sh/ruff-action@v4](https://github.com/astral-sh/ruff-action) | MIT |
| Type check | mypy (via composite) | MIT |
| Security SAST | [PyCQA/bandit](https://github.com/PyCQA/bandit) | Apache-2.0 |
| Dep vulns | [pypa/gh-action-pip-audit@v1](https://github.com/pypa/gh-action-pip-audit) | Apache-2.0 |
| Test | pytest (composite) | MIT |
| Coverage | [codecov/codecov-action@v6](https://github.com/codecov/codecov-action) | MIT |

Ruff replaces flake8, black, isort, pylint, pyupgrade, autoflake — single binary, 10–100× faster.

**Lockfile integrity & line endings (all languages):** CI installs from the
lockfile and fails on drift/tampering — `npm ci` / `--frozen-lockfile` (TS),
`uv sync --frozen` (Python), `go mod verify` (Go), `dotnet restore --locked-mode`
(C#). Copy [`policies/.gitattributes`](../policies/.gitattributes) and
[`policies/.editorconfig`](../policies/.editorconfig) into your repo so line
endings are LF everywhere (CRLF shell scripts break on Linux runners — the kit
warns when it sees them).

**Diff coverage (all languages):** on PRs the kit measures *patch coverage* — the % of the lines you changed that are covered by tests — via `diff-cover` (self-contained, no external service). Python and Go are kit-driven (coverage always produced); TypeScript, Java, and C# are *consume-if-present* (gated only if the repo emits a coverage report — lcov/cobertura, JaCoCo, or coverlet respectively). Controlled org-wide by `diff-coverage-min` (default 80) and `diff-coverage-enforcement` (default `warn`).

## TypeScript / JavaScript

**Detected by:** `package.json`, `tsconfig.json`, or any `*.ts*`/`*.js*` file

| Tool | Action | License |
|---|---|---|
| Lint + format (default) | [biomejs/setup-biome@v2](https://github.com/biomejs/setup-biome) | MIT |
| Lint (fallback) | ESLint via the repo's own `lint` npm script, else `npx eslint .` (composite) | MIT |
| Type check | tsc (composite) | Apache-2.0 |
| Security SAST | Semgrep CLI `1.97.0`, pip-installed (the wrapper action `returntocorp/semgrep-action` is deprecated as of 2026; the `semgrep/semgrep` image needed a Docker daemon on the runner) | LGPL-2.1 (used as tool) |
| Dep vulns | npm/pnpm/yarn audit (composite) | Various |
| Test | jest/vitest (composite) | MIT |

**Frontend quality (a11y + perf, consume-if-present):** at qa/main on repos with
a build, the kit runs **Lighthouse CI** (`lhci autorun`) when a `lighthouserc`
config exists — covering performance, Core Web Vitals, and **accessibility**
(Lighthouse's a11y category runs axe-core) — and **size-limit/bundlewatch** when
configured, for bundle-size budgets. The repo's own config defines how to
build/serve and the budgets; warn-first via `frontend-quality-enforcement`.

Biome is selected automatically when `biome.json` is present (it lints AND formats). Otherwise the kit runs ESLint only — via your repo's `lint` npm script if defined, else `npx eslint .`. There is no separate Prettier step on the fallback path, so formatting is enforced only when Biome is in use or your own `lint` script runs Prettier. Biome is 35× faster than ESLint+Prettier with 97% Prettier compatibility.

Package manager auto-detected: pnpm (`pnpm-lock.yaml`) → yarn (`yarn.lock`) → npm (default).

**Codegen (Prisma):** installs run with `--ignore-scripts` (supply-chain defense), which skips the `postinstall` hook generators like Prisma normally run from — so without help, lint and type-check would fail to resolve the generated client (`TS2305`/`TS7006`). When a Prisma schema is detected (`prisma/schema.prisma`, a `prisma.schema` field in `package.json`, or a `prisma.config.*` file), the lint and type-check jobs run `prisma generate --no-engine` before checking. This regenerates only the **types** (no query-engine binary download), and re-runs only that known first-party generator by name — never arbitrary third-party `postinstall` hooks — so consumer repos do **not** need to commit their generated client.

## Java

**Detected by:** `pom.xml`, `build.gradle*`, or any `*.java` file

| Tool | Action | License |
|---|---|---|
| Lint | [nikitasavinov/checkstyle-action](https://github.com/nikitasavinov/checkstyle-action) | MIT |
| Static analysis | SpotBugs (composite) | Apache-2.0 |
| Dep vulns | [dependency-check/Dependency-Check_Action@main](https://github.com/dependency-check/Dependency-Check_Action) | Apache-2.0 |
| Test | mvn/gradle test (composite) | various |
| JDK | [actions/setup-java@v4](https://github.com/actions/setup-java) (Temurin) | MIT |

## Go

**Detected by:** `go.mod`

| Tool | Action | License |
|---|---|---|
| Lint | [golangci/golangci-lint-action@v9](https://github.com/golangci/golangci-lint-action) | MIT (bundles 50+ linters) |
| Vuln scan | [golang/govulncheck-action@v1](https://github.com/golang/govulncheck-action) | BSD-3 |
| Test | `go test` (composite) | BSD-3 |

## Terraform

**Detected by:** any `*.tf` file

| Tool | Action | License |
|---|---|---|
| fmt + validate | [hashicorp/setup-terraform@v3](https://github.com/hashicorp/setup-terraform) | MPL-2.0 |
| Lint | [terraform-linters/setup-tflint@v6](https://github.com/terraform-linters/setup-tflint) | MPL-2.0 |
| Security | [bridgecrewio/checkov-action@master](https://github.com/bridgecrewio/checkov-action) | Apache-2.0 |
| Security (alt) | Trivy CLI (`trivy config`) via [aquasecurity/setup-trivy](https://github.com/aquasecurity/setup-trivy) — binary install, no Docker daemon | Apache-2.0 |
| Cost diff | [infracost/actions/setup@v4](https://github.com/infracost/actions) | Apache-2.0 (requires `INFRACOST_API_KEY` secret) |

Note: tfsec is folded into Trivy. Terrascan is archived by Tenable — not used here.

## Docker

**Detected by:** `Dockerfile` or `Dockerfile*` in repo root or up to depth 4

| Tool | Action | License |
|---|---|---|
| Dockerfile lint | [hadolint](https://github.com/hadolint/hadolint) v2.15.1 release binary — no Docker daemon needed to lint a Dockerfile | MIT |
| Image vuln scan | [aquasecurity/trivy-action@master](https://github.com/aquasecurity/trivy-action) | Apache-2.0 |
| Image lint | [erzz/dockle-action@v1](https://github.com/erzz/dockle-action) | Apache-2.0 |
| Build | [docker/build-push-action@v7](https://github.com/docker/build-push-action) | Apache-2.0 |

## Shell

**Detected by:** any `*.sh` or `*.bash` file

| Tool | Action | License |
|---|---|---|
| Lint | [ludeeus/action-shellcheck@master](https://github.com/ludeeus/action-shellcheck) | MIT |
| Format check | shfmt (composite) | BSD-3 |

## C#

**Detected by:** `*.csproj` or `*.sln`

| Tool | Action | License |
|---|---|---|
| Format | dotnet format (composite) | MIT |
| Build + test | [actions/setup-dotnet@v4](https://github.com/actions/setup-dotnet) | MIT |
| Security SAST | Semgrep CLI (`p/csharp` + `p/owasp-top-ten`), pip-installed — non-invasive, SARIF to code scanning | LGPL-2.1 (tool) |
| Coverage | coverlet (`--collect "XPlat Code Coverage"`) → diff-coverage gate | MIT |

## HTML / CSS / Astro / Svelte / MDX

Covered by Biome (CSS, JSON, GraphQL) and Prettier as fallback. No special action needed.

## Adding a new language

Open a PR adding:
1. `policies/<lang>.<config>` — default config
2. `.github/workflows/_<lang>.yml` — language reusable workflow
3. Detection logic in `.github/actions/detect-stack/action.yml`
4. Example in `examples/<stack>/.github/workflows/attri-dev-kit.yml`
5. This doc updated
