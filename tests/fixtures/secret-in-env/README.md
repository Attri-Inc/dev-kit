# Fixture: secret-in-env

**Expected to be caught by:** `detect-secrets` action.

Contains a planted `.env` file with a Postgres password and an OpenAI-shaped key.
The Anthropic key is a placeholder — should be allowlisted by the kit's `policies/.gitleaks.toml`.
