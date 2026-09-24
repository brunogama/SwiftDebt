#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///

"""Generate a cached, multi-ecosystem repository architecture tree."""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from collections.abc import Sequence
from contextlib import suppress
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

VERSION = "1.0.0"
CACHE_SCHEMA_VERSION = 1
DEFAULT_THRESHOLD = 8  # A feature, breaking change, ecosystem change, or summarized tree change can independently justify regeneration.
DEFAULT_OVERVIEW_DEPTH = 3
DEFAULT_SLICE_DEPTH = 3
DEFAULT_MAX_TREE_LINES = 180
COMMAND_TIMEOUT_SECONDS = 30

# Architecture choice: one stdlib Python orchestrator is more portable than shell+git+jq and more maintainable than a shell/Python hybrid.
DEFAULT_WEIGHTS: dict[str, int] = {
    "head_changed": 1,  # Record freshness without letting a routine commit regenerate documentation by itself.
    "branch_changed": 3,  # Treat branch movement as context, then require another signal before regeneration.
    "commit": 1,  # Let sustained non-conventional work accumulate toward regeneration.
    "feat_commit": 6,  # Make one valid Conventional Commit feature reach the threshold with HEAD and commit points.
    "breaking_change": 12,  # Regenerate immediately for an explicit compatibility break.
    "raw_tree_changed": 8,  # Regenerate when the summarized directory architecture changes, independent of commit text.
    "ecosystem_markers_changed": 15,  # Regenerate immediately when a language or build ecosystem appears or disappears.
    "history_diverged": 8,  # Re-establish the baseline after rebase, force-update, or an unreachable cached commit.
}
WEIGHT_CAPS: dict[str, int] = {
    "commit": 8,
    "feat_commit": 3,
    "breaking_change": 2,
}

# Keep one shared list so eza, tree, Python walking, marker detection, and hashing prune the same noise.
IGNORE_PATTERNS: list[str] = [
    ".git",
    ".hg",
    ".svn",
    ".DS_Store",
    ".idea",
    ".vscode",
    ".cache",
    ".gradle",
    ".mypy_cache",
    ".next",
    ".nox",
    ".nuxt",
    ".pytest_cache",
    ".ruff_cache",
    ".svelte-kit",
    ".tox",
    ".turbo",
    ".venv",
    "Pods",
    "DerivedData",
    "__pycache__",
    "bower_components",
    "build",
    "coverage",
    "dist",
    "env",
    "htmlcov",
    "node_modules",
    "out",
    "target",
    "vendor",
    "venv",
    "*.class",
    "*.dll",
    "*.dylib",
    "*.exe",
    "*.lock",
    "*.o",
    "*.obj",
    "*.pyc",
    "*.pyo",
    "*.so",
    ".repo-tree-cache.json",
    "repo-tree.md",
]

OUTPUT_RELATIVE_PATH = Path("docs/architecture/repo-tree.md")
CACHE_RELATIVE_PATH = Path("docs/architecture/.repo-tree-cache.json")
ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
GIT_OBJECT_RE = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
FEAT_SUBJECT_RE = re.compile(r"^feat(?:\([^)]+\))?!?:")
BREAKING_SUBJECT_RE = re.compile(r"^[A-Za-z][A-Za-z0-9-]*(?:\([^)]+\))?!:")
BREAKING_BODY_RE = re.compile(r"^BREAKING(?: CHANGE|-CHANGE):", re.MULTILINE)


@dataclass(frozen=True)
class EcosystemSpec:
    name: str
    marker_patterns: tuple[str, ...]


ECOSYSTEM_SPECS: tuple[EcosystemSpec, ...] = tuple(
    sorted(
        (
            EcosystemSpec(
                ".NET", ("*.csproj", "*.fsproj", "*.sln", "Directory.Build.props")
            ),
            EcosystemSpec("Bazel", ("MODULE.bazel", "WORKSPACE", "WORKSPACE.bazel")),
            EcosystemSpec("C/C++", ("CMakeLists.txt", "meson.build", "*.vcxproj")),
            EcosystemSpec(
                "Containers",
                (
                    "Dockerfile",
                    "Dockerfile.*",
                    "compose.yaml",
                    "compose.yml",
                    "docker-compose.yaml",
                    "docker-compose.yml",
                ),
            ),
            EcosystemSpec("Dart/Flutter", ("pubspec.yaml",)),
            EcosystemSpec("Elixir", ("mix.exs",)),
            EcosystemSpec("Go", ("go.mod", "go.work")),
            EcosystemSpec(
                "Java/Kotlin",
                (
                    "pom.xml",
                    "build.gradle",
                    "build.gradle.kts",
                    "settings.gradle",
                    "settings.gradle.kts",
                ),
            ),
            EcosystemSpec("Nix", ("flake.nix", "default.nix")),
            EcosystemSpec("PHP", ("composer.json",)),
            EcosystemSpec(
                "Python",
                (
                    "pyproject.toml",
                    "requirements.txt",
                    "setup.py",
                    "setup.cfg",
                    "Pipfile",
                ),
            ),
            EcosystemSpec("Ruby", ("Gemfile", "*.gemspec")),
            EcosystemSpec("Rust", ("Cargo.toml",)),
            EcosystemSpec("Swift", ("Package.swift", "*.xcodeproj", "*.xcworkspace")),
            EcosystemSpec("Terraform", ("*.tf",)),
            EcosystemSpec(
                "TypeScript/JavaScript", ("package.json", "pnpm-workspace.yaml")
            ),
        ),
        key=lambda spec: (spec.name.casefold(), spec.name),
    )
)


@dataclass(frozen=True)
class EcosystemSlice:
    spec: EcosystemSpec
    markers: tuple[PurePosixPath, ...]
    roots: tuple[PurePosixPath, ...]


@dataclass(frozen=True)
class GitState:
    head: str
    short_head: str
    branch: str
    source_date: str
    commit_count: int


@dataclass(frozen=True)
class ChangeCounts:
    commits: int = 0
    features: int = 0
    breaking: int = 0
    other: int = 0
    history_diverged: bool = False


@dataclass(frozen=True)
class DriftDecision:
    score: int
    threshold: int
    head_changed: bool
    branch_changed: bool
    raw_tree_changed: bool
    ecosystem_markers_changed: bool
    changes: ChangeCounts
    regenerate: bool
    reason: str


class RepoTreeError(RuntimeError):
    """A user-actionable repository tree error."""


class CommandError(RepoTreeError):
    """An external command failed."""


def run_command(
    args: Sequence[str],
    *,
    cwd: Path,
    timeout: int = COMMAND_TIMEOUT_SECONDS,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.update({"LC_ALL": "C", "LANG": "C", "NO_COLOR": "1"})
    try:
        completed = subprocess.run(
            list(args),
            cwd=cwd,
            env=env,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="surrogateescape",
            timeout=timeout,
            check=False,
        )
    except FileNotFoundError as error:
        raise CommandError(f"required command is unavailable: {args[0]}") from error
    except subprocess.TimeoutExpired as error:
        raise CommandError(f"command timed out: {args[0]}") from error
    if check and completed.returncode != 0:
        stderr = completed.stderr
        detail = (
            stderr.strip().splitlines()[-1]
            if stderr.strip()
            else f"exit {completed.returncode}"
        )
        raise CommandError(f"{args[0]} failed: {detail}")
    return completed


def resolve_repo_root(candidate: Path) -> Path:
    completed = run_command(
        ["git", "rev-parse", "--show-toplevel"],
        cwd=candidate.resolve(),
    )
    root = Path(str(completed.stdout).strip()).resolve()
    if not root.is_dir():
        raise RepoTreeError("git repository root is unavailable")
    return root


def git_text(root: Path, *args: str) -> str:
    completed = run_command(["git", *args], cwd=root)
    return str(completed.stdout).strip()


def read_git_state(root: Path) -> GitState:
    head = git_text(root, "rev-parse", "HEAD")
    short_head = git_text(root, "rev-parse", "--short=8", "HEAD")
    branch_completed = run_command(
        ["git", "symbolic-ref", "--short", "-q", "HEAD"],
        cwd=root,
        check=False,
    )
    branch = str(branch_completed.stdout).strip() or "(detached)"
    source_timestamp = git_text(root, "show", "-s", "--format=%cI", "HEAD")
    source_date = source_timestamp[:10]
    try:
        commit_count = int(git_text(root, "rev-list", "--count", "HEAD"))
    except ValueError as error:
        raise RepoTreeError("git returned an invalid commit count") from error
    return GitState(head, short_head, branch, source_date, commit_count)


def matches_ignore(name: str) -> bool:
    return any(fnmatch.fnmatchcase(name, pattern) for pattern in IGNORE_PATTERNS)


def path_is_ignored(path: PurePosixPath) -> bool:
    return any(matches_ignore(part) for part in path.parts)


def list_repository_files(root: Path) -> tuple[PurePosixPath, ...]:
    completed = run_command(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=root,
    )
    paths: list[PurePosixPath] = []
    for item in completed.stdout.split("\0"):
        if not item:
            continue
        path = PurePosixPath(item)
        if path.is_absolute() or ".." in path.parts or path_is_ignored(path):
            continue
        paths.append(path)
    return tuple(
        sorted(
            set(paths),
            key=lambda path: (path.as_posix().casefold(), path.as_posix()),
        )
    )


def marker_matches(path: PurePosixPath, spec: EcosystemSpec) -> bool:
    return any(
        fnmatch.fnmatchcase(path.name, pattern) for pattern in spec.marker_patterns
    )


def collapse_nested_roots(roots: set[PurePosixPath]) -> tuple[PurePosixPath, ...]:
    ordered = sorted(
        roots,
        key=lambda root: (
            len(root.parts),
            root.as_posix().casefold(),
            root.as_posix(),
        ),
    )
    collapsed: list[PurePosixPath] = []
    for root in ordered:
        if any(root == existing or existing in root.parents for existing in collapsed):
            continue
        collapsed.append(root)
    return tuple(
        sorted(
            collapsed,
            key=lambda root: (root.as_posix().casefold(), root.as_posix()),
        )
    )


def detect_ecosystems(files: Sequence[PurePosixPath]) -> tuple[EcosystemSlice, ...]:
    slices: list[EcosystemSlice] = []
    for spec in ECOSYSTEM_SPECS:
        markers = tuple(path for path in files if marker_matches(path, spec))
        if not markers:
            continue
        roots = {marker.parent for marker in markers}
        slices.append(EcosystemSlice(spec, markers, collapse_nested_roots(roots)))
    return tuple(
        sorted(slices, key=lambda item: (item.spec.name.casefold(), item.spec.name))
    )


def ecosystem_marker_keys(slices: Sequence[EcosystemSlice]) -> tuple[str, ...]:
    return tuple(
        sorted(
            f"{item.spec.name}:{marker.as_posix()}"
            for item in slices
            for root in item.roots
            for marker in item.markers
            if marker.parent == root
        )
    )


def repository_directories(files: Sequence[PurePosixPath]) -> set[PurePosixPath]:
    directories: set[PurePosixPath] = {
        PurePosixPath("docs"),
        PurePosixPath("docs/architecture"),
    }
    for path in files:
        parent = path.parent
        while parent != PurePosixPath("."):
            if not path_is_ignored(parent):
                directories.add(parent)
            parent = parent.parent
    return directories


def is_descendant(path: PurePosixPath, base: PurePosixPath) -> bool:
    return base == PurePosixPath(".") or path == base or base in path.parents


def relative_to_base(path: PurePosixPath, base: PurePosixPath) -> PurePosixPath:
    if base == PurePosixPath("."):
        return path
    return path.relative_to(base)


def canonical_directory_tree(
    directories: set[PurePosixPath],
    base: PurePosixPath,
    depth: int,
) -> str:
    nodes: dict[str, dict] = {}
    for directory in sorted(
        directories,
        key=lambda path: (path.as_posix().casefold(), path.as_posix()),
    ):
        if not is_descendant(directory, base) or directory == base:
            continue
        relative = relative_to_base(directory, base)
        if len(relative.parts) > depth:
            continue
        current = nodes
        for part in relative.parts:
            current = current.setdefault(part, {})

    label = "." if base == PurePosixPath(".") else base.as_posix()
    lines = [label]

    def append_children(children: dict[str, dict], prefix: str) -> None:
        names = sorted(children, key=lambda name: (name.casefold(), name))
        for index, name in enumerate(names):
            last = index == len(names) - 1
            lines.append(f"{prefix}{'`-- ' if last else '|-- '}{name}")
            append_children(children[name], f"{prefix}{'    ' if last else '|   '}")

    append_children(nodes, "")
    return "\n".join(lines)


def build_raw_architecture_tree(
    directories: set[PurePosixPath],
    slices: Sequence[EcosystemSlice],
    overview_depth: int,
    slice_depth: int,
) -> str:
    parts = [
        "[overview]",
        canonical_directory_tree(directories, PurePosixPath("."), overview_depth),
    ]
    for item in slices:
        parts.append(f"[ecosystem:{item.spec.name}]")
        parts.extend(f"marker:{marker.as_posix()}" for marker in item.markers)
        for root in item.roots:
            parts.append(canonical_directory_tree(directories, root, slice_depth))
    return "\n".join(parts) + "\n"


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8", errors="surrogateescape")).hexdigest()


def valid_cache_timestamp(value: object) -> bool:
    if not isinstance(value, str):
        return False
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return False
    return parsed.tzinfo is not None


def load_cache(path: Path) -> dict[str, object] | None:
    try:
        if not path.is_file() or path.stat().st_size > 1_000_000:
            return None
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return None
    required = {
        "schema_version",
        "last_generated_commit",
        "branch",
        "generated_at_utc",
        "raw_tree_hash",
        "commit_count_baseline",
        "ecosystem_markers",
        "renderer",
        "threshold",
        "weights",
    }
    if not isinstance(value, dict) or set(value) != required:
        return None
    markers = value.get("ecosystem_markers")
    weights = value.get("weights")
    if (
        type(value.get("schema_version")) is not int
        or value["schema_version"] != CACHE_SCHEMA_VERSION
    ):
        return None
    if not isinstance(
        value.get("last_generated_commit"), str
    ) or not GIT_OBJECT_RE.fullmatch(value["last_generated_commit"]):
        return None
    if not isinstance(value.get("branch"), str) or not value["branch"]:
        return None
    if not valid_cache_timestamp(value.get("generated_at_utc")):
        return None
    if not isinstance(value.get("raw_tree_hash"), str) or not SHA256_RE.fullmatch(
        value["raw_tree_hash"]
    ):
        return None
    baseline = value.get("commit_count_baseline")
    if type(baseline) is not int or baseline < 0:
        return None
    if not isinstance(markers, list) or not all(
        isinstance(item, str) for item in markers
    ):
        return None
    if markers != sorted(set(markers)):
        return None
    if not isinstance(value.get("renderer"), str) or not value["renderer"]:
        return None
    threshold = value.get("threshold")
    if type(threshold) is not int or threshold < 1:
        return None
    if not isinstance(weights, dict) or set(weights) != set(DEFAULT_WEIGHTS):
        return None
    if any(type(weight) is not int or weight < 0 for weight in weights.values()):
        return None
    return value


def commit_exists(root: Path, commit: str) -> bool:
    completed = run_command(
        ["git", "cat-file", "-e", f"{commit}^{{commit}}"],
        cwd=root,
        check=False,
    )
    return completed.returncode == 0


def is_ancestor(root: Path, ancestor: str, descendant: str) -> bool:
    completed = run_command(
        ["git", "merge-base", "--is-ancestor", ancestor, descendant],
        cwd=root,
        check=False,
    )
    return completed.returncode == 0


def classify_commits(
    root: Path, cache: dict[str, object] | None, state: GitState
) -> ChangeCounts:
    if cache is None:
        return ChangeCounts()
    cached_head = str(cache["last_generated_commit"])
    if cached_head == state.head:
        return ChangeCounts()
    raw_baseline = cache.get("commit_count_baseline", 0)
    baseline = raw_baseline if isinstance(raw_baseline, int) else 0
    if not commit_exists(root, cached_head):
        count = max(0, state.commit_count - baseline)
        return ChangeCounts(count, 0, 0, count, True)

    diverged = not is_ancestor(root, cached_head, state.head)
    completed = run_command(
        ["git", "log", "--format=%x1e%H%x1f%s%x1f%b", f"{cached_head}..{state.head}"],
        cwd=root,
    )
    records = [
        record for record in str(completed.stdout).split("\x1e") if record.strip()
    ]
    features = 0
    breaking = 0
    for record in records:
        fields = record.strip("\n").split("\x1f", 2)
        subject = fields[1] if len(fields) > 1 else ""
        body = fields[2] if len(fields) > 2 else ""
        if FEAT_SUBJECT_RE.match(subject):
            features += 1
        if BREAKING_SUBJECT_RE.match(subject) or BREAKING_BODY_RE.search(body):
            breaking += 1
    total = len(records)
    return ChangeCounts(total, features, breaking, max(0, total - features), diverged)


def weighted_count(value: int, weight: int, cap: int | None = None) -> int:
    bounded = min(value, cap) if cap is not None else value
    return bounded * weight


def compute_drift(
    cache: dict[str, object] | None,
    state: GitState,
    changes: ChangeCounts,
    raw_tree_hash: str,
    markers: Sequence[str],
    weights: dict[str, int],
    threshold: int,
    output_exists: bool,
    force: bool,
) -> DriftDecision:
    head_changed = (
        cache is not None and cache.get("last_generated_commit") != state.head
    )
    branch_changed = cache is not None and cache.get("branch") != state.branch
    raw_tree_changed = cache is not None and cache.get("raw_tree_hash") != raw_tree_hash
    raw_cached_markers = cache.get("ecosystem_markers", ()) if cache is not None else ()
    cached_markers = (
        tuple(str(item) for item in raw_cached_markers)
        if isinstance(raw_cached_markers, list)
        else ()
    )
    markers_changed = cache is not None and tuple(markers) != cached_markers

    score = 0
    score += weights["head_changed"] if head_changed else 0
    score += weights["branch_changed"] if branch_changed else 0
    score += weighted_count(changes.commits, weights["commit"], WEIGHT_CAPS["commit"])
    score += weighted_count(
        changes.features, weights["feat_commit"], WEIGHT_CAPS["feat_commit"]
    )
    score += weighted_count(
        changes.breaking, weights["breaking_change"], WEIGHT_CAPS["breaking_change"]
    )
    score += weights["raw_tree_changed"] if raw_tree_changed else 0
    score += weights["ecosystem_markers_changed"] if markers_changed else 0
    score += weights["history_diverged"] if changes.history_diverged else 0

    if force:
        regenerate, reason = True, "forced by invocation"
    elif cache is None:
        regenerate, reason = True, "no valid cache existed"
    elif not output_exists:
        regenerate, reason = True, "the generated document was missing"
    elif score >= threshold:
        regenerate, reason = True, "the drift threshold was met"
    else:
        regenerate, reason = False, "no significant architectural drift"

    return DriftDecision(
        score,
        threshold,
        head_changed,
        branch_changed,
        raw_tree_changed,
        markers_changed,
        changes,
        regenerate,
        reason,
    )


def tree_ignore_expression() -> str:
    return "|".join(IGNORE_PATTERNS)


def clean_tree_output(text: str, max_lines: int) -> str:
    cleaned = ANSI_ESCAPE_RE.sub("", text)
    cleaned = (
        cleaned.encode("utf-8", errors="backslashreplace").decode("utf-8").rstrip()
    )
    lines = cleaned.splitlines() or ["."]
    if len(lines) > max_lines:
        omitted = len(lines) - max_lines + 1
        lines = lines[: max_lines - 1] + [f"... ({omitted} lines omitted)"]
    return "\n".join(lines)


def render_with_eza(
    root: Path, target: PurePosixPath, depth: int, max_lines: int
) -> str:
    executable = shutil.which("eza")
    if executable is None:
        raise CommandError("eza is unavailable")
    completed = run_command(
        [
            executable,
            "--tree",
            f"--level={depth}",
            "--all",
            "--only-dirs",
            "--group-directories-first",
            "--sort=name",
            "--color=never",
            "--icons=never",
            "--git-ignore",
            "--ignore-glob",
            tree_ignore_expression(),
            "--",
            target.as_posix(),
        ],
        cwd=root,
    )
    return clean_tree_output(str(completed.stdout), max_lines)


def render_with_tree(
    root: Path, target: PurePosixPath, depth: int, max_lines: int
) -> str:
    executable = shutil.which("tree")
    if executable is None:
        raise CommandError("tree is unavailable")
    completed = run_command(
        [
            executable,
            "-a",
            "-d",
            "-L",
            str(depth),
            "--dirsfirst",
            "-n",
            "--noreport",
            "--charset",
            "ascii",
            "-I",
            tree_ignore_expression(),
            "--",
            target.as_posix(),
        ],
        cwd=root,
    )
    return clean_tree_output(str(completed.stdout), max_lines)


def render_with_python(
    root: Path, target: PurePosixPath, depth: int, max_lines: int
) -> str:
    start = root if target == PurePosixPath(".") else root.joinpath(*target.parts)
    label = "." if target == PurePosixPath(".") else target.as_posix()
    lines = [label]

    def visible_directories(directory: Path) -> list[Path]:
        try:
            entries = list(directory.iterdir())
        except OSError as error:
            try:
                relative = directory.relative_to(root).as_posix()
            except ValueError:
                relative = "."
            raise RepoTreeError(f"cannot read directory: {relative}") from error
        return sorted(
            (
                entry
                for entry in entries
                if not entry.is_symlink()
                and entry.is_dir()
                and not matches_ignore(entry.name)
            ),
            key=lambda entry: (entry.name.casefold(), entry.name),
        )

    def append(directory: Path, level: int, prefix: str) -> None:
        if level >= depth or len(lines) >= max_lines:
            return
        children = visible_directories(directory)
        for index, child in enumerate(children):
            if len(lines) >= max_lines:
                return
            last = index == len(children) - 1
            lines.append(f"{prefix}{'`-- ' if last else '|-- '}{child.name}")
            append(child, level + 1, f"{prefix}{'    ' if last else '|   '}")

    append(start, 0, "")
    return clean_tree_output("\n".join(lines), max_lines)


class TreeRenderer:
    def __init__(self, preference: str, root: Path) -> None:
        self.root = root
        if preference == "python":
            self.candidates = ["python"]
        elif preference == "tree":
            self.candidates = ["tree", "python"]
        else:
            self.candidates = ["eza", "tree", "python"]
        self.selected: str | None = None

    def render(
        self, target: PurePosixPath, depth: int, max_lines: int
    ) -> tuple[str, str]:
        candidates = self.candidates
        if self.selected is not None:
            candidates = [
                self.selected,
                *(
                    candidate
                    for candidate in self.candidates
                    if candidate != self.selected
                ),
            ]
        for candidate in candidates:
            try:
                if candidate == "eza":
                    output = render_with_eza(self.root, target, depth, max_lines)
                elif candidate == "tree":
                    output = render_with_tree(self.root, target, depth, max_lines)
                else:
                    output = render_with_python(self.root, target, depth, max_lines)
                self.selected = candidate
                return output, candidate
            except CommandError:
                continue
        output = render_with_python(self.root, target, depth, max_lines)
        self.selected = "python"
        return output, "python"


def markdown_code(value: str) -> str:
    escaped = value.encode("unicode_escape", errors="backslashreplace").decode("ascii")
    escaped = escaped.replace("|", "\\|")
    longest = max(
        (len(match.group(0)) for match in re.finditer(r"`+", escaped)), default=0
    )
    delimiter = "`" * max(1, longest + 1)
    padding = (
        " " if escaped.startswith(("`", " ")) or escaped.endswith(("`", " ")) else ""
    )
    return f"{delimiter}{padding}{escaped}{padding}{delimiter}"


def markdown_fence(text: str) -> str:
    longest = max(
        (len(match.group(0)) for match in re.finditer(r"`+", text)), default=0
    )
    return "`" * max(3, longest + 1)


def fenced_text(text: str) -> str:
    fence = markdown_fence(text)
    return f"{fence}text\n{text}\n{fence}"


def roots_directory_names(
    directories: set[PurePosixPath],
    roots: Sequence[PurePosixPath],
) -> set[str]:
    names: set[str] = set()
    for directory in directories:
        if any(is_descendant(directory, root) for root in roots):
            names.update(part.casefold() for part in directory.parts)
    return names


def format_markers(markers: Sequence[PurePosixPath], limit: int = 8) -> str:
    shown = [markdown_code(marker.as_posix()) for marker in markers[:limit]]
    if len(markers) > limit:
        shown.append(f"{len(markers) - limit} more")
    return ", ".join(shown)


def ecosystem_description(item: EcosystemSlice, directories: set[PurePosixPath]) -> str:
    names = roots_directory_names(directories, item.roots)
    detected = f"Detected from {format_markers(item.markers)}."
    if item.spec.name == "Python" and {"src", "routers", "services", "models"}.issubset(
        names
    ):
        layout = (
            "The Python slice follows a src layout with routers, services, and models."
        )
    elif item.spec.name == "Python" and "src" in names:
        layout = "The Python slice follows a src layout."
    elif item.spec.name == "Terraform" and {"modules", "environments"}.issubset(names):
        layout = (
            "The Terraform slice separates reusable modules from environment roots."
        )
    elif item.spec.name == "TypeScript/JavaScript" and {
        "src",
        "components",
        "pages",
    }.issubset(names):
        layout = "The TypeScript/JavaScript slice uses a source layout that separates reusable components from route-level pages."
    elif item.spec.name == "Go" and {"cmd", "internal"}.issubset(names):
        layout = "The Go slice separates executable entry points under cmd from internal packages."
    elif item.spec.name == "Rust" and {"src", "crates"}.issubset(names):
        layout = "The Rust slice separates the root crate from workspace crates."
    elif item.spec.name == "Java/Kotlin" and {"src", "main", "test"}.issubset(names):
        layout = "The Java/Kotlin slice separates main and test source sets."
    elif item.spec.name == ".NET" and {"src", "tests"}.issubset(names):
        layout = "The .NET slice separates production projects from test projects."
    elif item.spec.name == "Containers":
        layout = "The container slice groups image and composition boundaries."
    else:
        layout = (
            f"The {item.spec.name} slice below shows its visible directory boundaries."
        )
    return f"{detected} {layout}"


def yes_no(value: bool) -> str:
    return "yes" if value else "no"


def render_markdown(
    state: GitState,
    decision: DriftDecision,
    renderer_name: str,
    overview_tree: str,
    slices: Sequence[EcosystemSlice],
    slice_trees: dict[tuple[str, str], str],
    directories: set[PurePosixPath],
    overview_depth: int,
    slice_depth: int,
) -> str:
    lines = [
        "# Repository Architecture Tree",
        "",
        "| Field | Value |",
        "| --- | --- |",
        f"| Commit | `{state.short_head}` |",
        f"| Branch | {markdown_code(state.branch)} |",
        f"| Source date | `{state.source_date}` |",
        f"| Tree renderer | `{renderer_name}` |",
        f"| Drift score | `{decision.score}` / `{decision.threshold}` |",
        "",
        "## Repository overview",
        "",
        f"Summarized directory view at depth {overview_depth}; generated artifacts and dependency or build noise use the shared ignore list.",
        "",
        fenced_text(overview_tree),
    ]

    for item in slices:
        lines.extend(
            ["", f"## {item.spec.name}", "", ecosystem_description(item, directories)]
        )
        for root in item.roots:
            label = "." if root == PurePosixPath(".") else root.as_posix()
            lines.extend(
                [
                    "",
                    f"### {markdown_code(label)}",
                    "",
                    f"Focused directory view at depth {slice_depth}.",
                    "",
                    fenced_text(slice_trees[(item.spec.name, root.as_posix())]),
                ]
            )

    changes = decision.changes
    lines.extend(
        [
            "",
            "## Change summary since last generation",
            "",
            f"- Commits considered: {changes.commits}",
            f"- Feature commits: {changes.features}",
            f"- Breaking changes: {changes.breaking}",
            f"- Other commits: {changes.other}",
            f"- HEAD changed: {yes_no(decision.head_changed)}",
            f"- Branch changed: {yes_no(decision.branch_changed)}",
            f"- Structural tree changed: {yes_no(decision.raw_tree_changed)}",
            f"- Ecosystem markers changed: {yes_no(decision.ecosystem_markers_changed)}",
            f"- History diverged: {yes_no(changes.history_diverged)}",
            f"- Drift score: {decision.score} (threshold {decision.threshold})",
            f"- Decision: Regenerated because {decision.reason}.",
            "",
        ]
    )
    return "\n".join(lines)


def resolve_architecture_paths(root: Path) -> tuple[Path, Path, Path]:
    architecture_dir = root / "docs" / "architecture"
    output_path = root / OUTPUT_RELATIVE_PATH
    cache_path = root / CACHE_RELATIVE_PATH
    resolved_root = root.resolve()
    for path in (architecture_dir, output_path, cache_path):
        if path.is_symlink():
            raise RepoTreeError(f"{path.name} must not be a symbolic link")
        try:
            path.resolve(strict=False).relative_to(resolved_root)
        except ValueError as error:
            raise RepoTreeError(
                "docs/architecture resolves outside the repository"
            ) from error
    return architecture_dir, output_path, cache_path


def create_architecture_directory(path: Path) -> None:
    try:
        path.mkdir(parents=True, exist_ok=True)
    except OSError as error:
        raise RepoTreeError("cannot create docs/architecture") from error


def atomic_write_text(path: Path, content: str) -> None:
    temporary: Path | None = None
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.is_symlink() or (path.exists() and not path.is_file()):
            raise RepoTreeError(
                f"cannot atomically write {path.name}: destination is not a regular file"
            )
        existing_mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{path.name}.", dir=path.parent
        )
        temporary = Path(temporary_name)
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, existing_mode)
        os.replace(temporary, path)
    except RepoTreeError:
        raise
    except (OSError, UnicodeError) as error:
        raise RepoTreeError(f"cannot atomically write {path.name}") from error
    finally:
        if temporary is not None:
            with suppress(FileNotFoundError):
                temporary.unlink()


def cache_document(
    state: GitState,
    raw_tree_hash: str,
    markers: Sequence[str],
    renderer: str,
    threshold: int,
    weights: dict[str, int],
) -> str:
    data = {
        "branch": state.branch,
        "commit_count_baseline": state.commit_count,
        "ecosystem_markers": list(markers),
        "generated_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "last_generated_commit": state.head,
        "raw_tree_hash": raw_tree_hash,
        "renderer": renderer,
        "schema_version": CACHE_SCHEMA_VERSION,
        "threshold": threshold,
        "weights": dict(sorted(weights.items())),
    }
    return json.dumps(data, indent=2, sort_keys=True) + "\n"


def parse_weight_overrides(values: Sequence[str]) -> dict[str, int]:
    weights = DEFAULT_WEIGHTS.copy()
    for value in values:
        if "=" not in value:
            raise RepoTreeError(f"invalid weight override: {value}")
        key, raw_weight = value.split("=", 1)
        if key not in weights:
            valid = ", ".join(sorted(weights))
            raise RepoTreeError(f"unknown weight '{key}'; valid weights: {valid}")
        try:
            weight = int(raw_weight)
        except ValueError as error:
            raise RepoTreeError(f"weight '{key}' must be an integer") from error
        if weight < 0:
            raise RepoTreeError(f"weight '{key}' must be non-negative")
        weights[key] = weight
    return weights


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="repo-tree",
        description="Maintain docs/architecture/repo-tree.md when architectural drift is significant.",
    )
    parser.add_argument(
        "--repo",
        type=Path,
        default=Path.cwd(),
        help="Repository path (default: current directory).",
    )
    parser.add_argument(
        "--renderer",
        choices=("auto", "eza", "tree", "python"),
        default="auto",
        help="Tree renderer preference (default: auto).",
    )
    parser.add_argument(
        "--threshold",
        type=int,
        default=DEFAULT_THRESHOLD,
        help=f"Regeneration score threshold (default: {DEFAULT_THRESHOLD}).",
    )
    parser.add_argument(
        "--weight",
        action="append",
        default=[],
        metavar="NAME=INT",
        help="Override one drift weight; repeat as needed.",
    )
    parser.add_argument(
        "--overview-depth",
        type=int,
        default=DEFAULT_OVERVIEW_DEPTH,
        help=f"Overview depth, 1-3 (default: {DEFAULT_OVERVIEW_DEPTH}).",
    )
    parser.add_argument(
        "--slice-depth",
        type=int,
        default=DEFAULT_SLICE_DEPTH,
        help=f"Ecosystem depth, 1-6 (default: {DEFAULT_SLICE_DEPTH}).",
    )
    parser.add_argument(
        "--max-lines",
        type=int,
        default=DEFAULT_MAX_TREE_LINES,
        help=f"Maximum lines per tree block (default: {DEFAULT_MAX_TREE_LINES}).",
    )
    parser.add_argument(
        "--force", action="store_true", help="Regenerate regardless of drift score."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report the decision without writing files.",
    )
    parser.add_argument("--version", action="version", version=f"repo-tree {VERSION}")
    return parser


def validate_args(args: argparse.Namespace) -> None:
    if args.threshold < 1:
        raise RepoTreeError("threshold must be at least 1")
    if not 1 <= args.overview_depth <= 3:
        raise RepoTreeError("overview depth must be between 1 and 3")
    if not 1 <= args.slice_depth <= 6:
        raise RepoTreeError("slice depth must be between 1 and 6")
    if args.max_lines < 20:
        raise RepoTreeError("max lines must be at least 20")


def status_line(action: str, decision: DriftDecision, tool: str | None = None) -> str:
    parts = [
        f"repo-tree: {action}",
        f"score={decision.score}",
        f"threshold={decision.threshold}",
    ]
    if tool is not None:
        parts.append(f"tool={tool}")
    return " ".join(parts)


def execute(args: argparse.Namespace) -> int:
    validate_args(args)
    weights = parse_weight_overrides(args.weight)
    root = resolve_repo_root(args.repo)
    architecture_dir, output_path, cache_path = resolve_architecture_paths(root)
    state = read_git_state(root)
    files = list_repository_files(root)
    slices = detect_ecosystems(files)
    markers = ecosystem_marker_keys(slices)
    directories = repository_directories(files)
    raw_tree = build_raw_architecture_tree(
        directories,
        slices,
        args.overview_depth,
        args.slice_depth,
    )
    raw_tree_hash = sha256_text(raw_tree)
    cache = load_cache(cache_path)
    changes = classify_commits(root, cache, state)
    decision = compute_drift(
        cache,
        state,
        changes,
        raw_tree_hash,
        markers,
        weights,
        args.threshold,
        output_path.is_file(),
        args.force,
    )

    if not decision.regenerate:
        print(status_line("no significant architectural drift", decision))
        return 0
    if args.dry_run:
        print(status_line("would regenerate", decision))
        return 0

    create_architecture_directory(architecture_dir)
    architecture_dir, output_path, cache_path = resolve_architecture_paths(root)
    renderer = TreeRenderer(args.renderer, root)
    overview_tree, overview_renderer = renderer.render(
        PurePosixPath("."),
        args.overview_depth,
        args.max_lines,
    )
    used_renderers = {overview_renderer}
    slice_trees: dict[tuple[str, str], str] = {}
    for item in slices:
        for slice_root in item.roots:
            rendered, used = renderer.render(
                slice_root, args.slice_depth, args.max_lines
            )
            used_renderers.add(used)
            slice_trees[(item.spec.name, slice_root.as_posix())] = rendered
    renderer_name = ",".join(sorted(used_renderers))

    markdown = render_markdown(
        state,
        decision,
        renderer_name,
        overview_tree,
        slices,
        slice_trees,
        directories,
        args.overview_depth,
        args.slice_depth,
    )
    cache_text = cache_document(
        state,
        raw_tree_hash,
        markers,
        renderer_name,
        args.threshold,
        weights,
    )
    atomic_write_text(output_path, markdown)
    atomic_write_text(cache_path, cache_text)
    print(status_line("regenerated", decision, renderer_name))
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    try:
        args = parser.parse_args(argv)
        return execute(args)
    except (BrokenPipeError, KeyboardInterrupt, RepoTreeError) as error:
        if isinstance(error, BrokenPipeError):
            return 0
        if isinstance(error, KeyboardInterrupt):
            print("repo-tree: error: interrupted", file=sys.stderr)
            return 130
        print(f"repo-tree: error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
