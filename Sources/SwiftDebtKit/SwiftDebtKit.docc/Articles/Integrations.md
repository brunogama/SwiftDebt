# Choose an Integration

SwiftDebt has four ways to start analysis. They share the same metric engine, but each chooses source files differently.

## Standalone executable

Use `swift-debt analyze` for a directory or an explicit source manifest. A directory scan labels the input as one virtual `Workspace` module. The executable works outside SwiftPM projects and can write text, JSON, CSV, HTML, and diagnostic reports.

Use `swift-debt debt analyze` for ranked debt output and `swift-debt debt validate` for a maximum-score gate. Start with <doc:FirstAnalysis> or <doc:RankedDebt>.

---

## Command plugin

Use `swift package swift-debt` when the root Swift package owns the source. The command plugin selects SwiftPM targets and preserves their module names. It can combine several selected targets in one analysis, so cross-target syntactic coupling and duplicate observations remain visible. It does not select package dependencies by default. See <doc:CommandPlugin>.

---

## Build plugin

Attach `SwiftDebtBuildPlugin` to a SwiftPM target when each build should report target-local diagnostics. The plugin receives that target's source list and needs a root `.swift-debt.json` file as a declared input. It cannot see coupling or duplicate spans across targets that are not in its invocation. See <doc:BuildPlugin>.

---

## Library API

Use `Analyzer` for source text already in memory. Use `AnalysisService` for the same filesystem, configuration, and output behavior as the executable. The library product contains `SwiftDebtKit` and `SwiftDebtCore`; the generated references cover both modules. See <doc:LibraryAPI> and <doc:ProgrammaticGate>.

All integrations parse Swift syntax without type checking or macro expansion. Choose the source-selection route that matches the question you want the report to answer.
