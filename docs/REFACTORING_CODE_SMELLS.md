# Refactoring second-edition code smells

SwiftDebt uses the 24 Chapter 3 names from Martin Fowler's *Refactoring*, second edition, as a catalog, not as a claim that every subjective design judgment can be proven from syntax. The [publisher's table of contents](https://www.informit.com/store/refactoring-improving-the-design-of-existing-code-9780134757711) defines the catalog. The explanations and Swift examples in this repository are original.

---

## Completion predicate

A catalog entry is implemented only when a real `swift-debt analyze` execution identifies a concrete source span, explains the observed evidence, suggests a specific change, links to a published Swift-specific DocC article, and has positive and negative tests. When evidence needs cross-file bindings, usage, or history, the rule must not claim a clean result from a single parsed file.

Findings are advisory by default. `--fail-on-violation` is the explicit CI gate. Parse or rule execution failures remain exit 2 and never prove absence.

---

## Evidence map

| Book smell | Minimum Swift signal or evidence requirement | Support state |
| --- | --- | --- |
| Mysterious Name | The name obscures the intended domain meaning. | Not Reliably Observable |
| Duplicated Code | Two concrete bodies have meaningful normalized equivalence. | Research |
| Long Function | A function body contains 20 or more top-level statements. | Supported |
| Long Parameter List | A function or initializer declares six or more parameters. | Supported |
| Global Data | A mutable var is declared directly in a file's top-level statement list, outside #if clauses. | Supported |
| Mutable Data | Mutation and aliasing expose state outside a clear owner. | Research |
| Divergent Change | One unit changes repeatedly for distinct reasons. | Research |
| Shotgun Surgery | One kind of change repeatedly requires coordinated edits across units. | Research |
| Feature Envy | A method accesses resolved foreign members more than its owner's members. | Research |
| Data Clumps | A type-compatible parameter or property group repeats across declarations. | Research |
| Primitive Obsession | Several primitives encode a domain concept needing its own type. | Not Reliably Observable |
| Repeated Switches | Normalized dispatch over one discriminator repeats across units. | Research |
| Loops | Replacing a specific loop improves clarity for its intent. | Not Reliably Observable |
| Lazy Element | An abstraction adds little behavior or role under observed uses. | Research |
| Speculative Generality | Extension points lack observed use and a justified variation contract. | Research |
| Temporary Field | A field is meaningful only during one object-lifetime phase. | Research |
| Message Chains | A resolved access chain exposes navigation through owners. | Research |
| Middle Man | Resolved forwarding behavior dominates a type's useful behavior. | Research |
| Insider Trading | Types exchange internal state beyond their intended collaboration. | Research |
| Large Class | A class declares 20 or more direct members. | Supported |
| Alternative Classes with Different Interfaces | Two role-equivalent types expose needlessly different APIs. | Research |
| Data Class | A type owns data while relevant behavior lives elsewhere. | Research |
| Refused Bequest | A subtype cannot use or uphold inherited behavior. | Research |
| Comments | A comment compensates for code that fails to express its behavior. | Not Reliably Observable |

The public `RefactoringCodeSmellCatalog` in `SwiftDebtCore` exposes the same 24 entries with their evidence needs, risks, and explanation contracts. `Research` and `Not Reliably Observable` entries are excluded from the active rule catalog. Their absence from a run is not evidence that the smell is absent.

Catalog report schema 1 contains this exact ordered catalog. A change to its entries, predicates, or support states requires a new catalog report schema version so archived reports cannot silently change meaning.

The remaining work is tracked in [issue 48](https://github.com/brunogama/SwiftDebt/issues/48).

---

## Delivery sequence

1. Establish the current CLI/build/test baseline and the catalog's evidence boundaries.
2. Add explanation, proposed change, and DocC article links to rule reporting without allowing a rule to author canonical location or identity.
3. Implement the four syntax-supported rules above and test them through the real CLI, including the opt-in failure gate.
4. Publish the four DocC articles through the existing GitHub Pages release workflow. Expand the remaining catalog in evidence-specific slices; preserve the same per-rule proof gate.

The existing DocC workflow builds the documentation site on a main push. Branch content becomes available in the repository and in PR review first; the public site updates when it reaches main.
