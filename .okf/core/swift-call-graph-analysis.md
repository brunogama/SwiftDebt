---
type: Static Analysis Component
title: Swift call graph and coupling risk analysis
description: SCMACore builds deterministic Swift dependency graphs with syntax-level type references, calls, module dependencies, coupling risks, and explicit confidence notes.
resource: Sources/SCMACore/DependencyGraphBuilder.swift
tags: [swift, dependency-graph, call-graph, coupling, scmacore]
timestamp: 2026-09-13T00:00:00Z
---

# Overview

`DependencyGraphBuilder` builds a `SwiftDependencyGraph` from valid parsed sources after sorting inputs by path. It emits module, type, and callable nodes, then derives module dependency, type reference, and call edges before computing coupling risks, dependency contexts, statistics, and DOT output.

# Resolution model

Type references are resolved against in-input declarations using lexical parent lookup, same-module lookup, qualified names, imported modules, and same-name fallback. Edges can be `resolvedSyntax`, `ambiguousSyntax`, or `unresolvedSyntax`.

Call edges are resolved by matching syntax call facts to in-input callables by name and argument labels, with special handling for `self.`, `Self.`, member-looking calls, owner methods, and module-level functions. Ambiguous overload matches keep sorted target candidates rather than claiming a target.

# Confidence notes

Resolved type references, calls, and module dependencies state that the result is SwiftSyntax-only and not compiler semantic proof. Ambiguous and unresolved references state that no compiler binding is claimed. Ambiguous overload calls also state that overload binding requires the compiler.

# Verification coverage

`AnalyzerTests` exercises cross-file function resolution, cross-module type references through imports, module dependency inference, explicit SwiftSyntax-only notes, ambiguous overload notes, unresolved call reporting, deterministic graph equality for shuffled inputs with parallel jobs, and stable rendered report output between parallel and sequential analysis.

# Citations

[1] [DependencyGraphBuilder.swift](../../Sources/SCMACore/DependencyGraphBuilder.swift)
[2] [AnalyzerTests.swift](../../Tests/SCMAKitTests/AnalyzerTests.swift)
