# Deterministic Reports

SwiftDebt sorts source paths, entities, evidence, and findings before reporting. Parsing with a different `jobs` value does not change report order. Reports contain no generated wall-clock timestamp or random identifier.

The repeatable unit is a specific source selection and policy, not just a Git commit. Keep the selected files, their module names, analysis options, parser version, and source paths the same when comparing reports. Directory scans use a virtual `Workspace` module; command-plugin runs use SwiftPM target names, so those reports are not interchangeable without accounting for scope.

Git recency needs an explicit `debtReferenceTime`. Use the same timestamp on both sides of a comparison. Coverage evidence needs the same LCOV input and source mapping. If a required source cannot be read or the duplicate-comparison budget is exhausted, SwiftDebt fails rather than turning the missing work into a passing score.

`complete: true` means the selected files were handled under the configured syntax policy. It does not mean the code compiles or that every source in an application was selected. The default policy skips parser-error files with warnings; `strictSyntax` marks the report incomplete. Compare `inputFileCount` and `analyzedFileCount`, then review diagnostics before enforcing a result.

For ranked debt, unavailable optional evidence is recorded in `missingEvidence`. A missing Git or coverage input is not a measured zero. Keep the missing-evidence list with the score when presenting or archiving a ranked report.
