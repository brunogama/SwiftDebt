# Refactoring second-edition code smells

SwiftDebt uses the 24 Chapter 3 names from Martin Fowler's *Refactoring*, second edition, as a catalog, not as a claim that every subjective design judgment can be proven from syntax. The [publisher's table of contents](https://www.informit.com/store/refactoring-improving-the-design-of-existing-code-9780134757711) defines the catalog. The explanations and Swift examples in this repository are original.

---

## Completion predicate

A catalog entry is implemented only when a real `swift-debt analyze` execution identifies a concrete source span, explains the observed evidence, suggests a specific change, links to a published Swift-specific DocC article, and has positive and negative tests. When evidence needs cross-file bindings, usage, or history, the rule must not claim a clean result from a single parsed file.

Findings are advisory by default. `--fail-on-violation` is the explicit CI gate. Parse or rule execution failures remain exit 2 and never prove absence.

---

## Evidence map

| Book smell | Minimum Swift signal or evidence requirement | Status |
| --- | --- | --- |
| Mysterious Name | Project naming intent or a narrowly defined placeholder name | Later |
| Duplicated Code | Normalized bodies across files with meaningful equivalence | Later |
| Long Function | Function body size over a documented threshold | Active |
| Long Parameter List | Function declaration parameter count over a documented threshold | Active |
| Global Data | Mutable top-level declaration | Active |
| Mutable Data | Mutation/aliasing and state ownership | Later |
| Divergent Change | Distinct reasons for edits over change history | Later |
| Shotgun Surgery | Coordinated edits across files over change history | Later |
| Feature Envy | Resolved ownership of accessed members | Later |
| Data Clumps | Repeated parameter or property groups across declarations | Later |
| Primitive Obsession | Domain meaning of primitive values | Later |
| Repeated Switches | Repeated dispatch structure across source units | Later |
| Loops | Loop whose transformation would improve clarity, not mere loop syntax | Later |
| Lazy Element | Role and actual use of a small abstraction | Later |
| Speculative Generality | Unused extension points and change intent | Later |
| Temporary Field | State valid only during part of an object's lifetime | Later |
| Message Chains | Resolved access graph and an actionable delegation boundary | Later |
| Middle Man | Resolved forwarding methods and owners | Later |
| Insider Trading | Cross-type member access and visibility semantics | Later |
| Large Class | Type body size over a documented threshold | Active |
| Alternative Classes with Different Interfaces | Role equivalence and different public APIs | Later |
| Data Class | Behavioral role and externally owned behavior | Later |
| Refused Bequest | Inheritance contract and unused inherited behavior | Later |
| Comments | Comment hiding unclear behavior, not documentation or useful context | Later |

"Later" is an evidence requirement, not an absence result. These entries are deliberately excluded from the active rule catalog until a detector can meet the completion predicate.

The remaining work is tracked in [issue 48](https://github.com/brunogama/SwiftDebt/issues/48).

---

## Delivery sequence

1. Establish the current CLI/build/test baseline and the catalog's evidence boundaries.
2. Add explanation, proposed change, and DocC article links to rule reporting without allowing a rule to author canonical location or identity.
3. Implement the four syntax-supported rules above and test them through the real CLI, including the opt-in failure gate.
4. Publish the four DocC articles through the existing GitHub Pages release workflow. Expand the remaining catalog in evidence-specific slices; preserve the same per-rule proof gate.

The existing DocC workflow builds the documentation site on a main push. Branch content becomes available in the repository and in PR review first; the public site updates when it reaches main.
