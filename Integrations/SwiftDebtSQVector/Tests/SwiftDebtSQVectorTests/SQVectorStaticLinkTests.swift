import SwiftDebtSQVector
import Testing

@Test func linksSQVectorStaticProduct() throws {
    let vector = try SQVectorStaticLink.vector([1, 2])
    #expect(vector.dimensions == 2)
}
