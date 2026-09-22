---
type: Test Coverage
title: Swift structural debt evidence assertions
description: Swift Testing coverage asserts structural debt evidence locations, raw values, and nested callable metrics.
resource: Tests/SwiftDebtKitTests/AnalyzerTests.swift
tags: [swift-testing, debt-analysis, structural-evidence]
timestamp: 2026-09-13T00:00:00Z
---

# Overview

`AnalyzerTests` verifies that structural debt evidence emitted for a Swift fixture has file, line, and column locations, non-empty raw values, and non-empty notes. The same test still checks for `swift.cognitive-complexity` with `rawValue == "value=6"`, `swift.nesting-depth` with `rawValue == "value=3"`, oversized-type evidence, and non-zero duplicate-lines evidence.

`ParserTests.nestedCallablesHaveSeparateComplexity` verifies that a nested local function and closure are counted separately: the fixture has two functions and one closure, both functions have cyclomatic complexity `2`, cognitive complexity `1`, and maximum nesting depth `1`, and the closure has the same structural metric values.

# Citations

[1] [AnalyzerTests.swift](../../Tests/SwiftDebtKitTests/AnalyzerTests.swift)
[2] [ParserTests.swift](../../Tests/SwiftDebtSyntaxTests/ParserTests.swift)
