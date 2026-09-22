#!/usr/bin/env python3
"""Synchronize SwiftDebt release versions and plan semantic releases."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from release_version_files import audit, replace_versions
from release_version_git import prepare_plan
from release_version_model import BumpLevel, ReleaseError, SemanticVersion, requested_bump


def main(arguments: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("check")
    setter = subparsers.add_parser("set")
    setter.add_argument("version")
    subparsers.add_parser("prepare")
    args = parser.parse_args(arguments)
    root = args.root.resolve()
    try:
        if args.command == "check":
            version, blocks, failures = audit(root)
            if failures:
                raise ReleaseError("\n".join(failures))
            print(f"release version: PASS ({version}, {len(blocks)} markers)")
            return 0
        if args.command == "set":
            target = SemanticVersion.parse(args.version)
            replace_versions(root, target)
            print(target)
            return 0
        plan = prepare_plan(root)
        if plan.requires_release:
            replace_versions(root, plan.target)
        print(plan.target)
        return 0 if plan.requires_release else 3
    except ReleaseError as error:
        print(f"release version: FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
