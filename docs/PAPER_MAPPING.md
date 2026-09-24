# SCMA paper mapping and scoring contract

## Source and provenance

The user-supplied `paper006.pdf` is **SCMA: A Lightweight Tool to Analyze Swift Projects**, Fazle Rabbi, Syeda Sumbul Hossain, and Mir Mohammad Samsul Arefin, four pages. The document does not supply a complete executable specification or source release for its tool. No publication year/DOI is invented here.

References below are to that PDF's printed section/table/figure positions. The PDF itself and the original tool's code are not redistributed in this package. SwiftDebt is an independent implementation. Names, measurement categories, and Table I equations are attributed to the paper; implementation decisions beyond it are explicitly identified.

## Source-derived pipeline

Section III-A, page 2, describes selecting Swift files and constructing SwiftSyntax-based syntax trees. Section III-B describes collecting declarations and their relations before calculating metrics. Section III-C and Table I, page 3, describe violation counts, per-metric scores, and averaging. Section III-D describes HTML/CSV reports; the original HTML is served through Python.

SwiftDebt follows that broad sequence but uses an in-process SwiftParser frontend and standalone reporting. It does **not** recreate the paper's described call-graph matrix or Python report server.

## All ten metrics

The labels below preserve the paper's IDs, including its wording of NOAV and “Weighed.” The right-hand column is this implementation's explicitly chosen operational definition; it is not additional detail provided by the paper.

| ID | Paper description, section III-B | SwiftDebt policy |
| --- | --- | --- |
| LOCC | Line of Code by Classes; class lines excluding comments | Distinct nonblank token-bearing physical lines in the class plus its selected same-module extensions. |
| WMCC | Weighed Method Count by Classes; sum of method cyclomatic complexities | Sum over directly owned implemented `func`, `init`, `deinit`, and property/subscript accessor bodies, using the CCF policy below. |
| NOMC | Number of Methods by Classes | Count of directly owned implemented `func`, `init`, and `deinit`; accessors are not methods. |
| NOGC | Number of Global Variables by Classes | Distinct class-scope property binding names, including `let`, `var`, stored/computed/static members. True file-global variables are reported separately. |
| NOCC | Number of Couplings by Classes; connection in either direction | Degree of an undirected graph over selected nominal declarations, inferred from resolvable syntactic nominal references. Not a semantic call graph. |
| NOAV | Number of Accessed Methods by Variables; prose describes accessible global variables within a method | Distinct owning-type property names referenced explicitly through `self`/`Self` or lexically unshadowed bare names in each direct method or accessor body. Lexical estimate only. |
| LOCF | Line of Code by Functions; lines within method bodies | Nonblank token-bearing physical body-statement lines for implemented functions/initializers/deinitializers, including free/local functions. |
| CCF | Cyclomatic Complexity by Functions | Base 1 plus the decision nodes defined in METRICS.md. The paper does not specify a Swift syntax-node policy. |
| NOPF | Number of parameters by Functions | Syntactically declared parameters per implemented callable. |
| DC | Duplicate Code; original tool uses Lizard | Native exact token-normalized physical-code-line clone pairs, minimum 11 code lines by default. Not Lizard-equivalent. |

Class-oriented metrics default to `classes`. `nominals` adds structs, enums, and actors under the same metric IDs as an explicit extension; it does not turn those types into classes. Protocol requirements, synthesized declarations, and anonymous closures are outside the callable inventory; accessor bodies are inside it as a separate callable kind (see METRICS.md). See METRICS.md for scope consequences.

## Literal Table I equations

Table I on page 3 was checked against the rendered page, not reconstructed solely from PDF text extraction. Violation comparisons are strict `>`.

| ID | Paper violation threshold | Literal score |
| --- | --- | --- |
| LOCC | Each class over 500 | `1000 / (maxLOC + 1500)` |
| WMCC | Each class over 200 | `R = maxWMC * violations / totalWMC`; `2 / (R + 0.4)` |
| NOMC | N/A | `500 / (maxMethodsInAClass + 75)` |
| NOGC | N/A | `500 / (maxGlobalsInAClass + 75)` |
| NOCC | N/A | `1000 / (maxCoupling + 150)` |
| NOAV | N/A | `2 / (methods / globals + 0.4)` |
| LOCF | N/A | `2000 / (maxLOC + 300)` |
| CCF | Each function over 20 | `R = maxCC * violations / totalCC`; `2 / (R + 0.4)` |
| NOPF | Each function over 10 | `R = maxParam * violations / totalParams`; `2 / (R + 0.4)` |
| DC | Duplicate blocks over 10 lines | `R = duplicatedLines * totalLines / totalParams`; `2 / (R + 0.4)` |

For LOCC, use the maximum per-type line count; for LOCF, the maximum per-function body count. `methods` is the direct-method total for the selected type scope, and `globals` is the selected class-scope/property total. `totalParams` sums the declared parameters of all inventoried implemented callables. `totalLines` is the analyzed files' total nonblank token-bearing code-line count. `duplicatedLines` is the union of duplicated physical code lines across **all** occurrences, including the first, not the sum of every overlapping clone pair. These aggregation choices are necessary to operationalize the paper's underspecified variables; they are not asserted to match its original implementation.

WMCC/CCF/NOPF scores use the **paper** violation thresholds even when a user supplies different diagnostic thresholds. Reports expose `paperViolations` separately from configured `violations`. A custom policy must not silently rewrite a compatibility formula.

When a ratio's violation count is zero, its numerator is zero and `R = 0` for any denominator, so the score is `2 / 0.4 = 5` even when `totalWMC`, `totalCC`, or `totalParams` is zero. Likewise DC with zero duplicated lines scores 5 regardless of `totalParams`. Only a nonzero numerator over a zero denominator is treated as undefined.

## Why scores are not enabled by default

Section III-C says every score and their average lie in `[0, 5]`. The printed equations do not establish that property:

- For nonnegative LOC, the printed LOCC equation cannot exceed `1000 / 1500`, or two-thirds. Even a zero-line input would not approach 5.
- The printed NOMC, NOGC, NOCC, and LOCF equations can exceed 5 for small inputs. For example, `500 / (0 + 75)` is about 6.667.
- Several ratios divide by totals that can be zero. In particular, DC with any duplication is undefined on a valid source set with zero declared parameters.
- The DC denominator is printed as `totalParams`, not total lines. This unusual dependence is preserved in `paper` and `bounded` modes, not silently changed to a common duplication percentage. In practice it drives the DC score to almost zero for any clone at all, which is why the explicit `corrected` mode exists.
- NOAV's label, prose, and formula leave different possible interpretations. The formula does not actually consume the per-method access-count observations computed here; it consumes total methods and properties.

The dashboard on page 4 is not a specification that resolves these discrepancies. SwiftDebt does not infer new equations from a chart.

`--scoring none` is the default. `paper` implements the equations above literally, with finite results left unbounded. `bounded` explicitly clamps each otherwise-defined score to `[0, 5]`; it cannot repair undefined denominators or validate the model. Clamping is an implementation option, not part of the paper's printed calculation. `corrected` is `bounded` plus exactly one documented repair: the DC ratio becomes `duplicatedLines / totalLines`, the conventional duplication fraction. Every other equation, including the LOCC ceiling of two-thirds, is left as printed; the mode is labeled in the report's `scoringMode` and DC `scoreNote`.

No applicable entity or an undefined division produces no score (`null` in JSON). A syntax error under `strictSyntax` makes analysis incomplete and withholds **all** scores; by default the offending file is skipped with a warning and scores are computed over the files that parsed. An ambiguous duplicate type declaration omits that type with a warning. The overall value exists only when all ten individual scores exist and the analysis is complete, then is their arithmetic mean as in section III-C. There is no denominator reduction to “only available metrics,” perfect empty-project score, or replacement zero.

## Thresholds versus quality claims

Only LOCC, WMCC, CCF, NOPF, and DC receive default violation limits because those are the five supplied by Table I. Other limits are optional repository policies. All custom limits in this implementation are upper bounds; a custom NOAV upper bound must not be described as reproducing the paper's stated cohesion preference.

Section V, page 4, identifies company-derived metrics/thresholds, no evaluation on other open-source projects, and runs on 11 iOS projects. SwiftDebt therefore does not present the formulas as universally calibrated defect predictors, architectural conformance rules, or evidence of maintainability. It offers measurements and explicit policy gates, not a scientific certificate of code quality.

## Implementation references, separate from the paper

The following official sources informed the Swift/tooling integration rather than the metric definitions:

- SwiftSyntax tag and version alignment: https://github.com/swiftlang/swift-syntax/tree/602.0.0
- SwiftPM extensible build tools, SE-0303: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0303-swiftpm-extensible-build-tools.md
- SwiftPM command plugins, SE-0332: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0332-swiftpm-command-plugins.md
- SwiftPM 6.2.1 plugin command APIs: https://github.com/swiftlang/swift-package-manager/blob/swift-6.2.1-RELEASE/Sources/PackagePlugin/Command.swift
- SwiftPM 6.2.1 argument extraction: https://github.com/swiftlang/swift-package-manager/blob/swift-6.2.1-RELEASE/Sources/PackagePlugin/ArgumentExtractor.swift

The provided measurements are defined by this package version, its parser version, its source selection, and its explicit policy. Comparisons across tools require equivalent definitions and input scope, not only matching metric abbreviations.
