# Fixture: exception-swallow

**Expected to be caught by:** `exception-swallow`.

Plants every pattern the action checks:
- Python `except: pass`
- Python `except Exception: ... return None`
- TS `catch (_) {}` and `catch {}`
- Auth-bypass comment phrases ("bypassing microsoft auth for prod", "skip mfa for testing")
- `user.admin = true` style privilege escalation

The Pyright `reportUndefinedVariable` warnings on `verify_token` / `api_call` are expected — this is fixture code, not real code; the action only greps the diff for patterns and doesn't try to type-check.
