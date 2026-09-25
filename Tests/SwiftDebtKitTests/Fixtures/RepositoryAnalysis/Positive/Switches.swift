struct FulfillmentCoordinator {
    let mode: FulfillmentMode

    func reservationLabel() -> String {
        switch mode {
        case .pickup:
            "reserved"
        case .delivery:
            "scheduled"
        }
    }

    func confirmationLabel() -> String {
        switch mode {
        case .pickup:
            "ready"
        case .delivery:
            "in transit"
        }
    }
}
