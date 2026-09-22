# Domain docs

This is a single-context repository.

## Glossary source

- `CONTEXT.md` is the project glossary when it exists.
- Use the terms in `CONTEXT.md` exactly as defined there.
- If `CONTEXT.md` is missing and a task needs durable domain language, create or update it as part of that task.

## Decisions

- Architecture and process decisions belong under `docs/adr/` when they need to outlive a single ticket.
- ADRs are settled once written; implement them rather than relitigating them during ticket work.

## Package context

- Project name: `SwiftDebt`.
- Swift package: `SwiftDebt`.
- Purpose: analyze, rank, report, visualize, and enforce Swift technical debt
  with deterministic, auditable evidence.

## Agent behavior

- Before changing agent infrastructure, read this file, `docs/agents/issue-tracker.md`, and `docs/agents/triage-labels.md`.
- Prefer executable commands and local repository evidence over prose guesses.
