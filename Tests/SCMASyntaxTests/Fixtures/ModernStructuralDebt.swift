@propertyWrapper
struct Boxed<Value> {
    var wrappedValue: Value
}

actor ModernService {
    @Boxed var cache: [String: Int] = [:]

    subscript(key: String) -> Int {
        get async throws {
            if Task.isCancelled { return 0 }
            return cache[key] ?? 0
        }
    }

    func load(_ ids: [String]) async throws -> [Int] {
        defer { print("done") }
        #if DEBUG && os(macOS)
        if ids.isEmpty { return [] }
        #else
        guard !ids.isEmpty else { return [] }
        #endif
        do {
            var values: [Int] = []
            for id in ids {
                let value = try await self[id]
                if value > 0 {
                    values.append(value)
                }
            }
            return values
        } catch {
            throw error
        }
    }

    func map(_ ids: [String]) -> [String] {
        ids.map { id in
            if id.isEmpty { return "empty" }
            return id.uppercased()
        }
    }

    struct Nested {
        func nested(flag: Bool) {
            if flag {
                while flag {
                    repeat {
                        print(flag)
                    } while false
                }
            }
        }
    }
}
