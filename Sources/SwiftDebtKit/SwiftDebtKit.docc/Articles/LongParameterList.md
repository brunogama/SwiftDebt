# Long Parameter List

SwiftDebt reports functions and initializers with six or more declared parameters. The count gives a concrete place to review call-site complexity. Default arguments and external labels still count because they are part of the declaration.

---

## Why review it

Many arguments can hide relationships among values and make call sites difficult to scan. A wrong value can fit the right type, especially when several arguments share a primitive type. A public API may legitimately require many independent values, so inspect its callers before changing it.

---

## Suggested change

Group values that travel together into a named value type. If values already live on a domain object, pass that object or move behavior closer to it. Avoid a generic parameter bag that merely hides the count.

```swift
struct InvoiceAddress {
    let street: String
    let city: String
    let postalCode: String
}

func ship(_ order: Order, to address: InvoiceAddress) { /* ... */ }
```

---

## Detection and limits

Rule ID: `swiftdebt.refactoring.long-parameter-list`. The location points to the function name or `init` keyword. SwiftDebt does not infer whether parameters form a useful abstraction. Conditional compilation is parsed syntactically.

See [Refactoring, second edition](https://www.informit.com/store/refactoring-improving-the-design-of-existing-code-9780134757711) for the source catalog.
