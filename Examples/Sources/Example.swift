// Small, intentionally imperfect fixture for CLI and report examples.
final class Store {
    var value = 0

    func save(_ newValue: Int) {
        value = newValue
    }
}

final class Processor {
    let store = Store()

    func process(_ values: [Int], enabled: Bool) -> Int {
        guard enabled else { return 0 }
        var total = 0
        for value in values {
            if value > 0 && value < 100 {
                total += value
            }
        }
        store.save(total)
        return total
    }

    func copiedA(_ input: Int) -> Int {
        var value = input
        value += 1
        value *= 2
        value -= 3
        value += 4
        value *= 5
        value -= 6
        value += 7
        value *= 8
        value -= 9
        value += 10
        value *= 11
        value -= 12
        return value
    }

    func copiedB(_ input: Int) -> Int {
        var value = input
        value += 1
        value *= 2
        value -= 3
        value += 4
        value *= 5
        value -= 6
        value += 7
        value *= 8
        value -= 9
        value += 10
        value *= 11
        value -= 12
        return value
    }
}

actor Worker {
    func work(_ value: Int) -> Int { value + 1 }
}
