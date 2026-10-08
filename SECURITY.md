# Security Policy

## Reporting a vulnerability

If you find a vulnerability **in the kit itself** (not in a repo that uses the kit):

1. Do **not** open a public issue.
2. Report it privately: [open a security advisory](https://github.com/Attri-Inc/dev-kit/security/advisories/new).
3. Include: the kit commit SHA, a reproduction, the impact, and a suggested fix if you have one.
4. We aim to acknowledge within 2 business days and to ship a fix within 7.

If the kit failed to catch a vulnerability in your own repo, that is a missed
finding, not a kit vulnerability. Open a normal issue, without secrets or
exploit details.

## Scope

- ✅ The kit's own code (composite actions, reusable workflows, scripts)
- ✅ The kit's policies and configs in `policies/`
- ✅ Defaults that could mask real findings
- ❌ Vulnerabilities in third-party actions the kit wraps — report those upstream
- ❌ Misuse of the kit in a downstream repo

## Using the kit safely

**Pass only the secrets you need.** The kit needs no secrets. Pass optional
secrets (`GOOGLE_CHAT_WEBHOOK_URL`, `ANTHROPIC_API_KEY`, `RUNNER_STATUS_TOKEN`)
explicitly in a `secrets:` block. Do not use `secrets: inherit` — it hands
every repo and org secret to the kit's workflows.

**Pinning has a limit.** You can pin `gate.yml` to a commit SHA:

```yaml
uses: Attri-Inc/dev-kit/.github/workflows/gate.yml@<full-40-char-sha>
```

This freezes `gate.yml` and the per-language workflows it calls. It does
**not** freeze the kit's composite actions: `gate.yml` references them as
`Attri-Inc/dev-kit/.github/actions/<name>@main`, so they always come
from `main`. If you need every line of kit code frozen, fork the repo into
your org and point your workflows at the fork.

**Third-party actions** used inside the kit are pinned to commit SHAs.

## Supply chain

Every push to `main` generates a CycloneDX SBOM (`sbom.cdx.json`) and an SPDX
SBOM (`sbom.spdx.json`) of the kit. They are attached as artifacts to the
`release-kit` workflow run.
