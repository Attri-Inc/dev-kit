#!/usr/bin/env bash
# Stop hook — when Claude finishes a session, warn about unpushed dangerous changes.
set -euo pipefail
cd "${CLAUDE_PROJECT_DIR:-.}"

# Are we on a protected branch?
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
case "$branch" in
  main|master|prod|production|release|qa|uat|staging)
    if ! git diff-index --quiet HEAD --; then
      echo "::warning::Uncommitted changes on protected branch '$branch'. DO NOT commit directly — open a PR." >&2
    fi
    ;;
esac

# Any committed but-unpushed changes that touch sensitive files?
# shellcheck disable=SC1083 # @{u} is git upstream-tracking syntax, not a brace expansion
if git log --oneline @{u}..HEAD 2>/dev/null | grep -q .; then
  # shellcheck disable=SC1083
  changed=$(git diff --name-only @{u}..HEAD 2>/dev/null)
  if echo "$changed" | grep -qE '(\.env|credentials|token\.|\.pem|\.key|firebase|secret)'; then
    echo "::warning::Local commits touch sensitive file patterns. Review before pushing." >&2
  fi
fi
