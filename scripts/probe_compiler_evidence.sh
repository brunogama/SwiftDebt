#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repository_root=$(cd "$script_dir/.." && pwd)
fixture_root="$repository_root/Tests/CompilerEvidenceProbe/Sources"
output_root=${1:-"$repository_root/.scratch/compiler-evidence-probe"}

for command_name in swiftc jq rg; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'Required command is unavailable: %s\n' "$command_name" >&2
        exit 2
    fi
done

mkdir -p "$output_root"

run_probe() {
    local name=$1
    shift

    local status
    if "$@" >"$output_root/$name.json" 2>"$output_root/$name.stderr"; then
        status=0
    else
        status=$?
    fi
    printf '%s\n' "$status" >"$output_root/$name.exit"

    if jq -e . "$output_root/$name.json" >/dev/null; then
        printf 'valid\n' >"$output_root/$name.json-status"
    else
        printf 'invalid\n' >"$output_root/$name.json-status"
    fi
}

swiftc -version >"$output_root/swift-version.txt" 2>&1
swiftc -help-hidden >"$output_root/swift-help-hidden.txt" 2>&1

common_arguments=(-module-name main -typecheck -dump-ast -dump-ast-format json)
run_probe type-error swiftc "${common_arguments[@]}" "$fixture_root/TypeError/TypeError.swift"
run_probe conditional-default swiftc "${common_arguments[@]}" \
    "$fixture_root/ConditionalOverload/ConditionalOverload.swift"
run_probe conditional-feature-a swiftc "${common_arguments[@]}" -D FEATURE_A \
    "$fixture_root/ConditionalOverload/ConditionalOverload.swift"
run_probe observable-macro swiftc "${common_arguments[@]}" \
    "$fixture_root/ObservableMacro/ObservableMacro.swift"

default_usr=$(jq -r \
    '.. | objects | select((.decl_usr? // "") | startswith("s:4main6selecty")) | .decl_usr' \
    "$output_root/conditional-default.json" | sort -u | head -1)
feature_usr=$(jq -r \
    '.. | objects | select((.decl_usr? // "") | startswith("s:4main6selecty")) | .decl_usr' \
    "$output_root/conditional-feature-a.json" | sort -u | head -1)
macro_members=$(jq -r \
    '.. | objects | select(((.range.buffer_id? // "") | startswith("@__swiftmacro_"))) | .name?.base_name?.name? // empty' \
    "$output_root/observable-macro.json" | sort -u | paste -sd, -)
format_warning=$(rg 'no format is guaranteed stable across different compiler versions' \
    "$output_root/swift-help-hidden.txt" || true)

{
    cat "$output_root/swift-version.txt"
    printf '\n%s\n' "$format_warning"
    printf 'type-error: exit=%s json=%s\n' \
        "$(<"$output_root/type-error.exit")" "$(<"$output_root/type-error.json-status")"
    printf 'conditional-default: exit=%s json=%s bound=%s\n' \
        "$(<"$output_root/conditional-default.exit")" \
        "$(<"$output_root/conditional-default.json-status")" "$default_usr"
    printf 'conditional-feature-a: exit=%s json=%s bound=%s\n' \
        "$(<"$output_root/conditional-feature-a.exit")" \
        "$(<"$output_root/conditional-feature-a.json-status")" "$feature_usr"
    printf 'observable-macro: exit=%s json=%s generated-members=%s\n' \
        "$(<"$output_root/observable-macro.exit")" \
        "$(<"$output_root/observable-macro.json-status")" "$macro_members"
} | tee "$output_root/summary.txt"
