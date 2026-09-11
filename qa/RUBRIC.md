# Repository QA Rubric

Return this structure exactly:

## Summary

- Verdict: PASS or FAIL
- Scope reviewed: <paths or repository>

## Deterministic checks

- `uv run scripts/qa_repository.py .`: PASS or FAIL with the relevant output
- Additional commands run: <commands and results, or none>

## Fresh-agent review

- Instruction coverage: PASS or FAIL
- Harness coverage: PASS or FAIL
- Skill wiring: PASS or FAIL
- Safety and secrets: PASS or FAIL
- Findings: numbered list, or `None`

## Recommendation

Merge readiness: PASS or FAIL, with one sentence of rationale.
