func select(_ value: Int) -> Int { value }
func select(_ value: String) -> Int { value.count }

#if FEATURE_A
    let selected = select(1)
#else
    let selected = select("one")
#endif
