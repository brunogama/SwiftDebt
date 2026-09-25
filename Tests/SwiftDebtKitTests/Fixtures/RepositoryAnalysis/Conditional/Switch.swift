enum Mode {
    case basic
    case advanced
}

func label(for mode: Mode) -> String {
    switch mode {
    #if FEATURE_ADVANCED
        case .advanced:
            "advanced"
    #endif
    case .basic:
        "basic"
    }
}
