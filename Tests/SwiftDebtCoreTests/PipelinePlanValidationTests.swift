import Foundation
import Testing

@testable import SwiftDebtCore

@Suite("Pipeline plan validation")
struct PipelinePlanValidationTests {
    @Test("Only the current canonical policy decodes", arguments: pipelinePlanTestMutations)
    func rejectsNoncanonicalPlan(mutation: PipelinePlanTestMutation) throws {
        let encoded = try JSONEncoder().encode(pipelineTestPlan(mutating: mutation))

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(PipelinePlan.self, from: encoded)
        }
    }

    @Test("Plans without a policy revision are rejected")
    func rejectsMissingPolicyRevision() throws {
        let encoded = try JSONEncoder().encode(pipelineTestCanonicalPlan())
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "policyRevision")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(PipelinePlan.self, from: legacy)
        }
    }
}
