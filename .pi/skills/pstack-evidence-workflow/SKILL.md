---
name: pstack-evidence-workflow
description: "Run complex coding, research, migration, or review work with a pstack checklist and direct evidence. Use when asked for evidence-based work, an auditable implementation, verified multi-step work, or a proof-backed branch or feature assessment."
disable-model-invocation: true
---

# Pstack evidence workflow

Use this skill only when the work has at least three meaningful steps, a material
risk, delegated work, or a result a reviewer must be able to audit. Do not add
process to a one-command request.

This skill coordinates existing practices; it does not replace project rules,
user authority, `show-me-your-work`, or `principle-prove-it-works`.

## Procedure

1. **Frame a checkable outcome.** State the requested deliverables, boundary,
   acceptance predicate, and the direct artifact or runtime path that will
   prove each material claim. Identify what would count as `PASS`, `ISSUES`, or
   `BLOCKED`; do not treat an intended edit or an agent report as evidence.

2. **Track the work in pstack.** Create or refresh a focused `pstack_todo`
   checklist before starting. Keep one meaningful item active at a time and
   complete it immediately after its acceptance evidence exists. Record a
   blocker as open work instead of marking a partial result complete.

3. **Make units independently verifiable.** Establish a baseline where a
   comparison matters, then change one unit and run its focused check before
   advancing. For code, follow red–green where practical. For research or
   review, retain source citations or inspected artifacts that support each
   conclusion. Use `principle-sequence-verifiable-units` for the unit boundary.

4. **Delegate with evidence contracts.** Assign at most one writer to each
   mutable surface. Give every subagent its exact target, scope, expected
   artifact, acceptance criteria, and evidence required. Inspect the resulting
   diff, source, command output, or rendered behavior yourself; a child report
   is an input, never proof.

5. **Prove the real outcome.** Run the narrowest direct check first, then the
   relevant full gate. Exercise the actual input-to-output or integration path,
   compare against a baseline when behavior must be preserved, and save
   reproducible command output when a reviewer needs it. Apply
   `principle-prove-it-works`; build success alone is not completion.

6. **Leave an honest audit trail.** For long-running, autonomous, or
   reviewer-facing work, route to `show-me-your-work` for its append-only TSV
   trail and independent trail review. Log only real decisions and resolvable
   evidence. Reconcile every pstack item and report exactly what was checked,
   what remains unverified, and why.

## Guardrails

- Do not fabricate a passing result from static inspection, stale output, file
  timestamps, or self-reported subagent completion.
- Do not rerun broad gates when a focused failure explains the next correction.
  Fix the known failure, recheck the unit, then run the full gate once.
- Do not call remote CI, deploy, publish, or change external records unless the
  user authorized that action.
- If direct verification is unavailable, report `BLOCKED` or `UNVERIFIED` with
  the exact missing capability; never downgrade the acceptance predicate.
