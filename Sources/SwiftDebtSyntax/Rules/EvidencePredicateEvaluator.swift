import SwiftDebtCore

/// Evaluates an `EvidenceContract`'s boolean algebra (addendum E) against a
/// concrete set of observed evidence fact keys. This is the general-purpose
/// evaluator the contract's doc comment promises: `.all`/`.any`/`.not` are
/// actually walked and combined with real boolean operators, never
/// approximated by checking only the top-level case or counting facts.
enum EvidencePredicateEvaluator {
    /// - Parameters:
    ///   - predicate: The predicate tree to evaluate (typically
    ///     `definition.evidenceContract.required`).
    ///   - availableFacts: Keys of the evidence facts actually observed for
    ///     this candidate. A `.fact` node is satisfied only when its key is
    ///     present in this set.
    static func evaluate(_ predicate: EvidencePredicate, availableFacts: Set<String>) -> Bool {
        switch predicate {
        case .fact(let requirement):
            return availableFacts.contains(requirement.key)
        case .all(let predicates):
            return predicates.allSatisfy { evaluate($0, availableFacts: availableFacts) }
        case .any(let predicates):
            return predicates.contains { evaluate($0, availableFacts: availableFacts) }
        case .not(let inner):
            return !evaluate(inner, availableFacts: availableFacts)
        }
    }
}
