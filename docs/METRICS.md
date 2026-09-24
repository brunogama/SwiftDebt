<!-- swiftdebt-release-version:start -->
# Measurement specification - engine 0.7.0
<!-- swiftdebt-release-version:end -->

This document defines **implemented behavior**, not additional claims from the paper. The original categories and equations are mapped in PAPER_MAPPING.md.

## Source and completeness

Input is UTF-8 Swift source. The parser operates in source-accurate mode without building, type-checking, resolving imports, expanding macros, or evaluating conditional compilation. Source-located parser errors make a file invalid and its measurements are omitted. By default the file is skipped with a `warning` diagnostic prefixed `File skipped (parse error)`, `analyzedFileCount` drops below `inputFileCount`, and the report stays complete. With `strictSyntax` the same error is reported as an `error`, the report is marked incomplete, and all scores are withheld. Valid files still contribute raw observations in both modes. The default exists because the pinned parser can reject syntax a newer compiler accepts; the build plugin must not veto code the compiler will build. Input/configuration/read failures and clone-budget exhaustion throw instead of producing an apparently complete report.

`complete: true` means the selected files were handled according to these syntactic policies. It does **not** establish that the application compiles, that name resolution is correct, or that the selection contains every source in a product. Reports include sorted input paths, module names, input/analyzed file counts, and the clone floor.

Every `#if` branch is parsed; flags such as `DEBUG`, platform conditions, imports, and compiler feature tests are not evaluated. If mutually exclusive branches declare the same selected type key, that type is omitted with a `warning` diagnostic; the report stays complete and other types are unaffected. Functions declared in every branch still appear in the function metrics. Distinct conditional method definitions or properties can still both contribute. Use identical source/configuration scope for comparisons; these are not compiler-configuration-specific metrics.

Directory discovery uses a virtual module named `Workspace`. The command plugin supplies actual SwiftPM module names for the current package's selected targets. The build plugin supplies only its current target. In-memory callers supply their own explicit module identities.

---

## Built-in syntax rule observations

Default text output runs an ordered catalog of syntax rules after source discovery. Each selected source is parsed once for the catalog. Each rule and source pair commits independently: a throw, unsupported contract, or invalid emission discards that pair without erasing another rule's committed observations. A parse failure prevents every rule from running for that source. Absence is established only when every selected pair commits with no detection.

| Rule identity | Default severity | Exact syntax and location |
| --- | --- | --- |
| `swiftdebt.force-try` | `warning` | Every `try!`, at `!`. |
| `swiftdebt.concurrency.unchecked-sendable` | `information` | Inherited-type syntax spelled `@unchecked Sendable`, at `@`. A final qualified component spelled `Sendable` also matches; no name binding is claimed. |
| `swiftdebt.concurrency.actor-nonisolated-unsafe` | `information` | `nonisolated(unsafe)` on a direct member of an actor declaration, at `unsafe`. Actor extensions are not bound to their actors. |
| `swiftdebt.concurrency.actor-state-across-await` | `information` | A direct actor method explicitly accesses the same direct mutable actor property in sequential statements before and after an `await`, at `await`. Nested closures, actor extensions, and control-flow branches are outside this rule. |
| `swiftdebt.code-smell.force-cast` | `warning` | Every `as!`, at `!`. |
| `swiftdebt.code-smell.empty-catch` | `warning` | A catch body with no code block items, at `catch`. Comments and trivia do not make the body nonempty. |
| `swiftdebt.refactoring.long-function` | `warning` | A function body with at least 20 direct statements, at the function name. |
| `swiftdebt.refactoring.long-parameter-list` | `warning` | A function or initializer with at least six parameters, at the name or `init`. |
| `swiftdebt.refactoring.global-data` | `warning` | A mutable variable declared directly at file scope, at `var`. |
| `swiftdebt.refactoring.large-class` | `warning` | A class with at least 20 direct members, at the class name. |

The concurrency rules expose assumptions for review. They do not prove a race, an interleaving, or a definite bug. Apple documents [`@unchecked Sendable`](https://developer.apple.com/documentation/swift/sendable) as disabling compiler enforcement for a conformance; SE-0412 defines [`nonisolated(unsafe)`](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0412-strict-concurrency-for-global-variables.md) as an opt-out from static isolation checking; and [SE-0306](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md#actor-reentrancy) explains actor reentrancy across `await`. Visitor-based rules inspect every parsed `#if` branch. The Global Data rule checks only direct file-scope declarations, so declarations nested in a `#if` clause are outside its contract. The state-across-await rule inspects only direct declarations in the parsed actor and does not evaluate conditional compilation.

Rule observations remain outside `AnalysisReport` schema 2, `DebtReport` schema 2, and metric scores. Text output reports them. With `failOnViolation` enabled, the catalog also runs for other report formats and any detection triggers exit 1 without changing their output schemas. Parse or rule execution failure triggers exit 2.

---

## Type identity and extensions

A type key consists of module and lexically qualified nominal name. Nested types include their containing nominal name. Types declared inside callables include a source-offset local-scope discriminator. Equal names in different modules are never merged.

Default `classes` includes declared classes only. `nominals` also includes structs, enums, and actors; protocols are not inventory types. Enums' cases do not become properties. The JSON field `classScopeVariableCount` retains its schema name under `nominals`, where it means properties of all selected nominal types.

Same-module extension fragments with a matching base key are merged even across files. Base declarations must be present in the selected input. Extensions of external types, protocol extensions without a selected nominal base, typealias-based extensions, or differently spelled qualified extension names are not resolved into an owning type. Their implemented functions may still appear in the function metrics.

Nested type LOC contributes to the enclosing declaration's physical span and has its own observation, so summing LOCC is not a distinct project-line count. Use report `codeLineCount` for that count. Each extension declaration contributes its own physical code lines, including its header/braces.

## Code lines: LOCC, LOCF, and file totals

A code line is a distinct physical line containing a nonblank fragment of a present Swift token. Whitespace-only/comment-only lines do not count. An end-of-line comment does not erase preceding code. Nested comments and comment markers embedded in string literals are handled by SwiftParser, not regular expressions.

LOCC counts all token-bearing lines in the nominal declaration and merged extension declarations. LOCF counts token-bearing lines of the callable body's statements, excluding the outer body braces and signature. An internal control-flow brace on its own line counts; an empty body has LOCF 0. If signature and statements share one physical line, that line contributes when body statements occupy it.

Nonblank lines inside a multiline token/string literal count as source code lines. Empty/whitespace-only literal fragments do not. Line locations support CRLF and Unicode through SourceLocationConverter; columns are UTF-8 byte-based, not display-cell positions. Files retain their original physical line numbers in diagnostics even though blank/comment lines are removed from clone matching.

## Callable inventory: NOMC, WMCC, LOCF, CCF, NOPF

Implemented `func`, `init`, and `deinit` declarations are inventoried as methods. A declaration without a body is not counted. Direct members of a selected type count toward NOMC, WMCC, and NOAV.

Property and subscript accessor bodies (`get`, `set`, `willSet`, `didSet`, `_read`, `_modify`, and the implicit getter of `var x: T { ... }`) are inventoried as **accessor callables** named `Owner.property.get` or `Owner.subscript.set`. They count toward LOCF, CCF, and NOPF, and when their owner is a selected type, toward WMCC and NOAV. They are **not** methods and do not count toward NOMC or `methodCount`. Subscript accessors carry the subscript's declared parameter count; property accessors carry zero. The implicit `newValue`/`oldValue` (or an explicitly named accessor parameter) is treated as a local binding. Free functions and local named functions count toward LOCF, CCF, and NOPF, not toward an enclosing type's direct-method metrics. Operator functions follow the ordinary implemented-function rule.

Initializers count as methods and carry their declared parameter count. Deinitializers count with zero parameters. Each parameter declaration counts once regardless of external/internal label, default value, variadic marker, or modifiers.

Anonymous closures, protocol requirements, synthesized members, and macro-generated declarations have no separate callable observations. Decisions and field accesses inside nested local functions or closures do not inflate the enclosing callable's complexity/NOAV. Local named functions are measured separately; closures are not. Closure complexity, cognitive complexity, and nesting are still extracted as deterministic syntax facts and covered by parser fixtures; closure effects participate in functional-composition evidence. They intentionally do not become independently ranked debt items because anonymous closures lack a stable source-level callable identity. The enclosing callable's **physical LOC still contains nested source text**.

### CCF decision policy

Start at 1 for an implemented callable. Add 1 for each `if` expression/statement, `guard`, `for`, `while`, `repeat`, `catch` clause, ternary conditional, nondefault `switch case` clause, and `&&`/`||` operator token visited in its body. Operators inside a `#if` condition are compile-time, not runtime decisions, and are not counted; the branch bodies are. Both parser-unfolded and folded ternary representations are handled.

An `else if` adds its own `if`; an `else` does not. A `case a, b` clause counts as one case, not two alternatives. Multiple catch clauses count separately. `default`, `do`, `defer`, `return`, `throw`, `await`, optional chaining, nil coalescing `??`, and comma-separated conditions do not add a decision on their own. Expressions within those constructs can still contain a counted decision/operator. Overloaded `&&`/`||` spelling is treated syntactically, not semantically.

WMCC sums this CCF value over direct methods and direct accessor callables. It does not apply a different complexity model or account for runtime dispatch/fan-out. The paper gives no sufficiently detailed Swift decision-node rules to establish equality with its original CCF values.

## Property bindings: NOGC and top-level count

NOGC counts distinct names directly declared at selected type scope: stored/computed properties, `let`/`var`, instance/static/class members, and names in tuple or multi-binding declarations. It excludes parameters, local variables, closure bindings, enum cases, requirements of a protocol nested inside the type, and inherited properties that are not declared on that type. Distinct names are merged across selected extensions; conflicting same-name properties are not type-checked.

This deliberately operationalizes the paper's ambiguous “global variables in a class” as **class-scope properties**. `topLevelVariableCount` is a separate informational count of true file-scope variable bindings. Block locals in top-level control flow do not become file globals. Neither state mutability nor access level changes these counts.

## Field access estimate: NOAV

For each direct method, collect explicit `self.name`/`Self.name` and bare identifier references, then intersect with the selected owning type's declared property names. A property's name is counted at most once per method. `other.name` is not evidence of accessing the current type's property. Nested callable/closure bodies are skipped.

Bare names are suppressed only while a same-named local binding is **lexically in scope**. Parameters cover the whole body. A binding introduced by `let`/`var`, `if`/`while` optional or pattern bindings, `for`, `switch case`, `catch`, or a local `func` name is visible inside the construct that introduces it; `guard` bindings are visible for the remainder of the enclosing block. A binding's initializer is visited before its name is declared, so `if let title = Optional(title)` counts one field read of `title` before shadowing it. This is a syntactic scope model, not a compiler-grade lexical environment: multiple bindings of the same name in one block are not distinguished, and a use that textually precedes a same-block declaration is still counted. Explicit `self` always identifies a field regardless of shadowing.

Unresolved/implicit binding forms, patterns, capture lists, generics, inherited state, property wrappers, dynamic members, and binding ambiguity can produce over- or undercounts. No accessibility, actor-isolation, or semantic cohesion guarantee follows from NOAV. The paper's literal NOAV score uses aggregate methods/properties, **not** the observed access-count list.

## Coupling estimate: NOCC

Collect syntactic type names, names of called expressions, and named member receivers within each selected type fragment, excluding nested nominal declarations. Resolve against selected type keys by lexical nested scope and same module, then explicit module qualification, then a unique candidate in imported modules. Multiple imported candidates remain unresolved rather than choosing one arbitrarily.

A reference in either direction produces one undirected edge; repeated references do not multiply it. Self-edges are discarded. The per-type value is graph degree. Therefore the sum of per-type NOCC values is twice the number of unique graph edges, not a second definition of project coupling.

This is not a call graph or compiler symbol graph. References to framework/dependency types outside selected input are omitted. Aliases, inferred receiver types, generic constraints/substitutions, overload resolution, access control, protocol dispatch, and inheritance semantics are not modeled. A variable/function spelling that happens to match a declared type can be a false positive. A real connection through an inferred or erased type can be missed. Build-plugin reports only see the current target; use the command plugin to include multiple root-package targets.

## Native clone detection: DC

The native detector creates signatures from length-prefixed token-text fragments on each nonblank code line. It ignores intertoken whitespace, comments, and removed blank/comment-only lines. It preserves token spellings, identifiers, literal content, and boundaries between retained code lines. It is not invariant to arbitrary line wrapping or renamed variables, and whitespace-only lines in multiline literals are discarded by the code-line policy. It does not know whether an equal span is behaviorally meaningful duplication.

Rolling hashes select candidate windows. Every reported match is verified against actual signatures, so a hash collision alone cannot create a finding. Matches extend forward while equal. Same-file occurrences must not overlap within a reported pair; the extension is clipped at their separation. Only verified spans may suppress already-covered seed windows on the same diagonal. This condition is tested exhaustively against a brute-force duplicated-line union on all binary line sequences of lengths 2 through 9 with floor 2.

The default minimum is 11 code lines. Matching may cross declarations because the scanner operates on a file's code-line stream, not only function bodies. Different overlapping clone pairs may be reported; the result is not a minimal clone-class partition. Each pair is an observation, located at its first occurrence. `uniqueDuplicatedLineCount` unions actual physical code lines across all occurrences, avoiding double counting between pairs and including the first occurrence. Metric `DC.total` instead sums per-pair lengths and is **not** that union.

A deterministic comparison budget counts candidate-pair checks and signature comparisons. Exceeding the configured maximum fails the analysis. Hash buckets and extracted source facts still consume memory; this is not a hard memory or wall-clock limit, and highly repetitive inputs can reach the budget. Raising the budget trades safety margin for more work. There is no Lizard process, copied Lizard source, or promise of matching its block detection.

## Determinism, output, and failures

Sort order is fixed by module/entity/path/location and metric order. Parsing concurrency does not change report order. Reports contain no wall-clock generation timestamp or random identifiers. Identical selected source, module mapping, options, parser/engine version, and paths produce identical JSON in the tested environment. Diagnostic output uses root-qualified paths and therefore differs across root locations. Locally scoped type IDs change if preceding source offsets change.

Threshold findings use strict upper bounds. Syntax errors and ambiguous declarations are separate diagnostics. With no gate, findings are warnings; `failOnViolation` makes them fail the CLI/build. Incomplete analysis fails independently of threshold policy. Never treat an empty or failed report as zero violations. The CLI writes a requested report even when a completed/incomplete result will return a nonzero status, so automation must check the process status and the JSON `complete` field.

Report writes are atomic and refuse selected sources, the active configuration, input manifest, or any `.swift` destination. HTML escapes source-derived text and uses no script/network assets. CSV text cells guard common formula prefixes. JSON is preferred over text/diagnostic parsing for automation. Report paths and entity names can still reveal private project structure; do not publish reports without review.

## Scope not implemented

There is no compiler-index integration, architecture rule DSL, import-cycle checker, dependency-injection policy, broader compiler-backed security or concurrency lint suite, baseline suppression, automatic refactoring, persistent parse cache, SARIF output, daemon, or IDE source extension. The built-in catalog contains the ten syntax contracts above. These are distinct features, not implied by the paper or the delivered CLI/plugins. The versioned compiler-evidence sidecar and the boundary for future providers are defined in [ADR 0001](adr/0001-compiler-evidence-sidecar-boundary.md); the contract does not add compiler-backed metrics or change syntax-only reports.
