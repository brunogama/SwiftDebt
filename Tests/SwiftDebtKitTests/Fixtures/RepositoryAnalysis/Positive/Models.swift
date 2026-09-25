struct DeliveryAddress {
    let customerID: String
    let postalCode: String
    let countryCode: String
}

enum FulfillmentMode {
    case pickup
    case delivery
}
