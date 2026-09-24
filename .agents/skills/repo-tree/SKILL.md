---
name: repo-tree
description: Use when a Git repository needs a generated or refreshed docs/architecture/repo-tree.md, a summarized multi-language architecture map, or cached architecture-drift detection.
compatibility: Requires Git and uv with Python 3.11 or newer. Uses eza or tree when available and includes a pathlib fallback.
metadata:
  version: "1.0.0"
---

# Repository Architecture Tree

Maintain a deterministic, depth-limited architecture view instead of a full repository file dump. Preserve the previous document when the accumulated drift score stays below the configured threshold.

## When to use

- Use this skill to create, refresh, verify, or explain `docs/architecture/repo-tree.md`.
- Use this skill for polyglot repositories, monorepos, ecosystem discovery, architecture drift, and cached tree generation.
- Choose `repository-architecture` when the request requires a broader C4, dependency, data-flow, or interactive architecture report.

## Procedure

1. **RESOLVE_ROOT:** Run `git rev-parse --show-toplevel` and use the returned directory as the repository root.
2. **RESOLVE_SCRIPT:** Resolve `scripts/repo_tree.py` relative to this `SKILL.md` and keep the repository root as the script working target.
3. **DETECT_RENDERER:** Invoke the script with `--renderer auto`; let it try `eza --tree`, then `tree`, then the pathlib walker.
4. **DETECT_ECOSYSTEMS:** Let the script scan tracked and unignored files for ecosystem markers and sort ecosystem sections alphabetically.
5. **COMPUTE_DRIFT:** Let the script compare Git history, Conventional Commit classifications, the canonical raw tree hash, branch state, and ecosystem markers with the cache.
6. **DECIDE:** Accept a skip when the score stays below the threshold and the output and cache remain valid; use `--force` for an explicit refresh.
7. **RENDER:** On regeneration, let the script render the depth-limited overview and one focused subtree plus layout description per detected ecosystem.
8. **WRITE:** Let the script atomically replace the Markdown document and cache only after complete rendering succeeds.
9. **VERIFY:** Confirm the command exits successfully and inspect both generated files when regeneration occurs.
10. **REPORT:** Relay either `regenerated` or `no significant architectural drift` with the score, threshold, renderer, and output path.

## Invocation

```bash
repo_root="$(git rev-parse --show-toplevel)"
uv run <resolved-skill-directory>/scripts/repo_tree.py --repo "$repo_root"
```

Use a dry run to inspect the decision without writing files:

```bash
uv run <resolved-skill-directory>/scripts/repo_tree.py --repo "$repo_root" --dry-run
```

Use an explicit refresh when the human requests one:

```bash
uv run <resolved-skill-directory>/scripts/repo_tree.py --repo "$repo_root" --force
```

## Drift score contract

Use threshold `8` unless repository policy supplies another value.

| Signal | Weight | Cap |
| --- | ---: | ---: |
| HEAD SHA changed | 1 | 1 |
| Branch changed | 3 | 1 |
| Commit since baseline | 1 | 8 |
| `feat:` or `feat(scope):` commit | 6 | 3 |
| `BREAKING CHANGE:` body or `type!:` / `type(scope)!:` subject | 12 | 2 |
| Canonical raw tree hash changed | 8 | 1 |
| Ecosystem marker set changed | 15 | 1 |
| Cached history diverged | 8 | 1 |

Compute:

```text
score =
  1 * head_changed +
  3 * branch_changed +
  1 * min(commit_count, 8) +
  6 * min(feat_count, 3) +
  12 * min(breaking_count, 2) +
  8 * raw_tree_changed +
  15 * ecosystem_markers_changed +
  8 * history_diverged
```

Regenerate when `score >= threshold`, the cache is missing or invalid, the Markdown output is missing, or `--force` is present. Preserve both file contents and modification times on a below-threshold skip so low-signal changes continue accumulating from the last generation baseline.

Tune the threshold or one weight for a repository policy:

```bash
uv run <resolved-skill-directory>/scripts/repo_tree.py \
  --repo "$repo_root" \
  --threshold 10 \
  --weight feat_commit=5 \
  --weight raw_tree_changed=10
```

## Cache contract

Write `docs/architecture/.repo-tree-cache.json` with these stable fields:

- `schema_version`
- `last_generated_commit`
- `branch`
- `generated_at_utc`
- `raw_tree_hash`
- `commit_count_baseline`
- `ecosystem_markers`
- `renderer`
- `threshold`
- `weights`

Treat the raw tree hash as the SHA-256 of the canonical summarized directory trees plus every detected ecosystem marker path. Store every top-level marker in each detected slice under `ecosystem_markers`, and keep the cache unchanged on a skip so commit and feature counts remain cumulative.

## Output contract

Write `docs/architecture/repo-tree.md` with this order:

1. Title.
2. Commit, branch, source date, renderer, and drift metadata.
3. Repository overview tree at depth 3 or less.
4. Alphabetically sorted `##` ecosystem sections with detected markers, a concise layout description, and focused subtree.
5. Change summary with commit, feature, breaking, other, structural, marker, branch, history, score, threshold, and decision values.

Render directories only and list marker files in prose so the result remains an architecture summary. Use the single `IGNORE_PATTERNS` array in the script for every renderer, hash, and detector.

## Verification commands

```bash
uv run <resolved-skill-directory>/scripts/repo_tree.py --version
uv run <resolved-skill-directory>/scripts/repo_tree.py --repo "$repo_root" --renderer python --force
uv run <resolved-skill-directory>/scripts/repo_tree.py --repo "$repo_root" --renderer python
```

Confirm the first generation reports `regenerated` and the unchanged second invocation reports `no significant architectural drift`. Review `examples/multi-language-repo-tree.md` for the complete deterministic output shape.

## Installation and invocation

```bash
npx skills add <owner>/<skills-repository> --skill repo-tree
# Trigger with: /repo-tree, /skill:repo-tree, or "Refresh the repository architecture tree."
uv run <installed-skill-directory>/scripts/repo_tree.py --repo "$(git rev-parse --show-toplevel)"
```
