#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
SKILL_DIR="${SKILL_DIR_OVERRIDE:-$(cd -P -- "$SCRIPT_DIR/.." && pwd)}"
readonly SKILL_DIR
readonly CSV_PATH="$SKILL_DIR/reference/skills.csv"
readonly PI_BIN="${PI_BIN:-pi}"
# agentmemory: loaded explicitly because --no-extensions below disables ambient
# extension discovery, which would otherwise drop the agentmemory auto-recall and
# memory tools. Guarded on existence so the runner still works without it.
readonly AGENTMEMORY_EXT="${AGENTMEMORY_EXT:-$HOME/.pi/agent/extensions/agentmemory/index.ts}"

fail() {
	printf 'delegating read-only Pi: %s\n' "$*" >&2
	exit 1
}

(($# >= 2)) || fail "usage: $0 <selector> <task>"
selector="$1"
shift
task="$*"
[[ -n "$selector" ]] || fail "selector must not be empty"
[[ -n "$task" ]] || fail "task must not be empty"
[[ -f "$CSV_PATH" ]] || fail "selector CSV not found: $CSV_PATH"

repository_root="$(git -C "$SKILL_DIR" rev-parse --show-toplevel 2>/dev/null)" ||
	fail "could not resolve repository root"
# Run the child from the repository root so its read, grep, find, and ls
# requests inspect the intended tree even when invoked from elsewhere.
cd -- "$repository_root" || fail "could not enter repository root"

match_count=0
matched_path=""
while IFS=';' read -r key raw_path _; do
	key="${key%$'\r'}"
	raw_path="${raw_path%$'\r'}"
	[[ "$key" == "skill_name" ]] && continue
	[[ "$key" == "$selector" ]] || continue
	((match_count += 1))
	matched_path="$raw_path"
done <"$CSV_PATH"

((match_count > 0)) || fail "selector not found: $selector"
((match_count == 1)) || fail "selector has multiple CSV matches: $selector"
[[ -n "$matched_path" ]] || fail "selector has an empty skill path: $selector"

if [[ "$matched_path" == /* ]]; then
	skill_path="$matched_path"
else
	skill_path="$repository_root/${matched_path#./}"
fi
if [[ -d "$skill_path" ]]; then
	skill_path="$(cd -P -- "$skill_path" && pwd)/SKILL.md"
elif [[ -f "$skill_path" ]]; then
	skill_path="$(cd -P -- "$(dirname -- "$skill_path")" && pwd)/$(basename -- "$skill_path")"
fi
[[ -f "$skill_path" ]] || fail "resolved skill file not found: $skill_path"
[[ "$skill_path" != "$SKILL_DIR/SKILL.md" ]] || fail "this skill cannot delegate to itself"

prompt="$(printf '%s\n\nTARGET SKILL:\n%s\n\nTASK:\n%s' \
	'Use the explicitly loaded skill as mandatory instructions. Before acting, inspect its references directory and read every relevant reference file recursively. Resolve relative paths from the target skill directory. Work read-only. Return only the final answer for the calling Pi agent.' \
	"$skill_path" \
	"$task")"

command -v python3 >/dev/null 2>&1 || fail "python3 is required to stream child events"

ext_args=()
if [[ -f "$AGENTMEMORY_EXT" ]]; then
	ext_args=(--extension "$AGENTMEMORY_EXT")
fi

pipeline_status=0
if "$PI_BIN" --mode json \
	--no-session \
	--no-extensions \
	--no-skills \
	"${ext_args[@]+"${ext_args[@]}"}" \
	--skill "$skill_path" \
	--tools read,grep,find,ls,memory_search,memory_health \
	"$prompt" | python3 -u "$SCRIPT_DIR/stream_json.py"; then
	:
else
	pipeline_statuses=("${PIPESTATUS[@]}")
	pipeline_status="${pipeline_statuses[0]}"
	((pipeline_status != 0)) || pipeline_status="${pipeline_statuses[1]}"
fi

if ((pipeline_status != 0)); then
	printf 'delegating read-only Pi: child failed with status %d\n' "$pipeline_status" >&2
	exit "$pipeline_status"
fi
