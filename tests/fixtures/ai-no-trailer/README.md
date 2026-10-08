# Fixture: ai-no-trailer

**Expected to be caught by:** `ai-provenance` (require-trailer mode).

Built by `tests/build-fixtures.sh` — initializes a git repo with a commit authored by `claude[bot] <noreply@anthropic.com>` whose message body deliberately OMITS the `Co-Authored-By: Claude` trailer. The action should detect bot-author + missing-trailer and fail.

Companion: a second commit by `Some Human <human@example.com>` that DOES include the trailer (legitimate co-authoring) — should pass.
