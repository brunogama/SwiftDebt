import Foundation

func decodingErrorDescription(_ error: DecodingError) -> String {
    func path(_ context: DecodingError.Context) -> String {
        let keys = context.codingPath.map(\.stringValue).joined(separator: ".")
        return keys.isEmpty ? context.debugDescription : "\(keys): \(context.debugDescription)"
    }

    switch error {
    case .typeMismatch(_, let context), .valueNotFound(_, let context), .keyNotFound(_, let context),
        .dataCorrupted(let context):
        return path(context)
    @unknown default: return "\(error)"
    }
}
