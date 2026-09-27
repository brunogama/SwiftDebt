import Foundation

package enum LifecycleIntroductionProfileOutput {
    package static func prepare(
        _ profileURL: URL,
        artifactURL: URL,
        repositoryURL: URL
    ) throws {
        let profile = try validatedURL(
            profileURL,
            artifactURL: artifactURL,
            repositoryURL: repositoryURL
        )
        if FileManager.default.fileExists(atPath: profile.path) {
            try FileManager.default.removeItem(at: profile)
        }
    }

    package static func write(
        _ profile: LifecycleIntroductionProfile,
        to profileURL: URL,
        artifactURL: URL,
        repositoryURL: URL
    ) throws {
        let output = try validatedURL(
            profileURL,
            artifactURL: artifactURL,
            repositoryURL: repositoryURL
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(profile)
        data.append(0x0A)
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: output, options: .atomic)
    }

    private static func validatedURL(
        _ profileURL: URL,
        artifactURL: URL,
        repositoryURL: URL
    ) throws -> URL {
        let profile = LifecycleIntroductionOutputPath.canonical(profileURL)
        let artifact = LifecycleIntroductionOutputPath.canonical(artifactURL)
        let lock = LifecycleIntroductionOutputPath.canonical(
            URL(fileURLWithPath: artifactURL.path + ".lock")
        )
        guard !LifecycleIntroductionOutputPath.hasSameIdentity(profile, artifact),
            !LifecycleIntroductionOutputPath.hasSameIdentity(profile, lock),
            profile.pathExtension.lowercased() != "swift",
            !LifecycleIntroductionOutputPath.contains(profile, within: repositoryURL)
        else {
            throw WorkspaceError(
                "Introduction profile output must be outside the repository and must not replace the lifecycle artifact, lock, or a Swift source"
            )
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: profile.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        {
            throw WorkspaceError("Introduction profile output path is a directory: \(profile.path)")
        }
        return profile
    }
}
