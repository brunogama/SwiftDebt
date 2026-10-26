#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$script_directory"
while [[ "$repository_root" != "/" && ! -f "$repository_root/Package.swift" ]]; do
    repository_root="$(dirname "$repository_root")"
done
[[ -f "$repository_root/Package.swift" ]] || {
    printf 'Could not locate the SwiftDebt repository from %s\n' "$script_directory" >&2
    exit 1
}
binary="$repository_root/.build/debug/swift-debt"
expected_version="SwiftDebt $(<"$repository_root/VERSION")"
feature="metrics"
doctor_only=false

usage() {
    cat <<'EOF'
Usage: verify.sh [--doctor] [--feature metrics|debt|plugins]

  --doctor                    Check an existing build without writing reports.
  --feature NAME              Run one isolated end-to-end feature proof.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --doctor)
            doctor_only=true
            shift
            ;;
        --feature)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            feature="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

case "$feature" in
    metrics|debt|plugins) ;;
    *)
        printf 'Unknown feature: %s\n' "$feature" >&2
        exit 2
        ;;
esac

doctor() {
    [[ -x "$binary" ]] || {
        printf 'Missing executable: %s\nRun: swift build --build-tests\n' "$binary" >&2
        return 1
    }
    local version
    version="$("$binary" --version)"
    [[ "$version" == "$expected_version" ]] || {
        printf 'Version mismatch: expected %s, got %s\n' "$expected_version" "$version" >&2
        return 1
    }
    "$binary" --help | grep -Fq 'swift-debt analyze'
    "$binary" --help | grep -Fq 'swift-debt debt analyze'
    printf 'PASS doctor: %s\n' "$version"
}

if "$doctor_only"; then
    doctor
    exit 0
fi

doctor

evidence_root="$repository_root/.verification/evidence/run-$(date -u +%Y%m%dT%H%M%SZ)-$$"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/swift-debt-verify.XXXXXX")"
mkdir -p "$evidence_root"

cleanup() {
    rm -rf "$fixture_root"
}
trap cleanup EXIT INT TERM

record_command() {
    local name="$1"
    shift
    {
        printf '$'
        printf ' %q' "$@"
        printf '\n'
    } > "$evidence_root/$name.command"
    set +e
    "$@" > "$evidence_root/$name.log" 2>&1
    local status=$?
    set -e
    printf 'exit=%s\n' "$status" >> "$evidence_root/$name.command"
    if [[ "$status" -ne 0 ]]; then
        cat "$evidence_root/$name.log" >&2
        return "$status"
    fi
}

mkdir -p "$fixture_root/Sources"
cat > "$fixture_root/Sources/Source.swift" <<'EOF'
struct InvoiceProcessor {
    func total(_ values: [Int]) -> Int {
        var total = 0
        for value in values {
            if value > 0 {
                total += value
            }
        }
        return total
    }
}
EOF

case "$feature" in
    metrics)
        record_command metrics \
            "$binary" analyze "$fixture_root/Sources" --format json --jobs 1 \
            --output "$evidence_root/metrics.json"
        record_command metrics_repeat \
            "$binary" analyze "$fixture_root/Sources" --format json --jobs 4 \
            --output "$evidence_root/metrics-repeat.json"
        cmp "$evidence_root/metrics.json" "$evidence_root/metrics-repeat.json"
        python3 - "$evidence_root/metrics.json" "$evidence_root/metrics-repeat.json" > "$evidence_root/validation.log" <<'PY'
import json
import pathlib
import sys

first_path, second_path = map(pathlib.Path, sys.argv[1:])
first = json.loads(first_path.read_text())
second = json.loads(second_path.read_text())
assert first["complete"] is True
assert first["analyzedFileCount"] == 1
assert len(first["metrics"]) == 10
assert first["inputFiles"] == ["Source.swift"]
assert first == second
print("PASS: complete ten-metric report and byte-identical repeat")
PY
        ;;
    debt)
        record_command debt \
            "$binary" debt analyze "$fixture_root/Sources" --format debt-json --jobs 1 \
            --debt-reference-time 2026-09-12T00:00:00Z --top 5 \
            --output "$evidence_root/debt.json"
        python3 - "$evidence_root/debt.json" > "$evidence_root/validation.log" <<'PY'
import json
import pathlib
import sys

report = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert report["schemaVersion"] >= 1
assert report["reportKind"] == "swiftdebt-report"
assert report["items"]
assert report["summary"]["rankedItemCount"] == len(report["items"])
assert any("not a git repository" in item["reason"] for item in report["missingEvidence"])
print(f"PASS: ranked debt report schema {report['schemaVersion']} with {len(report['items'])} items")
PY
        ;;
    plugins)
        record_command plugins \
            python3 "$repository_root/scripts/smoke-test.py" --binary "$binary" --plugins \
            --timeout 900
        cp "$evidence_root/plugins.log" "$evidence_root/plugin-smoke.log"
        printf 'PASS: command and build plugin smoke harness\n' > "$evidence_root/validation.log"
        ;;
esac

printf 'PASS feature=%s evidence=%s\n' "$feature" "$evidence_root"
