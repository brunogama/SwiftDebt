public enum BuiltInRuleCatalog {
    public static var all: [any DebtRule] {
        [
            ForceTryRule(),
            UncheckedSendableRule(),
            NonisolatedUnsafeActorMemberRule(),
            ActorStateAcrossAwaitRule(),
            ForceCastRule(),
            EmptyCatchRule(),
        ]
    }
}
