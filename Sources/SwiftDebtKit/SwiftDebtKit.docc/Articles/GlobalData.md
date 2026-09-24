# Global Data

SwiftDebt reports a mutable `var` declared directly at file scope. A top-level constant is outside this rule. Members of a type are also outside it because they have an explicit owner.

---

## Why review it

Code far from the declaration may change the value. That makes behavior and concurrency safety harder to reason about. The syntax alone cannot show whether access is confined, synchronized, or even reachable, so treat the result as a request to inspect ownership.

---

## Suggested change

Put the state behind one owner and make reads and mutations explicit. An actor can serialize access when callers are concurrent; a value passed to functions can be simpler when the state is immutable per operation.

```swift
actor RequestCounter {
    private var count = 0

    func increment() { count += 1 }
    func current() -> Int { count }
}
```

---

## Detection and limits

Rule ID: `swiftdebt.refactoring.global-data`. The location points to the top-level `var` keyword. This rule does not prove a data race or inspect access paths. It checks direct file-scope declarations; declarations inside `#if` clauses are outside its current contract.

See [Refactoring, second edition](https://www.informit.com/store/refactoring-improving-the-design-of-existing-code-9780134757711) for the source catalog.
