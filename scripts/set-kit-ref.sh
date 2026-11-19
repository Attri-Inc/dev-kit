#!/usr/bin/env bash
# Point every internal kit reference (Attri-Inc/dev-kit/...@<ref>) under
# .github/ at one ref.
#
# Why: gate.yml loads the kit's composite actions by full reference, not by
# path. A branch that changes an action therefore runs main's copy of it,
# until its references point at the branch itself.
#
# Test a branch on a real repo:
#   scripts/set-kit-ref.sh my-branch   # commit this on the branch
#   ...point a consumer wrapper at gate.yml@my-branch and run its PRs...
#   scripts/set-kit-ref.sh main        # restore before merging
set -euo pipefail

REF="${1:?usage: set-kit-ref.sh <branch|tag|sha>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

grep -rlE 'Attri-Inc/dev-kit/\.github/[^@[:space:]]+@' "$ROOT/.github" \
  | while IFS= read -r f; do
      REF="$REF" perl -pi -e 's{(Attri-Inc/dev-kit/\.github/[^@\s]+)\@[^\s#]+}{$1\@$ENV{REF}}g' "$f"
    done

echo "Internal kit references now point at @${REF}:"
grep -rhoE 'Attri-Inc/dev-kit/\.github/[^@[:space:]]+@[^[:space:]]+' "$ROOT/.github" \
  | sed 's/.*@/@/' | sort | uniq -c
