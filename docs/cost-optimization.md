# CI Cost Optimization

Actions spend is ~99% **compute minutes**, and GitHub bills **every job rounded UP to a
full minute**. This doc lists the safe levers — none removes a check or reduces coverage.

## Kit-side (already shipped — every repo benefits on the next gate run)

| Lever | What it does |
|---|---|
| **Grouped fast checks** (`hygiene` / `code-scan` / `dep-scan`) | ~15 quick composite-action checks now run as steps inside 3 shared-runner jobs instead of 15 separate jobs — eliminating ~12 min/run of per-job rounding tax and de-duplicating the base-branch fetch. All checks still run (`if: ${{ !cancelled() }}`) and any real failure still blocks (`gate-passed`). |
| **`docs-only` short-circuit** | When a PR/push changes only markdown/docs/text/images, the expensive per-language + AI + dependency jobs skip and `gate-passed` still reports success — even for repos without a wrapper `paths-ignore`. Conservative: code/lockfiles/configs/workflows are never "docs"; secret-scanning still runs. |
| **Artifact retention** (`artifact-retention-days`, default 7) | Built-artifact / SBOM / compliance-evidence uploads expire in 7 days instead of GitHub's 90, curbing Actions-storage growth. |
| **Nightly attestation** (`attestation-frequency: nightly`, default) | Scorecard / SBOM / Sigstore run once daily, not per-commit (~$80–100/mo saved). Keep the default. |
| **Tiering** (`tier: auto`) | Heavy SAST / supply-chain / scorecard run at `qa`/`main`/nightly, never on every dev push. |

## Consumer-side (per-repo wrapper — opt-in rollout)

Apply these to each repo's `.github/workflows/attri-dev-kit.yml`. The `examples/` wrappers
already include them; the audit script below finds repos that are missing them.

| Lever | Snippet | Why |
|---|---|---|
| **Cancel superseded runs** | `concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }` | A new push cancels the in-flight run of the old commit — only the latest commit matters. |
| **Skip docs/config** | `paths-ignore: ['**/*.md','docs/**','LICENSE','*.txt','.gitignore','.editorconfig']` | Don't run CI on changes that can't affect code. (The kit's `docs-only` is a backstop, but `paths-ignore` avoids even spinning up `detect`.) |
| **Don't double-trigger** | gate feature branches on `pull_request` only; reserve `push:` for protected branches | Avoids running the same commits twice (push to branch + PR). Every change is still gated once. |
| **Skip drafts** | `if: github.event.pull_request.draft == false` on the calling job | Gate when a PR is marked ready, not on every WIP commit. You can't merge a draft. |

Copy the `concurrency` / `paths-ignore` snippets above into each repo's wrapper as
part of normal maintenance (the `examples/` wrappers already include them).

## Estimated impact
On a typical dev-tier PR the quick-check rounding tax (~12 billed min) drops to ~6 (3 grouped
jobs); `concurrency` removes stacked runs on active PRs; `docs-only` / `paths-ignore` zero out
doc PRs. Together: a meaningful cut on the per-run floor that multiplies across all repos.

## What is NOT safe (do not do)
Removing checks, lowering scan depth / coverage thresholds, disabling supply-chain or SAST
jobs, switching attestation to per-commit, or skipping Dependabot PRs. These weaken the gate.
