func scheduleDelivery(
    customerID: String,
    postalCode: String,
    countryCode: String
) -> String {
    "\(customerID):\(postalCode):\(countryCode)"
}

func quoteDelivery(
    customerID: String,
    postalCode: String,
    countryCode: String
) -> String {
    "\(countryCode)-\(postalCode)-\(customerID)"
}
