#!/usr/bin/env bash
# Materializes runtime git history for fixtures that need it.
# Idempotent — safe to re-run; rebuilds the .git/ tree from scratch.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$ROOT/tests/fixtures"

init_repo() {
  local dir="$1"
  local email="$2"
  local name="$3"
  rm -rf "$dir/.git"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "$email"
  git -C "$dir" config user.name "$name"
}

# 1. local-email-author
echo ">> local-email-author"
DIR="$FIXTURES/local-email-author"
echo "console.log('hello')" > "$DIR/app.js"
init_repo "$DIR" "dev@Devs-MacBook-Pro.local" "Dev Person"
git -C "$DIR" add -A
git -C "$DIR" commit -q -m "feat: initial app"

# 2. gmail-author
echo ">> gmail-author"
DIR="$FIXTURES/gmail-author"
echo "print('hello')" > "$DIR/app.py"
init_repo "$DIR" "someone@gmail.com" "Some One"
git -C "$DIR" add -A
git -C "$DIR" commit -q -m "feat: initial app"

# 3. oversized-pr — base + branch with +700 lines
echo ">> oversized-pr"
DIR="$FIXTURES/oversized-pr"
init_repo "$DIR" "dev@example.com" "Dev"
echo "x" > "$DIR/big.txt"
git -C "$DIR" add -A
git -C "$DIR" commit -q -m "chore: baseline"
git -C "$DIR" checkout -q -b feature/huge
seq 1 700 >> "$DIR/big.txt"
git -C "$DIR" add -A
git -C "$DIR" commit -q -m "feat: add a lot"
git -C "$DIR" checkout -q main

# The secret-in-env fixture's .env is matched by the repo-root .gitignore, so it
# is NOT present on a fresh checkout (it only lingers on dev machines). Recreate
# the planted secrets at build time and force-add them below, otherwise the
# fixture is empty in CI and the secret scanner has zero behavioral coverage. (audit H11)
mkdir -p "$FIXTURES/secret-in-env"
# Written via echo (not a heredoc) so each trailing `# pragma: allowlist secret`
# is a SHELL comment on the source line — it silences the kit's own
# detect-secrets self-scan of THIS script, but is NOT echoed into the generated
# .env, so the behavioral fixture still contains real-looking secrets to detect.
{
  echo "# Planted FAKE secrets for the detect-secrets / trufflehog behavioral test."
  echo "# Not real credentials — do not \"rotate\"."
  echo "DATABASE_URL=postgres://app:S3cr3t-PLANTED-pw-9182@db.internal:5432/prod"  # pragma: allowlist secret
  echo "AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"  # pragma: allowlist secret
  echo "OPENAI_API_KEY=sk-PLACEHOLDER-not-real-but-shaped-1234567890abcdef"  # pragma: allowlist secret
} > "$FIXTURES/secret-in-env/.env"

# 4. risky-migration-sql / -alembic / vulnerable-tf / bad-dockerfile / clean-baseline / secret-in-env
# 4b. AI-validation fixtures: prompt-injection-clauded / slopsquat-pkg / exception-swallow / no-test-delta
for d in risky-migration-sql risky-migration-alembic vulnerable-tf bad-dockerfile clean-baseline secret-in-env \
         prompt-injection-clauded slopsquat-pkg exception-swallow no-test-delta; do
  echo ">> $d"
  DIR="$FIXTURES/$d"
  init_repo "$DIR" "dev@example.com" "Dev"
  git -C "$DIR" add -A
  # Force-add the planted .env (a stray global gitignore must not drop it).
  [ -f "$DIR/.env" ] && git -C "$DIR" add -f .env
  git -C "$DIR" commit -q -m "chore: planted fixture"
done

# 6. ai-no-trailer — bot-authored commit WITHOUT Co-Authored-By trailer + companion good commit
echo ">> ai-no-trailer"
DIR="$FIXTURES/ai-no-trailer"
# Clean any leftover files from prior runs so the first commit only contains app.js
rm -f "$DIR/app.js" "$DIR/app2.js"
init_repo "$DIR" "claude[bot]" "claude[bot]"
git -C "$DIR" config user.email "noreply@anthropic.com"
echo "console.log('hi')" > "$DIR/app.js"
git -C "$DIR" add -A
git -C "$DIR" commit -q -m "feat: add greeting (bot author, no trailer — should fail)"
git -C "$DIR" config user.email "human@example.com"
git -C "$DIR" config user.name "Some Human"
echo "console.log('hello')" > "$DIR/app2.js"
git -C "$DIR" add -A
git -C "$DIR" commit -q -m "feat: add second greeting

Co-Authored-By: Claude <noreply@anthropic.com>"

# 5. kit-onboarding-pr — base has nothing kit-related, branch adds attri-dev-kit.yml only
echo ">> kit-onboarding-pr"
DIR="$FIXTURES/kit-onboarding-pr"
# Clean any prior kit workflow file before init so 'nothing to commit' can't occur
rm -f "$DIR/.github/workflows/attri-dev-kit.yml"
init_repo "$DIR" "dev@example.com" "Dev"
echo "console.log('hi')" > "$DIR/app.js"
git -C "$DIR" add -A
git -C "$DIR" commit -q -m "chore: baseline"
git -C "$DIR" checkout -q -b chore/onboard 2>/dev/null || git -C "$DIR" checkout -q chore/onboard
mkdir -p "$DIR/.github/workflows"
cp "$ROOT/examples/multi-language-monorepo/.github/workflows/attri-dev-kit.yml" "$DIR/.github/workflows/attri-dev-kit.yml"
git -C "$DIR" add -A
git -C "$DIR" commit -q -m "chore: onboard attri-dev-kit"
git -C "$DIR" checkout -q main

echo ""
echo "✅ All fixtures built."
