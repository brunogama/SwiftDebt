# Large Class

SwiftDebt reports a class with at least 20 direct member declarations. The count includes stored properties and methods in the declaration body. Members in extensions and compiler-generated members are outside this count.

---

## Why review it

Many members can indicate several responsibilities, especially when different clients use different subsets. Size alone cannot establish that: a cohesive adapter or facade may have many members for a good reason.

---

## Suggested change

Group fields and methods by the behavior they support. Extract a type for a cohesive group, move its methods with its state, and keep an intentional interface between the types. Use call-site tests to check that behavior remains intact.

```swift
final class CheckoutCoordinator {
    private let pricing: PricingService
    private let payment: PaymentService

    init(pricing: PricingService, payment: PaymentService) {
        self.pricing = pricing
        self.payment = payment
    }
}
```

---

## Detection and limits

Rule ID: `swiftdebt.refactoring.large-class`. The location points to the class name. SwiftDebt does not infer responsibility boundaries, usage, or generated declarations. Review the count as a prompt for design inspection.

See [Refactoring, second edition](https://www.informit.com/store/refactoring-improving-the-design-of-existing-code-9780134757711) for the source catalog.
