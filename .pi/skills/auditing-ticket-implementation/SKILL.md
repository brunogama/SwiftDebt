---
name: auditing-ticket-implementation
description: Use when deciding whether a diff, branch, pull request, or changed file set fully satisfies a ticket, issue, specification, acceptance criteria, or implementation brief before merge or closure.
---

# Auditing Ticket Implementation

## Overview

Trace every ticket requirement to concrete implementation evidence. The audit is complete only when each atomic requirement has an explicit status, an evidence-backed explanation, and an actionable gap when coverage is incomplete.

## Required Inputs

Obtain both:

1. The ticket or specification, including title, description, acceptance criteria, linked context, and relevant comments.
2. The exact change artifact to evaluate, such as a diff, pull request, branch comparison, or changed files.

If either input is unavailable or the target ticket/change set is ambiguous, request it rather than guessing. Repository code outside the diff may confirm an implementation, but it does not prove that an unspecified change set introduced the behavior.

## Audit Workflow

1. Establish the ticket and change-set boundaries.
2. Convert the ticket into numbered atomic requirements:
   - List explicit acceptance criteria first.
   - Split compound criteria when their parts can pass or fail independently.
   - Add behavior implied by the description, edge cases, linked context, or comments and label each `(inferred)`.
3. Inspect the complete change set, then only the surrounding code, configuration, migrations, and tests needed to verify coverage.
4. Map each requirement to direct evidence: file path plus symbol, line, diff hunk, test, or observable behavior.
5. Assign exactly one status:

| Status | Meaning |
| --- | --- |
| Fully Implemented | Direct evidence covers the complete requirement, including required edge cases. |
| Partially Implemented | Some independently useful part exists, but a required behavior or integration is absent. |
| Missing | No implementation evidence exists, or the implementation contradicts the requirement. |
| Cannot Determine | Available evidence cannot establish the behavior; state the exact artifact or runtime proof needed. |

1. For every status other than Fully Implemented, state the smallest concrete remaining action. Do not replace a precise gap with general advice.
2. Identify changed code, dependencies, configuration, or migrations that map to no ticket requirement. Separately identify behavior that contradicts the specification.
3. For each genuinely ambiguous requirement, compare at least two plausible interpretations. State which interpretation the implementation satisfies and let that comparison determine the status. Keep this conclusion in the relevant checklist item or incomplete-item detail. Do not invent ambiguity where the ticket is clear.
4. Choose the verdict:
   - `Fully Implements Ticket` only when every requirement is Fully Implemented.
   - `Partially Implements Ticket` when substantive implementation exists but any requirement is Partial, Missing, or Cannot Determine.
   - `Does Not Implement Ticket` when the core objective is absent or the changes provide no substantive required behavior.

## Evidence Rules

- Cite only paths, symbols, lines, and behavior actually inspected.
- Treat tests as evidence of exercised behavior, not proof of untested production integration.
- Mark absent evidence as Cannot Determine unless the searched change boundary supports a defensible Missing finding.
- Evaluate requirement coverage only. Do not add style, performance, or architecture commentary unless the ticket requires it.
- Do not expose private chain-of-thought. Report concise evidence and conclusions.

## Output Contract

Return only the evaluation, using these sections in this order:

```markdown
## Requirement Checklist

1. **<atomic requirement>** - **<status>**: <evidence with path/symbol, or precise gap>. <ambiguity comparison when applicable>

## Missing/Incomplete Items

- <actionable work for every Partially Implemented, Missing, or Cannot Determine item; for Cannot Determine, name the evidence needed>

## Out-of-Scope or Contradictory Changes

- <unrelated or contradictory change and why it does not map to the ticket>

## Final Verdict

**<Fully Implements Ticket | Partially Implements Ticket | Does Not Implement Ticket>** - <one-line justification>.
```

Omit `## Out-of-Scope or Contradictory Changes` when there are none. If every requirement is fully implemented, write `- None.` under Missing/Incomplete Items. Never add a preamble, instruction restatement, generic code summary, or closing remarks.

## Common Mistakes

- Treating one compound acceptance criterion as one pass/fail item.
- Crediting an endpoint when the ticket requires a user-accessible UI flow.
- Calling a requirement Missing when the provided diff is too narrow to decide.
- Listing a gap without the exact implementation or evidence needed.
- Declaring full coverage while any inferred requirement remains unresolved.
- Mentioning unrelated quality concerns instead of ticket scope creep.
