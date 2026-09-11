---
description: Run deterministic and fresh-agent repository QA
argument-hint: "[scope]"
---

Perform QA for `${ARGUMENTS:-the repository}`.

Run `uv run scripts/qa_repository.py .`, then follow `qa/QA_AGENT.md`. Return its exact rubric structure. Do not modify files during the independent QA pass.
