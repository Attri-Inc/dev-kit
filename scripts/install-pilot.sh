#!/usr/bin/env bash
# Pilot installer — drops attri-dev-kit.yml into a target repo for manual review.
# Does NOT push, does NOT open a PR, does NOT modify org settings.
#
# Usage: ./scripts/install-pilot.sh <target-repo-path> <stack>
#   stack ∈ {python, typescript, go, terraform, java, monorepo}
#
# It creates a branch and a single commit in the target repo, then PRINTS the
# push + `gh pr create` commands for you to run. You push and open the PR
# yourself — the kit never auto-pushes or auto-merges. The target working tree
# must be clean and the onboarding branch must not already exist.

set -euo pipefail

TARGET="${1:-}"
STACK="${2:-monorepo}"

if [ -z "$TARGET" ] || [ ! -d "$TARGET" ]; then
  echo "Usage: $0 <target-repo-path> <stack>" >&2
  echo "Stacks: python, typescript, go, terraform, java, monorepo" >&2
  exit 2
fi

case "$STACK" in
  python)     EXAMPLE="python-fastapi" ;;
  typescript) EXAMPLE="nextjs-app" ;;
  go)         EXAMPLE="go-mcp-server" ;;
  terraform)  EXAMPLE="terraform-iac" ;;
  java)       EXAMPLE="java-spring" ;;
  monorepo)   EXAMPLE="multi-language-monorepo" ;;
  *) echo "Unknown stack: $STACK" >&2; exit 2 ;;
esac

KIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$KIT_ROOT/examples/$EXAMPLE/.github/workflows/attri-dev-kit.yml"

if [ ! -f "$SRC" ]; then
  echo "Example not found: $SRC" >&2
  exit 2
fi

cd "$TARGET"

# Operating on a human's working repo — fail loudly rather than silently
# polluting it. (audit H7)
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "::error::$TARGET is not a git repository." >&2
  exit 1
fi

if [ -f .github/workflows/attri-dev-kit.yml ]; then
  echo "::warning::$TARGET already has .github/workflows/attri-dev-kit.yml — aborting."
  exit 1
fi

# Refuse to run against a dirty tree — a branch checkout could carry unrelated
# uncommitted changes onto the onboarding branch.
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "::error::$TARGET has uncommitted changes. Commit or stash them first." >&2
  exit 1
fi

BRANCH="chore/onboard-attri-dev-kit"

# Don't silently switch to a pre-existing (possibly stale/divergent) branch.
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "::error::Branch '$BRANCH' already exists in $TARGET. Delete it or finish that work first." >&2
  exit 1
fi
git checkout -b "$BRANCH"

mkdir -p .github/workflows
cp "$SRC" .github/workflows/attri-dev-kit.yml
git add .github/workflows/attri-dev-kit.yml
git commit -m "chore: onboard attri-dev-kit ($STACK example)

Adds .github/workflows/attri-dev-kit.yml calling Attri-Inc/dev-kit@main.

This is opt-in. Nothing else in the repo changes. The kit emits SARIF
annotations on PRs and never modifies code. Review the kit at
https://github.com/Attri-Inc/dev-kit before merging."

echo ""
echo "✅ Workflow file added on branch $BRANCH."
echo ""
echo "Next steps:"
echo "  cd $TARGET"
echo "  git push -u origin $BRANCH"
echo "  gh pr create --title 'chore: onboard attri-dev-kit' --body 'See https://github.com/Attri-Inc/dev-kit/blob/main/docs/per-repo-onboarding-checklist.md'"
echo ""
echo "Do NOT auto-merge. Wait for the kit to run on the PR; verify it's catching what you expect; then merge."
