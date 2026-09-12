public final class BaselineController {
    private var cache: [String: Int] = [:]
    private let formatter = BaselineFormatter()

    public init() {}

    public func score(_ records: [BaselineRecord]) -> Int {
        var total = 0
        for record in records {
            if let value = cache[record.identifier] {
                total += value
                continue
            }
            let value = formatter.normalized(record)
            cache[record.identifier] = value
            total += value
        }
        return total
    }
}

public struct BaselineRecord {
    public let identifier: String
    public let severity: Int
    public let tags: [String]

    public init(identifier: String, severity: Int, tags: [String]) {
        self.identifier = identifier
        self.severity = severity
        self.tags = tags
    }
}

public final class BaselineFormatter {
    public init() {}

    public func normalized(_ record: BaselineRecord) -> Int {
        var value = record.severity
        for tag in record.tags where tag.hasPrefix("debt") {
            value += tag.count
        }
        if record.identifier.contains("legacy") {
            value *= 2
        }
        return value
    }
}
