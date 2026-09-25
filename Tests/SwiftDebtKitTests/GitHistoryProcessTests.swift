import Testing

@testable import SwiftDebtKit

@Suite("Git process environment")
struct GitHistoryProcessTests {
    @Test("Repository overrides are cleared while Git configuration remains available")
    func isolatesRepositoryOverrides() {
        let inherited = [
            "PATH": "/custom/git/bin:/usr/bin",
            "GIT_DIR": "/wrong/repository",
            "GIT_WORK_TREE": "/wrong/worktree",
            "GIT_IMPLICIT_WORK_TREE": "0",
            "GIT_CONFIG_GLOBAL": "/custom/gitconfig",
            "GIT_TRACE": "1",
        ]

        let environment = GitHistorySubprocessRunner.repositoryScopedEnvironment(inherited)

        #expect(environment["PATH"] == "/custom/git/bin:/usr/bin")
        #expect(environment["GIT_DIR"] == nil)
        #expect(environment["GIT_WORK_TREE"] == nil)
        #expect(environment["GIT_IMPLICIT_WORK_TREE"] == nil)
        #expect(environment["GIT_CONFIG_GLOBAL"] == "/custom/gitconfig")
        #expect(environment["GIT_TRACE"] == "1")
    }
}
