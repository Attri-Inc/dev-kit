#!/usr/bin/env bash
# PreToolUse hook for Bash — blocks dangerous commands at the OS level.
# Read/Edit deny rules don't stop Bash, so we enforce here.
set -euo pipefail

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

if [ -z "$cmd" ]; then
  echo '{"continue": true}'
  exit 0
fi

# Hard-block patterns
BLOCKED=(
  'rm -rf /'
  'rm -rf ~'
  'rm -rf \.'
  'sudo'
  ':(){ :|:& };:'
  'curl[^|]+\|.*sh'
  'wget[^|]+\|.*sh'
  'git push.*--force'
  'git push -f'
  'git reset --hard'
  'git commit.*--no-verify'
  'npm publish'
  'pnpm publish'
  'yarn publish'
  '--dangerously-skip-permissions'
  'cat .env'
  'cat .env\.'
  'cat \./\.env'
  'cat \./credentials'
  'cat \./token\.'
)

for pat in "${BLOCKED[@]}"; do
  if echo "$cmd" | grep -qE "$pat"; then
    cat <<JSON
{"continue": false, "stopReason": "Refusing dangerous Bash: matches '$pat' in '$cmd'. If genuinely needed, run manually outside Claude Code."}
JSON
    exit 0
  fi
done

echo '{"continue": true}'
