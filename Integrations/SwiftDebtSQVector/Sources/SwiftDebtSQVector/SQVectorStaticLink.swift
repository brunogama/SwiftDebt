#if canImport(SQVector)
    import SQVector
    import SwiftDebtKit

    /// Confirms that SwiftDebt can consume SQVector's static SwiftPM product.
    public enum SQVectorStaticLink {
        public static let packageIdentity = SQVectorPackageIdentity.pinned

        public static func vector(_ values: [Float]) throws -> Vector {
            try Vector(float32: values)
        }
    }
#endif
