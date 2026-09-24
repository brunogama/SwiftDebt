# Release process

Merges to `main` run `.github/workflows/release.yml`. The workflow derives the
next semantic version from Conventional Commits, replaces every marked release
version, regenerates `CHANGELOG.md`, verifies the package, and commits that
state before it creates and pushes the immutable tag.

`tag-documentation.yml` audits every manually pushed `v*.*.*` tag. It applies
the tag version to all release markers in the runner and fails with the stale
file list when that would change the tagged source. It never moves a tag or
commits a correction after the tag has been created.

`pr-quality.yml` checks new pull request commits, runs strict formatter lint,
builds with compiler warnings treated as errors, and runs the tests.
`commit-history.yml` performs the same commit-subject check for every branch
push after cutover commit `15fa039b0cfb9f7fe3ac9891c64199e038e7fe6b`.
History through that commit is intentionally grandfathered.

GitHub Actions observes a push after GitHub has accepted it. A failing
`Push conventional commits` run reports a direct-push violation but
cannot reject that push. Configure a GitHub repository ruleset for protected
branches that requires pull requests and the `PR conventional commits`
and `Strict build and lint` status checks when pre-receive
enforcement is required.
