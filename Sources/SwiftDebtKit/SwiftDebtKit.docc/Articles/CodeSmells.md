# Code Smells from Refactoring

SwiftDebt uses the 24 code-smell names in Chapter 3 of Martin Fowler's *Refactoring*, second edition. Each active rule reports an observable Swift syntax signal. A signal asks for review; it does not prove that a design needs refactoring.

---

The catalog comes from the [publisher's table of contents](https://www.informit.com/store/refactoring-improving-the-design-of-existing-code-9780134757711). The guidance here is written for SwiftDebt.

## Available rules

| Smell | Observed signal | Guidance |
| --- | --- | --- |
| Long Function | At least 20 direct statements | <doc:LongFunction> |
| Long Parameter List | At least six parameters | <doc:LongParameterList> |
| Global Data | Mutable file-scope declaration | <doc:GlobalData> |
| Large Class | At least 20 direct members | <doc:LargeClass> |

Run `swift-debt analyze <path>` for advisory findings. Add `--fail-on-violation` to make rule detections fail CI with exit status 1. Text output includes the observation, reason for review, proposed change, and article URL.

---

## Evidence still needed

The remaining names are part of the catalog, but SwiftDebt does not currently claim to detect them:

| Evidence needed | Smells |
| --- | --- |
| Cross-source structure | Duplicated Code, Data Clumps, Repeated Switches, Message Chains |
| Resolved ownership and relationships | Feature Envy, Middle Man, Insider Trading, Alternative Classes with Different Interfaces, Refused Bequest |
| Change history | Divergent Change, Shotgun Surgery |
| Domain intent, usage, or carefully calibrated context | Mysterious Name, Mutable Data, Primitive Obsession, Loops, Lazy Element, Speculative Generality, Temporary Field, Data Class, Comments |

An unimplemented smell is not a clean observation. The evidence requirements and planned acceptance checks are recorded in [the repository plan](https://github.com/brunogama/SwiftDebt/blob/main/docs/REFACTORING_CODE_SMELLS.md) and [issue 48](https://github.com/brunogama/SwiftDebt/issues/48).
