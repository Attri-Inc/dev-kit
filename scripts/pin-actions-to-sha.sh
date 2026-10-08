#!/usr/bin/env bash
# Replaces every `uses: org/repo@vX` with the resolved commit SHA + comment of the version.
# Run once after a release; Dependabot then keeps the SHAs current.
# Requires: gh CLI authenticated.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-$ROOT/.github}"

mapfile -t FILES < <(find "$TARGET" -type f \( -name '*.yml' -o -name '*.yaml' \))

resolve() {
  local repo="$1" ref="$2"
  gh api "repos/$repo/git/ref/tags/$ref" --jq '.object.sha' 2>/dev/null \
    || gh api "repos/$repo/commits/$ref" --jq '.sha' 2>/dev/null \
    || echo ""
}

for f in "${FILES[@]}"; do
  while read -r _line_no line; do
    if [[ "$line" =~ uses:[[:space:]]+([^[:space:]]+/[^@]+)@([^[:space:]#]+) ]]; then
      repo="${BASH_REMATCH[1]}"
      ref="${BASH_REMATCH[2]}"
      # skip if already a 40-char SHA
      if [[ "$ref" =~ ^[a-f0-9]{40}$ ]]; then continue; fi
      # skip self-references
      [[ "$repo" == "Attri-Inc/dev-kit"* ]] && continue
      sha=$(resolve "$repo" "$ref")
      if [ -n "$sha" ]; then
        printf "  %s  %s@%s -> %s\n" "$f" "$repo" "$ref" "${sha:0:7}"
        # In-place replace, append comment with original ref. Use perl with
        # \Q..\E (quotemeta) so version chars like '.' are matched literally,
        # a token-boundary lookahead so '@v1' does NOT rewrite the 'v1' inside
        # '@v1.2.3', and %ENV so repo/ref/sha can never inject into the program.
        # The previous unescaped `sed` could corrupt unrelated lines. (audit H8)
        repo="$repo" ref="$ref" sha="$sha" perl -pi -e '
          my ($r, $v, $s) = @ENV{qw/repo ref sha/};
          s/\Q$r\E\@\Q$v\E(?=[\s#"]|$)/$r\@$s # $v/g;
        ' "$f"
      fi
    fi
  done < <(grep -n 'uses:' "$f" || true)
done

echo ""
echo "Done. Review with: git diff $TARGET"
echo "Dependabot will keep SHAs current via .github/dependabot.yml."
