# Long Function

A function with many steps can hide several jobs behind one name. SwiftDebt reports a function when its body has at least 20 direct statements. Nested statements, closures, and the quality of the design are not inferred from this count.

---

## Why review it

A reader must keep more local state and more steps in mind. An unrelated change can then touch the same function and make tests harder to target. A long function with a clear linear algorithm may be perfectly reasonable, so inspect the steps before refactoring.

---

## Suggested change

Find a consecutive group of statements that answers one question. Extract it into a named private function. Pass only the values it needs and return a result instead of mutating distant state. Keep tests around the original behavior while extracting.

```swift
func prepareInvoice(_ order: Order) -> Invoice {
    let lines = makeLines(from: order)
    let subtotal = subtotal(for: lines)
    let tax = tax(for: subtotal, region: order.region)
    return Invoice(lines: lines, total: subtotal + tax)
}
```

---

## Detection and limits

Rule ID: `swiftdebt.refactoring.long-function`. The location points to the function name. The count is syntax-only and includes declarations in inactive `#if` branches. It is a review signal, not proof that extraction is beneficial. Suppress a CI failure by leaving the opt-in `--fail-on-violation` gate off while investigating; the observation remains in the report.

See [Refactoring, second edition](https://www.informit.com/store/refactoring-improving-the-design-of-existing-code-9780134757711) for the source catalog.
