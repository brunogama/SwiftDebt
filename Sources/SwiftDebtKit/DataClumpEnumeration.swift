struct DataClumpGroup {
    let elements: [DataClumpElement]
    let unitIndices: [Int]
}

enum DataClumpEnumerationError: Error {
    case comparisonBudgetExceeded
}

struct DataClumpComparisonBudget {
    let limit: Int
    private(set) var consumed = 0

    mutating func consume() throws {
        guard consumed < limit else {
            throw DataClumpEnumerationError.comparisonBudgetExceeded
        }
        consumed += 1
    }
}
