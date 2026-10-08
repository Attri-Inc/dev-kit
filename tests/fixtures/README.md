# Fixtures

Planted-bad-state mini-repos used by `tests/self-test.bats` to verify the kit catches what it claims to catch.

| Fixture | Should be caught by |
|---|---|
| `secret-in-env/` | gitleaks |
| `local-email-author/` | identity-check |
| `gmail-author/` | identity-check |
| `oversized-pr/` | pr-size-guard |
| `risky-migration/` | migration-safety |
| `bad-dockerfile/` | hadolint |
| `vulnerable-tf/` | checkov / trivy-iac |

Each fixture is a self-contained directory with whatever files are needed to trip the corresponding check. The tests ensure: (a) each known-bad fixture is caught, (b) no fixture catches in a way unrelated to its purpose.
