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
push after cutover commit `0f724f4a69c3f0df5fe930a8c93205afbdf6ce8c`.
History through that commit is intentionally grandfathered.

GitHub Actions observes a push after GitHub has accepted it. A failing
`Push conventional commits` run reports a direct-push violation but
cannot reject that push. Configure a GitHub repository ruleset for protected
branches that requires pull requests and the `PR conventional commits`
and `Strict build and lint` status checks when pre-receive
enforcement is required.

---

## Local commit hooks

Install the repository's pre-commit and commit-msg hooks with
`prek install --prepare-hooks`. Run `prek run --all-files` to check the full
repository. The hook configuration uses strict Swift formatting, ShellCheck,
the shared pre-commit-hooks checks, and the commit-message trailer filter.
Generated benchmark evidence and managed agent files are excluded from
automatic whitespace changes.
