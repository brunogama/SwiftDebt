#!/usr/bin/env python3
"""Reject active references to the retired SwiftSCMA product identity."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


LEGACY_PATTERNS = (
    re.compile(pattern)
    for pattern in (
        r"SwiftSCMA",
        r"swiftscma",
        r"swift-deep-research",
        r"DeepResearch",
        r"SCMA(?:Core|Kit|Syntax|Reporting|Interactive|CommandPlugin|BuildPlugin|Command|Tests)",
        r"SCMA\.analysis\.swift",
        r"\.scma(?:\.json|\.example\.json|/)",
        r"(?<![A-Za-z0-9_-])scma(?![A-Za-z0-9_-])",
    )
)


def is_historical(path: str) -> bool:
    return (
        path == "CHECKSUMS.sha256"
        or path == ".audit/swiftdebt-rename.tsv"
        or path == "scripts/check_product_identity.py"
        or path.startswith("docs/validation-logs/")
        or path.startswith("benchmarks/debtmap-baseline/evidence/2026-09-22-swiftdebt-rename/diagnostics/")
        or path
        == "benchmarks/debtmap-baseline/evidence/2026-09-22-swiftdebt-rename/full-evidence-reference-report.json"
    )


def is_historical_line(path: str, line: str) -> bool:
    if "product-identity: allow historical" in line:
        return True
    return (
        path == ".github/workflows/debtmap-performance.yml"
        and "$RUNNER_TEMP/swift-debt-" in line
        and "/.build/release/scma" in line
    )


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    completed = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=root,
        check=True,
        capture_output=True,
    )
    patterns = tuple(LEGACY_PATTERNS)
    failures: list[str] = []
    for raw_path in completed.stdout.split(b"\0"):
        if not raw_path:
            continue
        path = raw_path.decode("utf-8")
        if is_historical(path):
            continue
        if any(pattern.search(path) for pattern in patterns):
            failures.append(f"legacy path: {path}")
            continue
        if not (root / path).is_file():
            continue
        try:
            text = (root / path).read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for line_number, line in enumerate(text.splitlines(), start=1):
            if is_historical_line(path, line):
                continue
            if any(pattern.search(line) for pattern in patterns):
                failures.append(f"{path}:{line_number}: {line.strip()}")

    if failures:
        print("product identity: FAIL", file=sys.stderr)
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1

    print("product identity: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
