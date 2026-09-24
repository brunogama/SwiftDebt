public enum BuiltInRuleCatalog {
    public static var all: [any DebtRule] {
        [
            ForceTryRule(),
            UncheckedSendableRule(),
            NonisolatedUnsafeActorMemberRule(),
            ForceCastRule(),
            EmptyCatchRule(),
        ]
    }
}
