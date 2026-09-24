---
name: bmad-build-auto
description: 'One iteration of an unattended development loop. Use when invoked by name.'
---
```bash
PROJECT_ROOT=$(pwd)
SKILL_ROOT=.agents/skills/bmad-build-auto/SKILL.md
```

{project-root} is the absolute path to the project root.
{skill-root} is the absolute path to this skill's directory.

Run the following command exactly once without changing the current working directory. Replace `{project-root}` with the absolute path to the project root and `{skill-root}` with the absolute path to this skill's directory:

```bash
uv run --no-cache "{project-root}/_bmad/scripts/render_skill.py" --project-root "{project-root}" --skill "{skill-root}"
```

- On success, read and follow the one absolute `workflow.md` instruction printed to stdout.
- On failure (including `uv` being unavailable), report the command output and HALT. Do not run any workflow source directly.
