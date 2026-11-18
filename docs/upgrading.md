# Upgrading the Kit

There is no upgrade. The kit tracks `main` — every push to the kit's main
branch is live for every consumer on their next CI run.

## Pinning strategy

Reference the kit as `@main`:

```yaml
uses: Attri-Inc/dev-kit/.github/workflows/gate.yml@main
```

There are no version tags. To control when you take changes, pin a commit SHA
instead of `@main`. A SHA pin freezes `gate.yml` and the per-language
workflows, but **not** the composite actions — `gate.yml` always loads those
from `@main`. To freeze everything, fork the kit and point at your fork. See
[SECURITY.md](../SECURITY.md#using-the-kit-safely).

## When the kit changes

1. A contributor opens a PR against the kit.
2. The kit's own gate runs on the PR (the kit dogfoods itself).
3. A code owner reviews and approves.
4. The PR merges to main.
5. **Every consumer on `@main` picks up the change on their next push.**

## Testing a kit branch before it merges

`gate.yml` loads the composite actions by full reference
(`Attri-Inc/dev-kit/.github/actions/<name>@main`), so a branch that changes an
action still runs main's copy — in the kit's own PR checks too. To test a
branch for real:

1. On the branch, run `scripts/set-kit-ref.sh <branch>` and commit the result.
2. Point one or two consumer wrappers at `gate.yml@<branch>` and open PRs there.
3. Before merging, run `scripts/set-kit-ref.sh main` and commit again.

## Branch protection is the safety net

Because every kit merge reaches every consumer at once, the protection on the
kit's `main` branch is load-bearing:

- Code owner approval required
- All gate checks must pass (the kit running against itself)
- No force pushes, no deletions
- Strict status checks (branch must be up-to-date with main)

If you wouldn't ship a change to every consumer the moment you press merge,
don't press merge.

## Breaking changes

A breaking change (removed input, changed default that fails more builds) is
called out with a `BREAKING CHANGE:` footer in the commit and a migration note
in this file, under a dated heading.

## Rollback

If a bad merge lands on main:

1. Revert the merge in the kit (`git revert -m 1 <merge-sha>`) → push as a hotfix PR.
2. Once the revert merges, all consumers pick up the revert on their next CI run.
3. Investigate the root cause in a follow-up.

If the revert isn't fast enough, a consumer can temporarily pin `gate.yml` to
the last known-good commit SHA (with the composite-action limit above).

## Reporting a regression

If a kit change breaks your repo:
1. Pin temporarily to the last known-good commit SHA.
2. Open an issue on `Attri-Inc/dev-kit` with:
   - The kit commit SHA your run used
   - A job log link from the failing run, if your repo is public
   - A minimal reproduction
3. We'll revert or hotfix on main.

## Migration notes

### 2026-11-18 — fewer jobs, less waiting

On a self-hosted pool each job waits for a free runner, and that wait was most
of a gate run. The gate now starts ~4 jobs per PR instead of ~13–20. No check
was removed.

- **Job names changed.** The quick checks are steps of one `Checks` job; each
  language is one job (e.g. `Python / Lint, types, security, tests (<runner>)`).
  `Gate passed` keeps its name. If branch protection requires any other job
  name, switch it to `Gate passed`.
- **`detect` runs on GitHub-hosted** and absorbed `preflight` (same one billed
  minute).
- **`test-os` defaults to the resolved `runner`.** Tests used to go to
  GitHub-hosted `ubuntu-latest` even when `runner` was self-hosted. A wrapper
  that passes `test-os: '["ubuntu-latest"]'` explicitly keeps the old behavior.
- **Nightly (`schedule`) runs** do only the full-history secret scan, the
  dependency scans and attestation. Build, SBOM and Sigstore are one job.
- **`_ai-verification.yml` is gone**; its checks are steps of `Checks`.
- **Base-branch fetches run only when the base is missing.** A `--depth`
  fetch into the full clone used to cut its history for every later step in
  the same job.
- **Python installs use uv** (`uv pip install`), and the kit's own tools run
  through `uvx`.
