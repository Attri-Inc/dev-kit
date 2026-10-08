# Allowlist Format

Silence reviewed false positives without disabling whole checks. Each scanner has its own allowlist file in your repo (the kit reads them automatically when present).

## Secret scanner (detect-secrets + trufflehog)

The CI gate scans secrets with **detect-secrets** (pattern + entropy) and
**trufflehog** (verified-only — it confirms the secret is live). There are two
allowlist mechanisms:

**1. detect-secrets baseline — `.secrets.baseline` in your repo root.**
This is the primary allowlist. Reviewed false positives are recorded in the
baseline; CI passes as long as no NEW secret appears that isn't in it.

```bash
# Generate (or refresh) the baseline after reviewing findings, then commit it:
pip install detect-secrets==1.5.0
detect-secrets scan > .secrets.baseline
# Audit each finding interactively (mark true/false positive):
detect-secrets audit .secrets.baseline
git add .secrets.baseline && git commit -m "chore: update detect-secrets baseline"
```

You can also inline-allow a single line with a pragma comment:

```python
api_key = "sk-PLACEHOLDER-not-a-real-key"  # pragma: allowlist secret
```

**2. trufflehog path excludes — `.trufflehogignore` in your repo root.**
One path or regex per line; trufflehog skips matching files.

```
docs/.*\.md$
tests/fixtures/.*
```

> Note: `.gitleaks.toml` (and the bundled [`policies/.gitleaks.toml`](../policies/.gitleaks.toml))
> configures only the **local pre-commit hook** ([`policies/lefthook.yml`](../policies/lefthook.yml)),
> NOT the CI gate. A `.gitleaks.toml` in your repo will not change CI results —
> use `.secrets.baseline` / `.trufflehogignore` for that.

## License compliance

The license gate denies strong/network copyleft (GPL/AGPL/SSPL/…) by default,
warns on weak copyleft (LGPL/EPL/…), and allows permissive licenses. To silence
a reviewed exception, add a `.attri-dev-kit-license-allowlist` file in your repo
root — one **package name** or **license ID** per line (`#` comments allowed):

```
# Reviewed: this GPL tool is a build-time-only dependency, not distributed
some-build-only-tool
# Accept this specific license org-wide
LGPL-2.1-only
```

Matched packages/licenses are skipped by the policy. To change the org-wide
posture instead of per-repo, set the `license-enforcement` input (`warn`/`fail`).

## Identity check

The identity check is off until you set the `allowed-author-domains` input:

```yaml
with:
  allowed-author-domains: 'example.com,users.noreply.github.com,github.com'
```

For per-commit exceptions (e.g., a one-off `v0[bot]` commit), there's no allowlist — fix the author in your local git config and amend the commit.

## PR size

Apply the `pr-size: bypass-approved` label to a specific PR (only repo admins should be able to apply it). The next CI run will pass the size check.

## Bandit (Python SAST)

File: `.bandit` or `pyproject.toml`:

```toml
[tool.bandit]
exclude_dirs = ["tests", "examples"]
skips = ["B101", "B601"]   # specific test IDs to skip
```

## Semgrep (TS/JS SAST)

File: `.semgrepignore` (gitignore syntax):

```
# Generated code
src/proto/
**/*.generated.ts
```

## ESLint / Biome / Ruff

Use the linter's native rule disable comments. The kit doesn't override your repo's lint config.

## TFLint

File: `.tflint.hcl` in your repo. Kit ships baseline at [`policies/tflint.hcl`](../policies/tflint.hcl).

## Checkov

File: `.checkov.yaml`:

```yaml
skip-check:
  - CKV_AWS_18      # S3 bucket access logging — opt out for dev buckets
  - CKV_AZURE_33    # Storage logging
soft-fail-on:
  - LOW
  - MEDIUM
```

## Hadolint

File: `.hadolint.yaml` (kit ships baseline at [`policies/.hadolint.yaml`](../policies/.hadolint.yaml)).

## Trivy

File: `.trivyignore`:

```
# Format: <CVE-ID> [optional reason]
CVE-2023-12345  # mitigated by network policy
```

## When to add an allowlist entry vs fix the issue

Add allowlist:
- Generated code with known acceptable findings
- Test fixtures planted intentionally
- Documentation containing example tokens
- Third-party vendored code that you can't modify

Fix the issue (don't allowlist):
- Real secret leaks (rotate first, then purge from history)
- Real CVEs in deps (upgrade)
- Real lint violations (fix the code)
- Real type errors (fix the types)

A good rule: if a future engineer would be surprised the allowlist exists, write a comment explaining why.
