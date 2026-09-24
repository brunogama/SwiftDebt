public struct Consumer {
    public init() {}

    public func classify(_ value: Int) -> String {
        if value > 0 { return "positive" }
        return "nonpositive"
    }
}
