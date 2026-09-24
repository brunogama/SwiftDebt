# ADR 0001: Keep compiler evidence in a versioned sidecar

---

## Status

Accepted.

---

## Context

SwiftDebt has two released syntax-only JSON contracts. `AnalysisReport` schema 2 carries metrics and source-derived graph estimates. `DebtReport` schema 2 carries ranked debt evidence and is consumed by comparison, dashboard, fixture, and automation code that requires its exact current schema.

Compiler-backed analysis depends on the exact compiler, toolchain, build configuration, and source snapshot. A type-checking failure, unsupported toolchain, missing source identity, or ambiguous binding must remain distinct from a measured zero or one resolved edge.

Issue #32 establishes the contract before issues #33 and #34 add compiler providers or semantic facts.

---

## Decision

Compiler evidence uses a standalone `CompilerEvidenceReport` with `reportKind` `swiftdebt-compiler-evidence` and schema version 1. The transport-neutral public types live in `SwiftDebtCore`.

The report records:

- analysis mode and SwiftDebt generator version;
- compiler name, version, build identifier, and toolchain identifier;
- build configuration, module, target, SDK, Swift language version, active compilation conditions, and a configuration fingerprint;
- a validated source-content digest plus a version-control revision when one exists; and
- explicit availability for type checking, conditional compilation, macro expansion, name binding, and dispatch targets.

Availability is a tagged state. `available` has no issue. `unavailable` and `ambiguous` require a nonblank machine-readable issue code and message. Neither state has a numeric value or selected target. Future fact schemas may represent a proven empty result only under `available`; they must not derive it from `unavailable` or `ambiguous`.

Source identity is also tagged. A Git checkout records revision, working-tree state, and content digest. A source archive records only its content digest. If neither is known, the report records an unavailable source identity. SHA-256 values are validated on construction and decode.

The existing `AnalysisReport` and `DebtReport` types, coding keys, schema versions, renderers, and golden files do not gain a compiler-evidence field. Syntax-only output therefore keeps its current byte shape and meaning.

---

## Compiler integration boundary

A future provider belongs in `SwiftDebtKit`, where process execution and toolchain-specific normalization already fit the environment-facing layer. Raw compiler output, process types, command arguments, and compiler dump nodes must not cross into `SwiftDebtCore` or the public sidecar.

A provider may mark a capability available only when all of these are true:

1. The compiler process exits with status 0.
2. The toolchain has a supported, version-scoped adapter.
3. The adapter reads a documented stable machine-readable source.
4. Normalization completes without losing ambiguity or provenance.

Until such an adapter exists, the capability remains unavailable. Issue #32 does not add a provider, command-line option, semantic fact, metric, score, or graph consumer.

---

## Swift 6.4 probe

Run the checked-in fixture package probes with:

```sh
scripts/probe_compiler_evidence.sh .scratch/compiler-evidence-probe
```

The 2026-09-24 run used:

```text
swift-driver version: 1.168.5 Apple Swift version 6.4 (swiftlang-6.4.0.27.1 clang-2100.3.27.1)
Target: arm64-apple-macosx27.2.0
```

Each source was type checked with `-module-name main -dump-ast -dump-ast-format json`.

| Probe | Exit | JSON | Observation |
| --- | ---: | --- | --- |
| Type error | 1 | Valid | The payload still contained AST data even though `String` could not initialize `Int`. Parse success is not type-check success. |
| Default conditional build | 0 | Valid | The active string branch bound `select(String)` with USR `s:4main6selectySiSSF`. |
| `-D FEATURE_A` | 0 | Valid | The active integer branch bound `select(Int)` with USR `s:4main6selectyS2iF`. |
| `@Observable` | 0 | Valid | Generated buffers contained `$defer`, `_value`, `_$observationRegistrar`, `access`, `withMutation`, and `shouldNotifyObservers`. |

`swiftc -help-hidden` describes `-dump-ast-format` with this warning:

```text
no format is guaranteed stable across different compiler versions
```

These are reproducible probe observations. The AST JSON is rejected as a production semantic boundary, so the report must not claim those bindings or generated declarations as usable compiler evidence.

---

## Consequences

- Syntax-only consumers continue reading the same schema-2 artifacts.
- Compiler-backed consumers opt into a second artifact with an independent migration path.
- Consumers reject sidecars with an unknown schema version before interpreting their fields.
- A new compiler version fails closed until its stable adapter is supported.
- Non-Git inputs can be identified honestly without inventing a revision.
- Issues #33 and #34 can add normalized facts after selecting and testing a stable provider.

---

## Rejected alternatives

Adding optional compiler fields to either schema-2 report was rejected because it broadens a released wire contract and duplicates integration policy.

Publishing raw AST JSON was rejected because the compiler explicitly disclaims format stability, and a failed type check can still emit parseable JSON.

Treating absent evidence as zero, or choosing one candidate from ambiguous evidence, was rejected because both create false semantic claims.
