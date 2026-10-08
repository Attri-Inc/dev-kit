#!/usr/bin/env bash
# PreToolUse hook for Edit/Write — refuses to modify protected files.
# Anthropic recommends `command` hooks for production (agent hooks are EXPERIMENTAL).
set -euo pipefail

# Read JSON from stdin (Claude Code passes tool input as JSON)
input=$(cat)
file=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null || echo "")

if [ -z "$file" ]; then
  exit 0
fi

# Files Claude must never write to
PROTECTED=(
  '.env' '.env.local' '.env.dev' '.env.qa' '.env.uat' '.env.prod'
  '.env.production' '.env.staging' '.env.test' '.env.testing'
  'credentials.json' 'client_secret.json' 'token.json' 'token.pickle'
  'firebase_credential.json' 'service-account.json'
  '.aws/credentials' '.docker/config.json'
  'CLAUDE.md'
)

base=$(basename "$file")
for p in "${PROTECTED[@]}"; do
  if [[ "$base" == "$p" ]] || [[ "$file" == *"/$p" ]]; then
    cat <<JSON
{"continue": false, "stopReason": "Refusing to modify protected file: $file. If this is intentional, edit it manually outside Claude Code."}
JSON
    exit 0
  fi
done

# Allow
echo '{"continue": true}'
