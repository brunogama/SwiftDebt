enum State {
    case idle
    case active
    case stopped
}

struct FirstOwner {
    let state: State

    func label() -> String {
        switch state {
        case .idle: "idle"
        case .active: "active"
        case .stopped: "stopped"
        }
    }
}

struct SecondOwner {
    let state: State

    func label() -> String {
        switch state {
        case .idle: "idle"
        case .active: "active"
        case .stopped: "stopped"
        }
    }
}

struct DifferentShapes {
    let state: State

    func shortLabel() -> String {
        switch state {
        case .idle: "idle"
        default: "busy"
        }
    }

    func detailedLabel() -> String {
        switch state {
        case .idle: "idle"
        case .active: "active"
        case .stopped: "stopped"
        }
    }
}

struct DifferentDiscriminators {
    let first: State
    let second: State

    func firstLabel() -> String {
        switch first {
        case .idle: "idle"
        default: "busy"
        }
    }

    func secondLabel() -> String {
        switch second {
        case .idle: "idle"
        default: "busy"
        }
    }
}
