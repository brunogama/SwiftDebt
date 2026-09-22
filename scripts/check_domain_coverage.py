#!/usr/bin/env python3
"""Run the test suite and require complete SCMACore line coverage."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Optional


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Require 100% executable line coverage for Sources/SCMACore."
    )
    parser.add_argument(
        "--coverage-json",
        type=Path,
        help="Use an existing SwiftPM code coverage export instead of running tests.",
    )
    return parser.parse_args()


def coverage_path(root: Path, supplied: Optional[Path]) -> Path:
    if supplied is not None:
        return supplied.resolve()
    subprocess.run(
        ["swift", "test", "--enable-code-coverage"],
        cwd=root,
        check=True,
    )
    completed = subprocess.run(
        ["swift", "test", "--show-codecov-path"],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    )
    return Path(completed.stdout.strip()).resolve()


def main() -> int:
    options = arguments()
    root = Path(__file__).resolve().parent.parent
    domain = (root / "Sources" / "SCMACore").resolve()
    report_path = coverage_path(root, options.coverage_json)
    report = json.loads(report_path.read_text(encoding="utf-8"))
    rows: dict[str, tuple[int, int]] = {}
    for dataset in report.get("data", []):
        for file_report in dataset.get("files", []):
            source = Path(file_report["filename"]).resolve()
            try:
                relative = source.relative_to(domain)
            except ValueError:
                continue
            lines = file_report["summary"]["lines"]
            name = str(relative)
            if name in rows:
                raise RuntimeError(f"duplicate coverage record for {name}")
            rows[name] = (int(lines["covered"]), int(lines["count"]))

    if not rows:
        raise RuntimeError(f"no executable coverage records found under {domain}")

    missed_total = 0
    for name in sorted(rows):
        covered, count = rows[name]
        missed = count - covered
        missed_total += missed
        percent = 100 * covered / count if count else 100
        print(f"{percent:6.2f}% {covered:4}/{count:4} {name}")

    covered_total = sum(covered for covered, _ in rows.values())
    line_total = sum(count for _, count in rows.values())
    total_percent = 100 * covered_total / line_total if line_total else 100
    print(f"TOTAL {total_percent:.2f}% {covered_total}/{line_total}")
    if missed_total:
        print(f"domain coverage: FAIL ({missed_total} executable lines uncovered)", file=sys.stderr)
        return 1
    print("domain coverage: PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, KeyError, TypeError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        print(f"domain coverage: error: {error}", file=sys.stderr)
        raise SystemExit(2)
