# Agent instructions

## Project

- Name: swift-deep-research
- Purpose: A Swift package that answers a research question with an auditable
  chain of evidence. Every factual sentence in an answer traces to an exact
  quotation in a retrieved document, and the cost and duration of a run are
  bounded before it starts.
- Package: `DeepResearch` (SwiftPM, root of this repository)
- Tags: swift, research, evidence, citations, agents
- Do not edit formating filess and `.swift-format`, `.swiftlint.yml`.

## Required startup

1. Read `CLAUDE.md` when the active harness loads it.
2. Read `CONTEXT.md`. It is the glossary; use its terms with exactly the
   meanings recorded there.
3. Read the decisions in `docs/adr/`. They are settled - implement them rather
   than relitigating them.
4. Consult `atomic-final-spec.md` for the authoritative contract of whatever
   you are about to build. It is long; read the sections your work touches.
5. Read `docs/agents/domain.md`, `docs/agents/issue-tracker.md`, and
   `docs/agents/triage-labels.md` before changing agent infrastructure.

## Implementation

- Swift 6.4, tools version 6.0, macOS 14 minimum, complete concurrency
  checking.
- Tests use Swift Testing (`@Suite`, `@Test`, `#expect`, `#require`), not
  XCTest. See `rules/testing.md`.
- Targets are declared in `Package.swift` as their source directories land. A
  target whose directory does not exist yet cannot be declared, so add the
  declaration in the ticket that creates the sources.
- Do not add dependencies that `atomic-final-spec.md` does not call for.

## Work tracking

Implementation work is tracked as local Markdown tickets under
`.scratch/tickets/`, described in `docs/agents/issue-tracker.md`.
Tickets carry their own blocking edges; `scripts/local-ticket-loop/` executes
them and owns their checkboxes. Do not edit a ticket's checkboxes by hand while
a loop is running.

## Skill lifecycle

No skill becomes permanent without:

    Collect -> Induction -> Deduction -> De-dup -> Approval

Never write a new skill directly to an active skill directory. Stage it under
the harness-specific `_candidates/<skill-name>/` directory and wait for
explicit human approval.

## Quality

- Run `swift build --build-tests && swift test` before completion.
- Run `uv run scripts/qa_repository.py .` for agent-infrastructure changes. It
  checks the repository's own tracked files, so build output and vendored
  checkouts are not its subject. Then ask a fresh agent to follow
  `qa/QA_AGENT.md`.
- Never enable or execute an external skill source before reviewing it.
- Do not place credentials, tokens, or private URLs in generated prompts or
  workflows.

## Version control

This repository uses Git as its only repository VCS; there is no Jujutsu
metadata and Jujutsu commands must not be used for repository operations. Use
`main` for released history and `feature/*`, `release/*`, and `hotfix/*` for
work. Branches under `local-ticket-loop/*` are created and owned by the ticket
loop; leave them alone.

## Rules modules

| File | Topic |
|------|-------|
| `rules/general.md` | General working agreements |
| `rules/rule-loading.md` | Dynamic rule-loading protocol |
| `rules/commits.md` | Commit message conventions |
| `rules/testing.md` | Testing standards and commands |
| `rules/mcp-tools-usage.md` | MCP tool usage policy |
| `rules/self_improve.md` | Agent self-improvement loop |

`rules/view.md` and `rules/view-model.md` cover SwiftUI conventions. This
package has no UI layer, so they do not apply to work here.

## Conventions

- Keep each module focused on one topic; split when a file exceeds ~200 lines.
- Exception: `scripts/local-ticket-loop/*.sh` may exceed this line-count guideline when the entrypoint must remain a portable, self-contained Bash 3.2 harness. Keep shared logic in `scripts/local-ticket-loop/shared/` when it is used by multiple entrypoints.
- Prefer executable commands over prose descriptions.
- Establish positive defaults ("always add tests") rather than bans.
- Treat stale rules as technical debt; update modules when conventions change.
