# Agent instructions

## Project

- Name: SwiftDebt
- Purpose: A Swift package for deterministic technical-debt analysis, ranking,
  reporting, visualization, and enforcement with auditable evidence.
- Package: `SwiftDebt` (SwiftPM, root of this repository)
- Tags: swift, technical-debt, static-analysis, reporting, plugins
- Do not edit formatting files, `.swift-format`, or `.swiftlint.yml`.

## Required startup

1. Read `CLAUDE.md` when the active harness loads it.
2. Read `CONTEXT.md` when it exists. It is the glossary; use its terms with
   exactly the meanings recorded there.
3. Read the decisions in `docs/adr/` when the directory exists. They are
   settled - implement them rather than relitigating them.
4. Consult `atomic-final-spec.md` when it exists for the authoritative contract
   of whatever you are about to build.
5. Read `docs/agents/domain.md`, `docs/agents/issue-tracker.md`, and
   `docs/agents/triage-labels.md` before changing agent infrastructure.

## Implementation

- Swift 6 language mode, tools version 6.2, complete concurrency checking.
- Deployment targets: macOS 13, iOS and iPadOS 16, tvOS 16, watchOS 9,
  and visionOS 1.
- Tests use Swift Testing (`@Suite`, `@Test`, `#expect`, `#require`), not
  XCTest. See `rules/testing.md`.
- Targets are declared in `Package.swift` as their source directories land. A
  target whose directory does not exist yet cannot be declared, so add the
  declaration in the ticket that creates the sources.
- Add dependencies only for an explicit product need and document the
  manifest-level justification.

## Work tracking

Implementation work is tracked in GitHub Issues for `brunogama/SwiftDebt`,
described in `docs/agents/issue-tracker.md`. Record blockers and acceptance
criteria in the issue body. Use `gh issue` for tracker operations.

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
work. Historical local ticket branches are not part of the active workflow.

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
- Prefer executable commands over prose descriptions.
- Establish positive defaults ("always add tests") rather than bans.
- Treat stale rules as technical debt; update modules when conventions change.
