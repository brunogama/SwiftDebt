# Optional SQVector static linkage

This separate Swift package links the `SQVectorStatic` product from SQVector's
nested package. It does not change the SwiftDebt package manifest or its platform
requirements. The adapter is available on macOS 26 and iOS 26, where SQVector
currently supports it.

From the SwiftDebt repository root, link a complete local `sqvector-swift`
checkout. The link is ignored by Git. Then run:

```sh
mkdir -p .vendor
ln -s /absolute/path/to/sqvector-swift .vendor/sqvector-swift
swift test --package-path Integrations/SwiftDebtSQVector
```

The SQVector checkout must include the `SQVectorStatic` product. No published
SQVector revision exposes that product yet, so this local path does not qualify
the exact-revision requirement in R2 FR-23.

The `SQVectorStaticLink` smoke test constructs a vector through the linked
product. The index behaviors in R2 FR-24 remain unresolved, including insert,
replacement, deletion, persistence, dimension and namespace validation,
filtering, and bounded nearest-neighbor retrieval.
