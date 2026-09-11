# Issue tracker

## Source of truth

Tickets are tracked as local Markdown files in this repository, not in GitHub Issues.

- Active execution tickets live under `.scratch/tickets/`.
- Each ticket is one Markdown file named with a stable, sortable id, for example `01-fidelity-layer.md`.
- GitHub issue URLs may be copied into a ticket for provenance, but the local Markdown file is the source of truth once created.
- Do not update GitHub issue state as part of normal implementation work unless the user explicitly asks for it.

## Ticket format

Use this structure for new tickets:

```markdown
# <ticket id and title>

Blocked by: none

## Context

<why this ticket exists>

## Acceptance criteria

- [ ] <observable criterion>
- [ ] <observable criterion>

## Notes

<links, prior GitHub issue references, constraints, or evidence>
```

## Blocking and waves

`Blocked by:` controls local-ticket-loop wave scheduling.

- Use `Blocked by: none` when a ticket has no prerequisite.
- Use full ticket ids or unambiguous numeric prefixes, for example `Blocked by: 01, 03-search`.
- The loop treats a ticket as ready when every blocker is complete at the campaign baseline.

## Implementation workflow

- Run `scripts/local-ticket-loop/loop.sh <ticket-id>` or `scripts/local-ticket-loop/loop-claude.sh <ticket-id>` for one ticket.
- Run `scripts/local-ticket-loop/proposed-loop.sh --plan` to inspect dependency waves.
- Run `scripts/local-ticket-loop/proposed-loop.sh --run` to execute dependency-gated waves.
- The wave orchestrator defaults to `feat/debtmap` for both `BASE_REVISION` and `MERGE_BACK_BRANCH`.

## Migrating existing GitHub tickets

When a GitHub issue should become implementation work:

1. Create a local Markdown ticket under `.scratch/tickets/`.
2. Copy the GitHub title, requirement summary, and acceptance criteria into the local ticket.
3. Add the GitHub issue URL or number under `## Notes`.
4. Treat the local ticket as canonical after that point.

Do not rely on GitHub labels, assignees, or issue state for local agent scheduling.
