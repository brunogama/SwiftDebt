---
name: delegating-read-only-pi
description: Use when a headless Pi agent needs a fresh nested Pi specialist to apply one specific skill without editing files and return its final answer to the caller.
compatibility: Requires the pi CLI with JSON mode, explicit skill loading, tool allowlists, Bash, and Python 3.
---

# Delegating to Read-Only Headless Pi

Launch one ephemeral nested Pi with one skill and read-only tools. Emit one start marker while returning the important output, the final answer, on stdout.

## Selector argument

Invoke this skill with a selector followed by the task:

```text
/skill:delegating-read-only-pi repo-code-review Review the current diff for correctness issues.
```

Treat the first argument, `repo-code-review`, as an exact lookup key. Treat all remaining text as the child task.

Resolve `reference/skills.csv` relative to this `SKILL.md`. The semicolon-delimited first column contains selector arguments and the second column contains skill paths. The CSV currently exposes `repo-code-review`, `auditing-ticket-implementation`, `repo-tree`, and `okf`; `repo-tree` and `okf` document script invocations (`uv run .../repo_tree.py`, `okf_validate.py`) that the child's `read,grep,find,ls` allowlist cannot execute, so those delegations can only review and report, not run their scripts - report the mismatch instead of widening the allowlist.

1. Find exactly one data row whose first column equals the selector. Do not fuzzy-match or process other rows.
2. Fail clearly when no row or multiple rows match.
3. Resolve the second-column path from the repository root when relative.
4. Append `SKILL.md` when the resolved path names a directory, then verify the file exists.

## Invocation contract

Resolve `scripts/run.sh` relative to this `SKILL.md`, then pass the selector and complete task:

```bash
<resolved-skill-directory>/scripts/run.sh \
  repo-code-review \
  "Review the current diff for correctness issues."
```

The runner performs the exact CSV lookup and launches the child with `read,grep,find,ls,memory_search,memory_health`. It emits one start marker on stderr, reports only exceptional retries or failures afterward, and returns the final child answer on stdout. Nonzero, malformed, incomplete, and empty-output runs fail.

## Required preparation

1. Require a nonempty selector and a nonempty task. For a whole-skill run such as `repo-tree`, derive the task from the target skill's own workflow; explicit callers must always provide both.
2. Resolve one trusted target `SKILL.md` through the CSV's exact first-column match. Never target this skill itself.
3. Inspect the target's `references/` tree and read every task-relevant file plus required relative references named by its `SKILL.md`.
4. Make `task` self-contained. The fresh child cannot infer the outer conversation.
5. Pass the task as one quoted argument to `scripts/run.sh`. Never use `eval`, `sh -c`, or unquoted expansion.

## Flag guarantees

| Flag | Purpose |
| --- | --- |
| `--mode json` | Runs headlessly while emitting lifecycle, tool, and response events. |
| `--no-session` | Prevents persistent child session state. |
| `--no-extensions` | Prevents ambient extensions from adding tools or behavior; the agentmemory extension is re-added explicitly (guarded on presence) so memory recall and health survive. |
| `--no-skills` | Disables ambient skill discovery. |
| `--skill "$skill_path"` | Adds only the selected skill despite `--no-skills`. |
| `--tools read,grep,find,ls,memory_search,memory_health` | Excludes mutation and shell tools from the child; keeps the read-only agentmemory recall and health tools. |

## Boundaries

- This is tool-level enforcement, not an operating-system sandbox. The child can read anything its process permissions allow.
- Project context files remain available. Add `--no-context-files` only when isolation from project instructions is explicitly required and safe.
- A target skill requiring `bash`, mutation tools, browser actions, or side effects is incompatible. Report the mismatch instead of widening the allowlist.
- Never add `bash` for convenience. A shell-capable child is not read-only.

## Common mistakes

1. Processing every CSV row instead of selecting one exact first-column match.
2. Treating the first argument as a path instead of resolving the second column.
3. Omitting `--no-skills` or ignoring the target's `references/` tree.
4. Reimplementing the runner inline and restoring command-substitution buffering.
5. Accepting failed or empty output without outer-agent review.
