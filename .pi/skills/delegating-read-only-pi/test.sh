#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
readonly RUNNER="$TEST_DIR/scripts/run.sh"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

# Deterministic agentmemory fixture: force the extension-present branch and
# assert its --extension flag is threaded through to the child invocation.
agentmemory_extension="$temporary_directory/agentmemory.ts"
: >"$agentmemory_extension"
export AGENTMEMORY_EXT="$agentmemory_extension"

fake_pi="$temporary_directory/pi"
cat >"$fake_pi" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$FAKE_PI_ARGUMENTS"
case "${FAKE_PI_MODE:-stream}" in
stream)
	printf '%s\n' '{"type":"agent_start"}'
	printf '%s\n' '{"type":"turn_start"}'
	printf '%s\n' '{"type":"tool_execution_start","toolName":"read"}'
	sleep 1
	printf '%s\n' '{"type":"tool_execution_end","toolName":"read","isError":false}'
	printf '%s\n' '{"type":"message_end","message":{"role":"assistant","content":[{"type":"text","text":"final-output"}]}}'
	printf '%s\n' '{"type":"agent_end","messages":[]}'
	;;
empty)
	printf '%s\n' '{"type":"agent_start"}'
	printf '%s\n' '{"type":"agent_end","messages":[]}'
	;;
fail)
	printf '%s\n' '{"type":"agent_start"}'
	exit 7
	;;
invalid)
	printf '%s\n' '{"type":"agent_start"}'
	printf '%s\n' 'not json at all'
	;;
truncated)
	printf '%s\n' '{"type":"agent_start"}'
	;;
esac
EOF
chmod +x "$fake_pi"

arguments_file="$temporary_directory/arguments"
stream_output="$temporary_directory/stream-output"
stream_error="$temporary_directory/stream-error"
FAKE_PI_ARGUMENTS="$arguments_file" PI_BIN="$fake_pi" \
	"$RUNNER" repo-code-review "Inspect the current diff." >"$stream_output" 2>"$stream_error" &
runner_pid=$!

for _ in {1..20}; do
	grep -Fx '[read-only child] started' "$stream_error" >/dev/null 2>&1 && break
	sleep 0.05
done
grep -Fx '[read-only child] started' "$stream_error" >/dev/null || {
	printf 'nested Pi progress was buffered until child exit\n' >&2
	kill "$runner_pid" 2>/dev/null || true
	wait "$runner_pid" 2>/dev/null || true
	exit 1
}
kill -0 "$runner_pid" 2>/dev/null || {
	printf 'fake child exited before the streaming assertion\n' >&2
	exit 1
}
wait "$runner_pid"
progress_lines="$(wc -l <"$stream_error" | tr -d '[:space:]')"
[[ "$progress_lines" == 1 ]] || {
	printf 'expected one minimal progress line, got %s\n' "$progress_lines" >&2
	exit 1
}
grep -Fx '[read-only child] started' "$stream_error" >/dev/null
grep -Fx 'final-output' "$stream_output" >/dev/null || {
	printf 'runner lost the final child response\n' >&2
	exit 1
}
if grep -F '"type"' "$stream_output" >/dev/null; then
	printf 'runner leaked raw JSON events to final stdout\n' >&2
	exit 1
fi
grep -Fx -- '--mode' "$arguments_file" >/dev/null
grep -Fx -- 'json' "$arguments_file" >/dev/null
grep -Fx -- '--no-session' "$arguments_file" >/dev/null
grep -Fx -- '--no-extensions' "$arguments_file" >/dev/null
grep -Fx -- '--no-skills' "$arguments_file" >/dev/null
grep -Fx -- '--tools' "$arguments_file" >/dev/null

grep -Fx -- 'read,grep,find,ls,memory_search,memory_health' "$arguments_file" >/dev/null
grep -Fx -- '--extension' "$arguments_file" >/dev/null
grep -Fx -- "$agentmemory_extension" "$arguments_file" >/dev/null
expected_skill="$(cd -P -- "$TEST_DIR/../repo-code-review" && pwd)/SKILL.md"
grep -Fx -- 'read,grep,find,ls' "$arguments_file" >/dev/null
# The expected skill path is resolved the way the runner resolves it: through
# the CSV's second column relative to the repository root.
on
grep -Fx -- "$expected_skill" "$arguments_file" >/dev/null

set +e
FAKE_PI_MODE=empty FAKE_PI_ARGUMENTS="$arguments_file" PI_BIN="$fake_pi" \
	"$RUNNER" repo-code-review "Inspect the current diff." >/dev/null 2>"$temporary_directory/empty-error"
empty_status=$?
FAKE_PI_MODE=fail FAKE_PI_ARGUMENTS="$arguments_file" PI_BIN="$fake_pi" \
	"$RUNNER" repo-code-review "Inspect the current diff." >/dev/null 2>"$temporary_directory/fail-error"
fail_status=$?
set -e

[[ "$empty_status" == 1 ]] || {
	printf 'expected empty output status 1, got %s\n' "$empty_status" >&2
	exit 1
}
[[ "$fail_status" == 7 ]] || {
	printf 'expected child status 7, got %s\n' "$fail_status" >&2
	exit 1
}

# Unknown selector: exactly zero CSV matches must fail.
set +e
FAKE_PI_ARGUMENTS="$arguments_file" PI_BIN="$fake_pi" \
	"$RUNNER" does-not-exist "Inspect nothing." >/dev/null 2>&1
unknown_status=$?
# Ambiguous selector: duplicate CSV rows must fail. Build a private CSV copy
# with a duplicated row through a temporary clone of the skill tree.
duplicate_root="$temporary_directory/duplicate"
mkdir -p "$duplicate_root"
cp -R "$TEST_DIR/." "$duplicate_root/"
printf 'repo-code-review;.pi/skills/repo-code-review/\n' >>"$duplicate_root/reference/skills.csv"
duplicate_status=0
SKILL_DIR_OVERRIDE="$duplicate_root" FAKE_PI_ARGUMENTS="$arguments_file" PI_BIN="$fake_pi" \
	bash "$TEST_DIR/scripts/run.sh" repo-code-review "Inspect the current diff." >/dev/null 2>&1 || duplicate_status=$?
# Malformed event stream: invalid JSON before agent_end must fail with 2.
FAKE_PI_MODE=invalid FAKE_PI_ARGUMENTS="$arguments_file" PI_BIN="$fake_pi" \
	"$RUNNER" repo-code-review "Inspect the current diff." >/dev/null 2>&1
invalid_status=$?
# Truncated stream: EOF before agent_end must fail with 2.
FAKE_PI_MODE=truncated FAKE_PI_ARGUMENTS="$arguments_file" PI_BIN="$fake_pi" \
	"$RUNNER" repo-code-review "Inspect the current diff." >/dev/null 2>&1
truncated_status=$?
set -e

[[ "$unknown_status" != 0 ]] || {
	printf 'unknown selector unexpectedly succeeded\n' >&2
	exit 1
}
[[ "$duplicate_status" != 0 ]] || {
	printf 'ambiguous selector unexpectedly succeeded\n' >&2
	exit 1
}
[[ "$invalid_status" == 2 ]] || {
	printf 'expected malformed stream status 2, got %s\n' "$invalid_status" >&2
	exit 1
}
[[ "$truncated_status" == 2 ]] || {
	printf 'expected truncated stream status 2, got %s\n' "$truncated_status" >&2
	exit 1
}

printf 'delegating read-only Pi runner tests passed\n'
