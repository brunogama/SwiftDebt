# Optional SQVector candidate index

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

The SQVector checkout must include the `SQVectorStatic` product. Access to its
repository is currently required to build this optional package.

The `SQVectorCandidateIndex` actor accepts caller-provided float vectors and
returns bounded nearest-neighbor candidates. A distance is retrieval evidence,
not a technical-debt finding. It makes no network request or embedding call.
Persistence, provider/model namespaces, source compatibility checks, replacement,
and deterministic rule validation remain part of R2; this package qualifies the
local static linkage and a small retrieval boundary.
