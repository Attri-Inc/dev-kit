# Repository Governance Policy

The single source of truth for **what** governance every repo in your org should have.
Application is **manual** (you configure these in GitHub — org rulesets, repo settings);
the kit's [`scripts/audit-governance.sh`](../scripts/audit-governance.sh) **reads** each
repo and reports which items are missing, so the manual work is targeted and verifiable.

> Why this exists: the most common audit findings — direct unreviewed pushes, auth-bypass
> merges, repos with **no branch protection** — are not fixable from CI:
> it lives in repo/org *settings*. This policy + audit make the settings explicit and checkable.

Prefer **organization-level rulesets** (one definition targeting many repos via custom
properties) over per-repo branch protection — see GitHub → Org → Settings → Rules → Rulesets.

## Required on every repo's default branch (`main`)

| # | Control | Where to set it | Why |
|---|---|---|---|
| G1 | **Require a pull request before merging** | Ruleset → "Require a pull request before merging" | Kills direct unreviewed pushes |
| G2 | **Require ≥1 approving review** (≥2 for prod-critical) | Same rule → required approvals | Two-person review (SLSA source L4) |
| G3 | **Dismiss stale approvals on new push** + **require approval of most-recent push** | Same rule | Stops "approve then sneak in changes" / self-approve-via-extra-commit |
| G4 | **Require status checks** including **`Gate passed`** | Ruleset → "Require status checks to pass" → add `Gate passed` | Makes the kit's gate actually required, not advisory |
| G5 | **Block force-pushes** (non-fast-forward) | Ruleset → "Block force pushes" (default on) | History integrity (SLSA L2 continuity) |
| G6 | **Empty bypass list** ("Do not allow bypassing") | Ruleset → bypass list = none (or break-glass team only) | The fix for auth-bypass merges — a required check admins can bypass is theater |
| G7 | **CODEOWNERS present + required owner review** | `.github/CODEOWNERS` + ruleset "Require review from Code Owners" | Routes review to accountable teams |
| G8 | **Block branch deletion** | Ruleset → "Restrict deletions" | Protect main/release branches |
| G9 | **attri-dev-kit onboarded** | `.github/workflows/attri-dev-kit.yml` present | The repo actually calls the kit |

Recommended (tier up for prod-critical repos): **require signed commits** (G10),
**require linear history** (G11), **tag protection** for `v*` (G12).

> **G7 is partly auto-checked in CI.** The kit's `codeowners` job (read-only, runs
> on every PR) verifies CODEOWNERS exists, is valid (via GitHub's own
> `codeowners/errors` API — catches dead/invalid owner handles), and has a
> catch-all `*` rule. It does *not* set the "require code owner review" ruleset
> bit — that's still manual (G7). Template: [`policies/CODEOWNERS.template`](../policies/CODEOWNERS.template).
>
> **G9 caveat:** the audit flags `kit-not-onboarded` when `.github/workflows/attri-dev-kit.yml`
> is absent. The **kit repo itself** is a false-positive here — it dogfoods
> the gate via `self-test.yml`, not the consumer wrapper. Your product repos report accurately.

## Required at the organization level (one-time)

| # | Control | Where | Why |
|---|---|---|---|
| O1 | **Require 2FA for all members** | Org → Settings → Authentication security | Account-takeover prevention |
| O2 | **Secret-scanning push protection** (org default) | Org → Settings → Code security | Block secrets server-side before they land |
| O3 | **Base permission = read** (not write) | Org → Settings → Member privileges | Least privilege; push only via team grant |
| O4 | **Required workflow** (org ruleset) — run `gate.yml` even if a repo deletes its wrapper | Org ruleset → required workflow | Closes the opt-out hole |

## Rollout

1. **Audit** — run `scripts/audit-governance.sh <org>` to get the current gap matrix.
2. **Fix manually** — apply the missing controls in GitHub (org rulesets first; they cover many repos at once).
3. **Re-audit** — re-run until the matrix is green. Re-run periodically to catch drift.

The audit is read-only and mutates nothing. It needs a token with admin read on the
repos (so it can read branch-protection / ruleset state) — run it under your own
`gh auth login` as an org admin.
