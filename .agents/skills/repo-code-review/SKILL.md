---
name: repo-code-review
description: Use when reviewing a source diff, pull request, repository file, architecture document, or ADR and the review needs repository-aware evidence, risks, and actionable findings.
---

# Repository-Aware Code Review

Review the supplied artifact against the repository evidence that can confirm or challenge it. Gather only context that could change a finding. Keep source edits separate from review work.

## When to Activate

Activate for code review, PR review, architecture review, design review, ADR review, or a request to assess repository risks before approval.

Do not activate for a generic explanation with no repository artifact. Use `code-review` when running CodeRabbit on code changes. Use `codebase-memory` for architecture exploration without a review verdict.

For a manual repository review, use this skill's **Output Contract**. Do not replace it with another review skill's report format.

## Suggested Context

Start with the artifact and select only the relevant evidence.

| Artifact | Suggested repository context |
| --- | --- |
| Source file or diff | Changed files, direct callers and implementations, input/output contracts, affected tests, build and lint configuration, and dependency or compatibility constraints. |
| Pull request | PR description, full diff, changed-file tests, surrounding interfaces, migration or feature-flag changes, and current working-tree status. |
| Architecture document or ADR | Referenced source files, related ADRs, API schemas, persistence migrations, deployment configuration, security controls, operational runbooks, and test evidence. |

Ask for unavailable context only when it prevents a decision. Otherwise state it as an assumption or unknown.

### Context Request Template

```text
Artifact: <path, diff, PR, RFC, or ADR>
Review goal: <merge, security, architecture approval, incident follow-up>
Scope: <components and environments in scope>
Constraints: <compatibility, privacy, availability, compliance, delivery date>
Evidence available: <tests, dashboards, runbooks, deployment config, traces>
Known unknowns: <production topology, traffic volume, credentials, third parties>
```

## Review Workflow

1. Identify the artifact type and its approval decision.
2. Build a short checklist from applicable dimensions only.
   - Code: correctness, security, failure paths, concurrency, resource usage, compatibility, and tests.
   - Architecture: requirements, trust boundaries, reliability, data consistency, observability, rollout and rollback, capacity, cost, and contract stability.
3. Verify each potential finding against the artifact and selected repository context. Cite a real path, section, symbol, or diff hunk. Do not infer absent details as facts.
4. Report only concrete, decision-relevant findings. State the failure mode when a risk needs context.
5. Separate assumptions and unknowns from findings, then finish with severity-ordered actions.

## Severity Guide

| Severity | Use when | Required recommendation |
| --- | --- | --- |
| Critical | Exploitable security issue, likely data loss, unsafe enforcement, or outage blocker | Block approval and give the smallest safe corrective action. |
| Major | Significant correctness, reliability, security, or compatibility risk | Fix before approval or document an explicit, time-bounded exception. |
| Minor | Maintainability, testability, clarity, or operational improvement | Give a bounded improvement. |
| Note | Useful observation or unresolved question without a demonstrated defect | State the evidence needed to resolve it. |

## Output Contract

```markdown
## Artifact Type

## Tailored Checklist
- Applicable review dimensions only

## <Relevant Category>
- [Major] Location: finding. Recommendation. If unaddressed: failure mode.

## Assumptions and Unknowns
- [Note] ...

## Prioritized Actions
1. [Severity] Action
```

## Common Mistakes

1. **Reviewing the whole repository by default**: inspect only evidence that can validate the supplied artifact or change its risk assessment.
2. **Treating missing context as a defect**: label it as an assumption or unknown unless the document claims the missing property.
3. **Listing generic checklists as findings**: include a dimension only when it applies and report it only with concrete evidence.
4. **Overstating severity**: base severity on the plausible production failure mode, not on code style or implementation cost.
