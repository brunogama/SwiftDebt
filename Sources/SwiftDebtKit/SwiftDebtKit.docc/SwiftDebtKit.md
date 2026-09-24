# ``SwiftDebtKit``

Analyze, rank, report, visualize, and enforce Swift technical debt with deterministic evidence.

---

## Overview

SwiftDebt provides an in-memory library API, a standalone `swift-debt` executable, and SwiftPM command and build plugins. Choose the integration that matches when you want analysis to run:

- Use ``Analyzer`` when a Swift tool already owns source text in memory.
- Use the standalone CLI for repositories, scripts, and non-SwiftPM projects.
- Use `swift package swift-debt` for on-demand analysis of exact SwiftPM target source lists.
- Attach `SwiftDebtBuildPlugin` for target-local diagnostics on every build.

All routes share the same analysis engine and deterministic report formats. Read <doc:CIEnforcement> before turning findings into a required policy gate.

The built-in <doc:CodeSmells> rules report concrete syntax signals and suggest Swift-specific changes. Their detections are advisory unless `--fail-on-violation` is enabled.

### Code Smells

- <doc:CodeSmells>
- <doc:LongFunction>
- <doc:LongParameterList>
- <doc:GlobalData>
- <doc:LargeClass>

---

## Topics

### Tutorials

- <doc:StandaloneCLI>
- <doc:LibraryAPI>
- <doc:CommandPlugin>
- <doc:BuildPlugin>
- <doc:CIEnforcement>

### Analysis API

- ``Analyzer``
- ``AnalysisService``
- ``AnalysisRequest``
- ``AnalysisRunResult``
