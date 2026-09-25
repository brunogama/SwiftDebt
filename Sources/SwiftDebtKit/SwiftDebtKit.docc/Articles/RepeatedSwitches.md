# Repeated Switches

SwiftDebt's R2 research analyzer reports switches that repeat one exact
syntactic dispatch shape inside the same textual module and nominal-type scope.
This rule remains Research until the R2 labeled-corpus, independent review,
accuracy, determinism, and calibrated performance gates pass.

---

## Why review it

Repeated dispatch on the same distinction can scatter behavior across methods.
Adding a new case then requires coordinated edits and makes omissions easier.

---

## Evidence predicate

The default predicate requires at least two switch statements with the same
simple identifier or member-access discriminator and the same ordered normalized
case labels. Each switch must contain at least two cases. Bodies do not
participate in the shape.

```swift
switch mode {
case .pickup: reserveCounter()
case .delivery: reserveCourier()
}

switch mode {
case .pickup: printTicket()
case .delivery: sendTrackingLink()
}
```

The schema 1 repository sidecar records the textual scope, discriminator, case
shape, compared source locations, threshold, and source snapshot digest.

---

## Suggested change

Centralize the dispatch when one operation owns it. When each case represents a
stable behavior family, move the variation behind polymorphic behavior.

---

## Limits

Rule ID: `swiftdebt.refactoring.repeated-switches`. Equal discriminator spelling
is not compiler-resolved identity. Switch case order remains significant because
patterns and `where` clauses can be order-sensitive. Conditional-compilation
case elements make the rule outcome incomplete instead of clean.
