# Metric Definitions

SwiftDebt reports ten metric families derived from the SCMA paper. These definitions describe the implemented Swift syntax model. They do not claim compiler-level semantics or equivalence to the paper's original tool.

| ID | Observation |
| --- | --- |
| `LOCC` | Token-bearing physical lines in a selected type and its merged extensions. |
| `WMCC` | Sum of cyclomatic complexity for direct methods and accessors of a selected type. |
| `NOMC` | Implemented direct `func`, `init`, and `deinit` members of a selected type. |
| `NOGC` | Distinct properties declared at selected type scope. |
| `NOCC` | Degree of a syntactic, undirected coupling graph between selected types. |
| `NOAV` | Estimated reads or writes of declared properties in direct methods. |
| `LOCF` | Token-bearing lines in implemented callable bodies. |
| `CCF` | Cyclomatic complexity from Swift control-flow syntax, starting at 1. |
| `NOPF` | Declared parameter count for an implemented callable. |
| `DC` | Verified matching runs of tokenized code lines. |

The default type scope is `classes`. With `nominals`, type metrics also include structs, enums, and actors. Protocol requirements, synthesized members, macro-generated declarations, and anonymous closures do not become separate callable observations.

`CCF` counts `if`, `guard`, loops, catch clauses, nondefault switch cases, ternaries, and `&&` or `||` operators. `NOCC` resolves names only within selected source and known module names. `DC` preserves token spelling and line boundaries, so it is sensitive to identifier changes and line wrapping. No metric uses a compiler type checker.

Thresholds are strict upper bounds. The paper specifies defaults for `LOCC` 500, `WMCC` 200, `CCF` 20, `NOPF` 10, and `DC` 10. The other five are informational until your configuration adds thresholds. For the exact token, scope, and clone policies, see the repository's `docs/METRICS.md` measurement specification.
