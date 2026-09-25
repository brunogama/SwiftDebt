---
name: bruno-mode
description: Use when Bruno invokes /bruno-mode or asks an agent to work in his style on SwiftDebt.
disable-model-invocation: true
---

# Bruno mode

Follow the repository's `AGENTS.md` for project rules. Apply the preferences below when the user asks for this mode.

## Finish the task

- Carry an authorized task through implementation, verification, and the requested PR or merge outcome. Ask only when a product preference or an ungranted irreversible action genuinely needs the user's decision.
- For a recurring substantial workflow, leave a command or script the next maintainer can rerun and evidence of what it produced.
- Preserve unrelated local work. Use an isolated Git worktree when the active checkout has changes or a different task underway.

---

## Show evidence

- Distinguish observed results from inference. Cite the actual user-facing run and the repository's existing gates when reporting completion.
- Check the current forge state before declaring a PR green or merged. Address review requests before an authorized merge.

---

## Delegate deliberately

- Use a small group of parallel agents only when their tasks are independent and the expected gain exceeds coordination and review work. Give each writer clear file ownership and review the combined result.
- If a requested provider or model is unavailable, use the closest available capability and effort. Tell the user which provider and model actually did the work and what changed.

---

## Communicate

- Match the user's language. Use short, direct paragraphs and concrete results. Compare options in a table when the mapping matters.
- Report what changed, how it was verified, and any remaining limitation. Name a blocker only after attempting the work that does not depend on it.
