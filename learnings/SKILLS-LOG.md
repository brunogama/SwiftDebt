# Skill promotion log

## 2026-10-04: swift-package-bootstrap

- Status: approved and promoted to `~/.agents/skills/swift-package-bootstrap/` by explicit user request.
- Compatibility links: `~/.codex/skills/swift-package-bootstrap` and `~/.claude/skills/swift-package-bootstrap` point to the shared skill.
- Trigger: create or standardize a SwiftPM package using the bundled SwiftSCMA development standard.
- Procedure: inspect the target and preserve its work; review relevant bundled configs, skills, templates, and docs; confirm package shape and platform support; scaffold targets after directories exist; use the test-first workflow for behavior; build and test before claiming verification.
- Bundle: 454 tracked reference assets in the skill's `references/swiftscma/` tree. No SwiftPM package manifest, source target, local settings, or consumer examples are included.
- Evaluation: platform-clarification and portability cases passed. Existing-package behavior and full-asset-import cases remain inconclusive. Results and limitations are recorded in `~/.agents/skills/swift-package-bootstrap/evals/results.md`.
- Superseded on 2026-10-04 by `swift-repo-bootstrapper`. The original is preserved at `~/.agents/skill-archive/2026-10-04-swift-package-bootstrap/`; its Claude and Codex links were removed.

---

## 2026-10-04: swift-repo-bootstrapper

- Status: explicitly approved and promoted to `~/.agents/skills/swift-repo-bootstrapper/` from the staged candidate.
- Compatibility links: `~/.codex/skills/swift-repo-bootstrapper` and `~/.claude/skills/swift-repo-bootstrapper` point to the shared skill.
- Relationship: supersedes `swift-package-bootstrap`; the prior skill is archived, not deleted.
- Trigger: explicit request to bootstrap or standardize an existing or new Swift repository, including SwiftPM and Xcode, with selective formatting, lint, hook, and CI references.
- Procedure: classify and preserve the target; select only relevant rules on invocation; confirm blocking platform choices; make the smallest requested scaffold; apply existing test conventions; compare tool diagnostics before and after edits; verify and report actual checks.
- Evaluation: ten behavior cases passed on the amended candidate. The first case 6 holdout failed before correction; a new, untouched Xcode-only formatting holdout passed after the correction. Twenty-one candidate tests, rule QA, Ruff, prek, repository QA, SwiftPM build, and 89 Swift tests passed. Remote GitHub Actions runtime remains unverified. Evidence and the decision trail are in `~/.agents/skills/swift-repo-bootstrapper/evals/`.


---

## 2026-10-05: pstack-evidence-workflow

- Status: explicitly approved and promoted to `.pi/skills/pstack-evidence-workflow/` from the Pi candidate.
- Relationship: new Pi-only workflow skill; composes `show-me-your-work`, `principle-prove-it-works`, and `principle-sequence-verifiable-units` rather than replacing them.
- Trigger: evidence-based, delegated, risky, or reviewer-facing work with at least three meaningful steps.
- Procedure: frame direct acceptance evidence; track units with `pstack_todo`; verify each unit before advancing; inspect delegated artifacts rather than reports; run the real outcome path; keep an honest audit trail when warranted.
- Evaluation: a fresh read-only deduction review passed. It reconstructed a practical workflow, found no necessary patch, and confirmed that the candidate limits process overhead for one-command tasks.
