#!/usr/bin/env bash
# Strips AI agent Co-Authored-By trailers from a commit message file.
# Used as a commit-msg hook via prek.
# Usage: strip_ai_coauthors.sh <commit-msg-file>

set -euo pipefail

FILE="${1:?commit message file required}"

# Patterns: claude, anthropic, copilot, github-actions[bot], gemini, chatgpt, openai.
sed -i.bak -E \
  '/^[Cc]o-[Aa]uthored-[Bb]y:.*([Cc]laude|[Aa]nthropic|[Cc]opilot|github-actions\[bot\]|[Gg]emini|[Cc]hat[Gg][Pp][Tt]|[Oo]pen[Aa][Ii])/d' \
  "$FILE"

rm -f "${FILE}.bak"
