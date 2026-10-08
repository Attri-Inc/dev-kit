# Contributing to attri-dev-kit

Thanks for considering a contribution. Every repo that uses the kit runs the
kit's `main` on its next CI run, so changes carry blast radius. Please follow
this guide.

## Ground rules

1. **Don't add custom scanners.** Always wrap an existing, license-clean OSS
   tool or GitHub Action. Write original code only when no existing tool does
   the job (for example, `identity-check`).
2. **License hygiene.** Every dependency must be MIT, Apache-2.0, BSD-2/3,
   MPL-2.0, or LGPL (used as a tool, not embedded). No GPL/AGPL.
3. **Pin third-party actions; reference the kit by `@main`.** Two different rules:
   - **Third-party actions** used *inside* the kit (trivy, checkov, etc.) must
     be pinned to a commit SHA — never `@master`/`@main`. Use
     `scripts/pin-actions-to-sha.sh`.
   - **The kit's own composite actions** are referenced as
     `Attri-Inc/dev-kit/.github/actions/<name>@main`.
4. **Keep things composable.** Per-language workflows live in
   `.github/workflows/_<lang>.yml` and are called only by `gate.yml`.
5. **Backward compatibility.** New inputs need defaults. Removing an input is
   a breaking change.
6. **Treat PR-derived strings as untrusted.** Titles, bodies, labels and branch
   names must never reach a shell unquoted.

## Local dev

```bash
# 1. Clone
git clone https://github.com/Attri-Inc/dev-kit
cd dev-kit

# 2. Validate workflow YAML
brew install actionlint
actionlint .github/workflows/*.yml

# 3. Build fixtures and run the test suite
brew install bats-core
bash tests/build-fixtures.sh
bats tests/self-test.bats
bash tests/test-lint-disable.sh
```

A known limit: the kit's own CI (`self-test.yml`) loads composite actions from
`main`, not from your PR branch. A PR that changes a composite action is
tested by the bats suite, but not end-to-end by the gate, until it merges.

## Sign your commits off (DCO)

We use the [Developer Certificate of Origin](https://developercertificate.org/).
Add a `Signed-off-by` line to every commit to certify that you wrote the change
or have the right to submit it:

```bash
git commit -s -m "fix(gate): correct tier resolution for uat"
```

## Commit messages

Conventional Commits, enforced via the PR title:

- `feat(python): add ruff format check`
- `fix(gate): correct tier resolution for uat`
- `docs(languages): document Astro support`
- `chore(deps): bump trivy-action to v0.30.0`
- `security(identity): reject @hotmail.com domains`

## PR checklist

- [ ] Conventional Commits PR title
- [ ] Every commit signed off (`git commit -s`)
- [ ] Updated `docs/` for any user-visible change
- [ ] Updated `examples/` if a new pattern is introduced
- [ ] Added or updated a `tests/self-test.bats` test
- [ ] Third-party actions pinned to a commit SHA
- [ ] License of any new tool or action is MIT/Apache-2.0/BSD/MPL
- [ ] No breaking change, OR a `BREAKING CHANGE:` footer + `docs/upgrading.md` updated

## Reporting security issues

Don't open a public issue. See [SECURITY.md](SECURITY.md).

## Code of conduct

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
