import Foundation

func analyzeLifecycle(_ fixture: TemporaryLifecycleGitRepository) throws -> LifecycleCLIRunResult {
    try runLifecycleCLI([
        "analyze", fixture.repository.path,
        "--format", "json",
        "--lifecycle-artifact", fixture.artifact.path,
        "--jobs", "2",
    ])
}

func explainLifecycle(
    _ findingID: String,
    fixture: TemporaryLifecycleGitRepository
) throws -> LifecycleCLIRunResult {
    try runLifecycleCLI([
        "lifecycle", "explain", fixture.artifact.path, findingID,
    ])
}
