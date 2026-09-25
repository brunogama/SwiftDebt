# Data Clumps

SwiftDebt's R2 research analyzer reports exact repeated groups of local names
and normalized declared types across parameter lists and nominal instance
properties. This rule remains Research until the R2 labeled-corpus, independent
review, accuracy, determinism, and calibrated performance gates pass.

---

## Why review it

Values that repeatedly travel together often represent a missing domain value.
Separate parameters make it easier to swap same-typed arguments and force each
caller to preserve relationships that one type could own.

---

## Evidence predicate

The default predicate requires at least three identical local-name and
normalized-type pairs in at least two declaration units. SwiftDebt computes
closed repeated groups so a four-element group does not also produce every
three-element subset with the same occurrences.

Parameter attributes, ownership modifiers, declared-type tokens, and variadic
markers participate in the parameter compatibility key. Default values and
external argument labels do not.

The schema 1 repository sidecar records every compared unit, the exact shared
elements, the occurrence count, the threshold, source locations, and source
snapshot digest.

```swift
func schedule(customerID: String, postalCode: String, countryCode: String) {}
func quote(customerID: String, postalCode: String, countryCode: String) {}
```

---

## Suggested change

Introduce a parameter object or focused value type when the repeated values
share one concept and invariants. For repeated instance properties, extract a
value type and compose it from the original owners.

---

## Limits

Rule ID: `swiftdebt.refactoring.data-clumps`. The rule compares exact
formatting-independent type syntax. It does not resolve type aliases or prove
that equal names in different binding contexts represent the same concept.
Unnamed parameters, inferred property types, local nominal types, computed
properties, and closure parameters are outside this implementation slice.
