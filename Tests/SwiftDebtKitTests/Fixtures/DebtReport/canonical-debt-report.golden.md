# SwiftDebt debt report

Schema version: 2
Ranked items: 2
Unavailable evidence: 1

## Critical priority

### App.Beta.run()

- ID: `callable:Beta.run`
- Location: Sources/Beta.swift:12:5
- Score: 91.2
- Category: swift
- Evidence: 1 available, 1 unavailable
- Why: Nested async work combines complexity and missing coverage.
- Action: Extract smaller operations and add coverage.
- Missing evidence:
  - coverage.lcov `callable:Beta.run:coverage`: LCOV file missing

## High priority

### App.Alpha.help()

- ID: `callable:Alpha.help`
- Location: Sources/Alpha.swift:3:1
- Score: 72.5
- Category: swift
- Evidence: 1 available, 0 unavailable
- Why: High fan-in concentrates change risk.
- Action: Reduce fan-in before adding features.
