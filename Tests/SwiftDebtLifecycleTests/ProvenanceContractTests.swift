import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 provenance and decode contracts")
struct ProvenanceContractTests {
    @Test("Parsed SourceUnits reject parse-only not-executed outcomes")
    func parsedSourceCannotDecodeAsNotExecuted() throws {
        let snapshot = try makeObservation(
            id: "parsed-source",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(0))]
        )
        var root = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any]
        )
        var atomics = try #require(root["atomicObservations"] as? [[String: Any]])
        var atomic = try #require(atomics.first)
        atomic["outcome"] = [
            "kind": "not-executed",
            "reason": [
                "code": "source-parse-failed",
                "message": "Fabricated parse failure.",
            ],
        ]
        atomics[0] = atomic
        root["atomicObservations"] = atomics

        let corrupted = try lifecycleJSONData(root)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ObservationSnapshot.self, from: corrupted)
        }
    }

    @Test("Source and configuration identities require canonical digests")
    func malformedIdentityDigestsFailClosed() throws {
        #expect(throws: (any Error).self) { try LifecycleDigest(value: "digest") }
        #expect(throws: LifecycleContractError.self) { try GitRevisionID("main") }

        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        _ = try store.ingest(
            makeObservation(
                id: "digest-root",
                sequence: 1,
                rules: [LifecycleRuleV1(mode: .committed(1))]
            )
        )
        let valid = try Data(contentsOf: fixture.url)

        var root = try artifactJSONObject(at: fixture.url)
        var snapshots = try #require(root["snapshots"] as? [[String: Any]])
        var snapshot = try #require(snapshots.first)
        var provenance = try #require(snapshot["provenance"] as? [String: Any])
        var sourceIdentity = try #require(provenance["sourceIdentity"] as? [String: Any])
        var contentDigest = try #require(sourceIdentity["contentDigest"] as? [String: Any])
        contentDigest["value"] = "bogus"
        sourceIdentity["contentDigest"] = contentDigest
        provenance["sourceIdentity"] = sourceIdentity
        snapshot["provenance"] = provenance
        snapshots[0] = snapshot
        root["snapshots"] = snapshots
        try lifecycleJSONData(root).write(to: fixture.url, options: .atomic)
        #expect(throws: LifecycleStoreError.self) { try store.load() }

        try valid.write(to: fixture.url, options: .atomic)
        root = try artifactJSONObject(at: fixture.url)
        snapshots = try #require(root["snapshots"] as? [[String: Any]])
        snapshot = try #require(snapshots.first)
        provenance = try #require(snapshot["provenance"] as? [String: Any])
        var configuration = try #require(provenance["configurationFingerprint"] as? [String: Any])
        configuration["value"] = "informal-label"
        provenance["configurationFingerprint"] = configuration
        snapshot["provenance"] = provenance
        snapshots[0] = snapshot
        root["snapshots"] = snapshots
        try lifecycleJSONData(root).write(to: fixture.url, options: .atomic)
        #expect(throws: LifecycleStoreError.self) { try store.load() }
    }

    @Test("Unknown source identity cannot verify resolution")
    func unavailableSourceIdentityLeavesFindingUnverified() throws {
        let reason = try LifecycleReason(
            code: "source-identity-unavailable",
            message: "The caller could not establish source content identity."
        )
        let identity = SnapshotSourceIdentity.unavailable(reason)
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        _ = try store.ingest(
            makeObservation(
                id: "unknown-source-root",
                sequence: 1,
                sourceIdentity: identity,
                rules: [LifecycleRuleV1(mode: .committed(1))]
            )
        )
        _ = try store.ingest(
            makeObservation(
                id: "unknown-source-child",
                sequence: 2,
                predecessor: "unknown-source-root",
                sourceIdentity: identity,
                rules: [LifecycleRuleV1(mode: .committed(0))]
            )
        )

        let finding = try #require(store.load().findings.first)
        #expect(finding.lifecycleState == .open)
        guard case .unverified(let reasons) = finding.events.last?.transition else {
            Issue.record("Expected unavailable source identity to remain unverified")
            return
        }
        #expect(reasons.map(\.code) == ["source-identity-unavailable"])
    }

    @Test("A persisted resolution rejects tampered comparability provenance")
    func resolvedArtifactRevalidatesComparability() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        _ = try store.ingest(
            makeObservation(
                id: "comparability-root",
                sequence: 1,
                rules: [LifecycleRuleV1(mode: .committed(1))]
            )
        )
        _ = try store.ingest(
            makeObservation(
                id: "comparability-child",
                sequence: 2,
                predecessor: "comparability-root",
                rules: [LifecycleRuleV1(mode: .committed(0))]
            )
        )
        let valid = try Data(contentsOf: fixture.url)

        try assertRejectedMutation(validArtifact: valid, store: store, fixture: fixture) { provenance in
            provenance["scope"] = [
                "kind": "partial",
                "reason": ["code": "tampered", "message": "Coverage is partial."],
            ]
        }
        try assertRejectedMutation(validArtifact: valid, store: store, fixture: fixture) { provenance in
            var fingerprint = try #require(provenance["configurationFingerprint"] as? [String: Any])
            fingerprint["value"] = String(repeating: "a", count: 64)
            provenance["configurationFingerprint"] = fingerprint
        }
        try assertRejectedMutation(validArtifact: valid, store: store, fixture: fixture) { provenance in
            provenance["capabilities"] = [
                [
                    "name": "semantic-index",
                    "state": [
                        "kind": "unavailable",
                        "reason": ["code": "missing", "message": "The capability is unavailable."],
                    ],
                ]
            ]
        }
    }

    private func assertRejectedMutation(
        validArtifact: Data,
        store: LifecycleArtifactStore,
        fixture: TemporaryLifecycleArtifact,
        mutate: (inout [String: Any]) throws -> Void
    ) throws {
        try validArtifact.write(to: fixture.url, options: .atomic)
        var root = try artifactJSONObject(at: fixture.url)
        var snapshots = try #require(root["snapshots"] as? [[String: Any]])
        let index = try #require(snapshots.firstIndex(where: { $0["id"] as? String == "comparability-child" }))
        var snapshot = snapshots[index]
        var provenance = try #require(snapshot["provenance"] as? [String: Any])
        try mutate(&provenance)
        snapshot["provenance"] = provenance
        snapshots[index] = snapshot
        root["snapshots"] = snapshots
        try lifecycleJSONData(root).write(to: fixture.url, options: .atomic)
        #expect(throws: LifecycleStoreError.self) { try store.load() }
    }
}
