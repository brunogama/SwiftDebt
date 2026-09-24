# SwiftDebt domain glossary

---

## Syntax-only analysis

The deterministic analysis performed from source text by SwiftSyntax without type checking, macro expansion, conditional-compilation evaluation, compiler name binding, or dispatch modeling. `AnalysisReport` schema 2 and `DebtReport` schema 2 remain syntax-only contracts.

---

## Compiler-backed analysis

An optional analysis mode whose facts have passed through a supported compiler integration and stable normalization boundary. Parseable compiler output alone does not make evidence compiler-backed.

---

## Compiler evidence report

The standalone `swiftdebt-compiler-evidence` artifact. It records compiler-backed provenance and capability availability under its own schema version. It is not embedded in either syntax-only report.

---

## Evidence availability

`available` means a supported provider produced evidence that consumers may use. `unavailable` means evidence cannot be used and carries a reason. `ambiguous` means evidence cannot identify one semantic result and carries a reason; consumers must not select a candidate.

---

## Source identity

The analyzed source snapshot is identified by a validated content digest and, when available, a version-control revision plus working-tree state. Archives use the content-digest-only state. Missing identity is recorded as unavailable.
