---
name: skill-forge
description: Use when a completed multi-step task, repeated correction, or resolved bug should become a reusable technical procedure. Owns collection, induction, deduction, de-duplication, staging, and approval-gated promotion. Do not use for ordinary project documentation or unverified one-off notes.
tags: [meta, self-improvement, skills, sop]
date: 2026-07-29
---

# Skill Forge

Convert real task evidence into a verified skill candidate without changing active skills before approval.

## Trigger

- A task with three or more non-trivial steps completed.
- The same user correction appeared twice.
- A non-trivial bug was reproduced and resolved.
- The user invoked `forge-skill` for a topic.

## Harness paths

Choose the current harness root once:

| Harness | Active skill root | Candidate root |
| --- | --- | --- |
| Claude | `.claude/skills/` | `.claude/skills/_candidates/` |
| Pi | `.pi/skills/` | `.pi/skills/_candidates/` |
| Codex/shared | `.agents/skills/` | `.agents/skills/_candidates/` |

Call these `<active-skill-root>` and `<candidate-root>` below. Never substitute a different harness's root.

## Pipeline

### 1. Collect

Read the session evidence, diff, task summary, and `learnings/CORRECTIONS.md`. Identify the steps, failures, correction, and observable outcome.

### 2. Induce

Use `templates/skill-template.md` to write an imperative, parameterized procedure. Stage it at `<candidate-root>/<kebab-name>/SKILL.md`.

For a revision to an active skill, copy that skill into `<candidate-root>/<existing-name>/` and edit the candidate copy. Never edit the active copy before approval.

### 3. Deduct

Give only the candidate and its explicit resources to a fresh agent. Ask it to reconstruct the outcome.

- Pass: record evidence and proceed.
- Fail: add the missing instruction and retry, up to two rounds.

### 4. De-duplicate

Compare candidate descriptions against `<active-skill-root>*/SKILL.md`.

- Strong overlap: revise the existing skill through a candidate copy.
- Partial overlap: declare `supersedes` in candidate frontmatter.
- No overlap: keep the new candidate name.

### 5. Request approval

Present the trigger, a five-line procedure summary, deduction evidence, and whether the change is new, revised, or superseding. Wait for explicit human approval.

### 6. Promote

Only after approval:

1. Move the candidate into `<active-skill-root><name>/`.
2. Append the approved promotion to `learnings/SKILLS-LOG.md`.

## Rejection criteria

- No generalizable trigger.
- The candidate duplicates an active skill without revising it.
- Deduction still fails after two rounds.
- The procedure has fewer than three meaningful steps.

## Files

- Reads: session evidence, corrections, active skill descriptions, and the skills log.
- Writes before approval: `<candidate-root>` only.
- Writes after approval: `<active-skill-root>` and `learnings/SKILLS-LOG.md`.
