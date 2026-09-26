#!/usr/bin/env python3
"""Portable presentation for measured R2 benchmark evidence."""

from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Any


ROLE_PATH_TOKENS = {
    "candidateRoot": "$R2_CANDIDATE_ROOT",
    "referenceRoot": "$R2_REFERENCE_ROOT",
    "workRoot": "$R2_WORK_ROOT",
}

PATH_PRESENTATION = {
    "scheme": "r2-release-role-root-tokens-v1",
    "tokens": ROLE_PATH_TOKENS,
    "scope": (
        "Machine-local reference, candidate, and work root prefixes are replaced; "
        "relative paths, measured values, content hashes, and binary identities are "
        "preserved."
    ),
}

MACHINE_LOCAL_PATH_MARKERS = ("/Users/", "/private/tmp/", "/tmp/")
ROLE_TOKEN_PATTERN = re.compile(r"\$R2_[A-Z0-9_]+")


def present_portable_paths(
    evidence: dict[str, Any], roots: dict[str, Path]
) -> dict[str, Any]:
    """Replace exact measured root prefixes with unambiguous role tokens."""
    if set(roots) != set(ROLE_PATH_TOKENS):
        raise RuntimeError("portable evidence requires every exact role root")

    canonical = {
        role: path.expanduser().resolve(strict=False) for role, path in roots.items()
    }
    for role, root in canonical.items():
        for other_role, other_root in canonical.items():
            if role >= other_role:
                continue
            if root == other_root or root in other_root.parents or other_root in root.parents:
                raise RuntimeError(
                    f"portable evidence role roots overlap: {role}, {other_role}"
                )

    replacements: set[tuple[str, str]] = set()
    for role, path in roots.items():
        token = ROLE_PATH_TOKENS[role]
        aliases = {
            os.path.abspath(os.path.expanduser(str(path))),
            str(path.expanduser().resolve(strict=False)),
        }
        replacements.update((alias.rstrip(os.sep), token) for alias in aliases)

    ordered = sorted(replacements, key=lambda item: len(item[0]), reverse=True)

    def replace(value: Any) -> Any:
        if isinstance(value, dict):
            return {key: replace(item) for key, item in value.items()}
        if isinstance(value, list):
            return [replace(item) for item in value]
        if not isinstance(value, str):
            return value
        for prefix, token in ordered:
            if value == prefix or value.startswith(f"{prefix}{os.sep}"):
                return f"{token}{value[len(prefix):]}"
        return value

    result = replace(evidence)
    reject_unpresented_roots(result, tuple(prefix for prefix, _ in ordered))
    result["pathPresentation"] = PATH_PRESENTATION
    validate_portable_path_presentation(result)
    return result


def validate_portable_path_presentation(evidence: dict[str, Any]) -> None:
    """Reject ambiguous tokens and machine-local absolute paths."""
    if evidence.get("pathPresentation") != PATH_PRESENTATION:
        raise RuntimeError("calibration path presentation mismatch")

    tokens = tuple(ROLE_PATH_TOKENS.values())

    def validate(value: Any) -> None:
        if isinstance(value, dict):
            for item in value.values():
                validate(item)
            return
        if isinstance(value, list):
            for item in value:
                validate(item)
            return
        if not isinstance(value, str):
            return
        unknown_tokens = [
            token for token in ROLE_TOKEN_PATTERN.findall(value) if token not in tokens
        ]
        if unknown_tokens:
            raise RuntimeError(
                f"calibration uses an unknown role-root token: {unknown_tokens[0]}"
            )
        if any(marker in value for marker in MACHINE_LOCAL_PATH_MARKERS):
            raise RuntimeError(
                f"calibration retains a machine-local absolute path: {value}"
            )

    validate(evidence)


def reject_unpresented_roots(value: Any, root_prefixes: tuple[str, ...]) -> None:
    """Reject embedded roots and boundary lookalikes the projection did not replace."""
    if isinstance(value, dict):
        for item in value.values():
            reject_unpresented_roots(item, root_prefixes)
        return
    if isinstance(value, list):
        for item in value:
            reject_unpresented_roots(item, root_prefixes)
        return
    if isinstance(value, str) and any(prefix in value for prefix in root_prefixes):
        raise RuntimeError(f"calibration retains an unpresented role-root prefix: {value}")
