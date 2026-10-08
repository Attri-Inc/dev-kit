# Per-Repo Onboarding Checklist

Five minutes per repo. Three steps. Pure opt-in — your repo is unchanged until you add the file in step 1.

## Step 1 — Add the workflow file

1. Pick the example that matches your stack from [`examples/`](../examples).
2. Copy its `.github/workflows/attri-dev-kit.yml` to your repo at the same path.
3. Don't edit anything unless you have a specific reason, except one: set `allowed-author-domains` to your org's email domains to turn on the identity check.

If your stack isn't an example, use `multi-language-monorepo` and let `languages: auto` handle detection.

## Step 2 — Open a PR with the workflow file added

- Push to a branch
- Open a PR against `dev` (or whatever your repo's working branch is)
- Watch the kit run on the PR

If the kit catches things, fix them in the same PR. If it false-positives on something, see [allowlist.md](allowlist.md).

## Step 3 — Verify each tier works

Open a follow-up PR and merge it through your tiers in order:
1. PR to `dev` → confirm `tier: dev` runs (fast, ~2 min)
2. PR `dev` → `qa` (or `uat`) → confirm `tier: qa` runs (~5 min)
3. PR `qa` → `main` → confirm `tier: main` runs (~10–15 min, includes SBOM + Sigstore + Scorecard)

If any tier fails on a true issue, fix it. If it fails on noise, document the false positive and add to the appropriate allowlist.

## Optional: per-repo overrides

If your repo legitimately needs different defaults (e.g., a docs-only repo with huge PRs):

```yaml
jobs:
  attri-dev-kit:
    uses: Attri-Inc/dev-kit/.github/workflows/gate.yml@main
    with:
      tier: ${{ github.base_ref || github.ref_name }}
      languages: typescript,docker
      fail-on: critical              # only fail on critical
      pr-size-soft-limit: 800
      pr-size-hard-limit: 2000
      allowed-author-domains: 'example.com,users.noreply.github.com,github.com'
```

## What you're agreeing to

By opting in, every push/PR to `dev`/`qa`/`uat`/`main` will run the kit. If a check fails:
- **dev** — most checks are advisory; only secrets, identity, and lint fail hard
- **qa/uat** — adds PR size, SAST, dep vulns, license, container, IaC
- **main** — adds SBOM, Sigstore, OpenSSF Scorecard, migration safety

The kit never modifies your repo. It only annotates and pass/fails.

## Bypassing the test-delta gate

`test-delta` fails a PR that adds 20+ production-code lines without touching any
test file. Two ways to opt out:

- **Per-PR (label):** apply the `tests-not-needed` label to the PR — the gate
  passes. Rename the accepted label with `test-delta-bypass-label:` in your
  wrapper if your repo uses a different convention.
- **Whole repo (CI keyword):** set `skip-test-delta: 'true'` in your wrapper to
  disable the gate everywhere.

```yaml
jobs:
  attri-dev-kit:
    uses: Attri-Inc/dev-kit/.github/workflows/gate.yml@main
    with:
      tier: auto
      languages: python
      skip-test-delta: 'true'                 # bypass test-delta repo-wide
      test-delta-bypass-label: 'no-tests'     # or: rename the per-PR bypass label
```

## Pinning the kit version

- `@main` — receive every kit change on your next run (recommended)
- `@<sha>` — lock `gate.yml` to a commit. Composite actions still come from
  `@main`; see [upgrading.md](upgrading.md#pinning-strategy).

## Supply-chain hardening (recommended repo settings)

The kit's CI installs dependencies with `--ignore-scripts` and frozen lockfiles so a compromised package can't run install-time code in the gate. Set the equivalent in your repo so the same protection applies to local installs and deploys — the strongest defense against attacks like Shai-Hulud (malicious versions of trusted packages, usually flagged within a day or two):

- **Release-age cooldown** — don't install brand-new versions immediately:
  - uv — in `pyproject.toml`: `[tool.uv]\nexclude-newer = "7 days"`
  - pnpm — in `pnpm-workspace.yaml`: `minimumReleaseAge: 10080` (minutes = 7 days)
- **Disable install scripts** — npm — in `.npmrc`: `ignore-scripts=true`
- **Freeze installs** — `uv sync --locked`, `pnpm install --frozen-lockfile`, `npm ci`
- **Don't blindly auto-merge** Dependabot/version-bump PRs.
