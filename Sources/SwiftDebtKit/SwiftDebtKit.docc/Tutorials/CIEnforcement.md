# Enforce a Debt Policy in CI

Turn explicit thresholds into a deterministic CI gate while preserving SwiftDebt's distinct failure statuses.

## Commit a policy

Place `.swift-debt.json` in the package root so local and CI analysis use the same options:

```json
{
  "typeScope": "nominals",
  "scoring": "none",
  "thresholds": { "CCF": 15, "NOPF": 6 },
  "failOnViolation": true
}
```

These values are example repository policy, not claims from the SCMA paper.

## Run the command plugin in GitHub Actions

The package manifest supplies the SwiftDebt dependency and its release version. A minimal enforcement step is:

```yaml
name: SwiftDebt policy

on:
  pull_request:

permissions:
  contents: read

jobs:
  analyze:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
      - run: swift package resolve
      - name: Enforce metric thresholds and rule detections
        run: |
          swift package swift-debt \
            --format text \
            --fail-on-violation
```

Status `0` means analysis completed without an enabled gate failure. Status `1` means analysis completed and violated an opted-in threshold or produced a rule detection. Status `2` means input, configuration, or analysis was invalid or incomplete. SwiftPM can wrap these in its own nonzero plugin status, so use the report to distinguish the cause. Use text output for the full rule explanation and DocC article link. Other formats retain their existing schema while the opted-in rule gate still applies.

For ranked debt, run `swift package swift-debt debt validate --max-score SCORE` and provide `--debt-reference-time` when Git-history evidence participates in the score. The explicit time keeps repeat runs deterministic.
