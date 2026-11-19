# CI Cost Optimization

Actions spend is ~99% **compute minutes**, and GitHub bills **every job rounded UP to a
full minute**. On a self-hosted pool the cost is time instead: **every job waits for a
free runner**, then pays a fixed start-up cost (pod, action download, clone). This doc
lists the safe levers — none removes a check or reduces coverage.

## Kit-side (already shipped — every repo benefits on the next gate run)

| Lever | What it does |
|---|---|
| **One `checks` job** | Every quick, language-independent check (secrets, hygiene, code scan, dependency scans, AI provenance + AI verification, migration safety, actionlint) runs as a step of ONE job instead of ~13 jobs. All checks still run (`if: ${{ !cancelled() }}`) and any real failure still blocks (`gate-passed`). |
| **One job per language** | Each language workflow is one job: dependencies install once, then lint, type-check, security, audit, tests and build run as steps. Python went from 6 jobs to 1, TypeScript from 8 to 1. |
| **`detect` on GitHub-hosted** | Every other job waits for `detect`, so it must not wait in the self-hosted queue. It absorbed the old `preflight` job, which was hosted already: still one billed minute. |
| **Tests on the selected runner** | `test-os` defaults to the resolved `runner`. Before, tests always went to GitHub-hosted `ubuntu-latest`, even for self-hosted consumers. |
| **`docs-only` short-circuit** | When a PR/push changes only markdown/docs/text/images, the expensive per-language + AI + dependency jobs skip and `gate-passed` still reports success — so wrappers need no `paths-ignore` on `pull_request`. Conservative: code/lockfiles/configs/workflows are never "docs"; secret-scanning still runs. |
| **Artifact retention** (`artifact-retention-days`, default 7) | SBOM / compliance-evidence uploads expire in 7 days instead of GitHub's 90, curbing Actions-storage growth. |
| **Nightly attestation** (`attestation-frequency: nightly`, default) | Scorecard / SBOM / Sigstore run once daily, not per-commit (~$80–100/mo saved). Keep the default. The examples schedule it at 21:47 UTC (03:17 IST), outside working hours, so it does not compete with PRs for runners. |
| **Tiering** (`tier: auto`) | Heavy SAST / supply-chain / scorecard run at `qa`/`main`/nightly, never on every dev push. |

## Consumer-side (per-repo wrapper — opt-in rollout)

Apply these to each repo's `.github/workflows/attri-dev-kit.yml`. The `examples/` wrappers
already include them; the audit script below finds repos that are missing them.

| Lever | Snippet | Why |
|---|---|---|
| **Cancel superseded runs** | `concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }` | A new push cancels the in-flight run of the old commit — only the latest commit matters. |
| **Skip docs/config on push** | `paths-ignore: ['**/*.md','docs/**','LICENSE','*.txt','.gitignore','.editorconfig']` under `push:` only | Don't run CI on pushes that can't affect code. **Never put it under `pull_request:`**: GitHub never reports the required `Gate passed` check for a PR that a path filter skips, so docs-only and zero-change PRs stay blocked forever. `docs-only` covers the PR side. |
| **Don't double-trigger** | gate feature branches on `pull_request` only; reserve `push:` for protected branches | Avoids running the same commits twice (push to branch + PR). Every change is still gated once. |
| **Skip drafts** | `if: github.event.pull_request.draft == false` on the calling job | Gate when a PR is marked ready, not on every WIP commit. You can't merge a draft. |

Copy the `concurrency` / push-only `paths-ignore` snippets above into each repo's wrapper as
part of normal maintenance (the `examples/` wrappers already include them).

## Self-hosted runner pool (on-prem) — what the pool owner can add

The kit works without any of these. Each one removes repeated downloads from
every job. Ephemeral runner pods (ARC) start empty, so today every job fetches
its tools and packages again over the internet link.

| Lever | How | What it removes |
| --- | --- | --- |
| **Bake tools into the runner image** | Install the pinned versions the kit checks for: actionlint, shellcheck, semgrep, trivy, hadolint, shfmt, trufflehog, detect-secrets, commitlint at `/opt/commitlint`, plus Python and Node in the tool cache (`RUNNER_TOOL_CACHE`). | The per-job tool downloads. The kit already skips an install when the pinned version is on `PATH`. |
| **Persistent cache volume** | Mount one volume in every runner pod and set `UV_CACHE_DIR`, `npm_config_cache`, `PRE_COMMIT_HOME`, `TRIVY_CACHE_DIR` to folders on it. | Package downloads. `setup-uv` keeps a preset `UV_CACHE_DIR` and turns its GitHub cache off on self-hosted runners. uv's cache is safe for parallel jobs. |
| **Local registry for Docker layers** | A `registry:2` on the server, used as the buildx cache. | Today `_docker.yml` uses `cache-to: type=gha,mode=max`, which uploads every layer to GitHub's cache over the internet link. |
| **Keep warm runners** | ARC `minRunners` ≥ the usual PR load. | Pod start-up while a job waits. It also keeps the offline-fallback check honest (scale-to-zero reads as "no runner online"). |

A shared cache is written by every repo's PRs. All gated repos are internal, but
treat the volume as shared state: do not mount it into fork-PR jobs.

## Estimated impact

On a self-hosted pool, a typical PR now waits for ~4 runners instead of ~13–20;
`concurrency` removes stacked runs on active PRs; `docs-only` (PRs) / `paths-ignore`
(pushes) zero out doc PRs. Measure before/after from the jobs API: queue time is
`started_at - created_at` per job.

## What is NOT safe (do not do)

Removing checks, lowering scan depth / coverage thresholds, disabling supply-chain or SAST
jobs, switching attestation to per-commit, or skipping Dependabot PRs. These weaken the gate.
