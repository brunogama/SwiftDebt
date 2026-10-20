extension CLIOptions {
    static let help = """
        OVERVIEW: SwiftDebt - Swift source metrics based on the SCMA paper.

        USAGE: swift-debt analyze [path] [options]
               swift-debt debt analyze [path] [options]
               swift-debt debt validate [path] --max-score SCORE [options]
               swift-debt compare BEFORE_JSON AFTER_JSON [--output PATH]
               swift-debt validate-improvement BEFORE_JSON AFTER_JSON [--threshold SCORE] \
        [--output PATH]
               swift-debt explain coverage [path] --lcov PATH [options]
               swift-debt performance-gate BASELINE_JSON CANDIDATE_JSON [options]
               swift-debt pipeline plan CONFIG_JSON
               swift-debt pipeline run CONFIG_JSON --artifacts NEW_DIRECTORY
               swift-debt --help
               swift-debt --version

        OPTIONS:
          --artifacts DIRECTORY          New directory for pipeline logs and report.json.
          --config PATH                  JSON configuration (default: <root>/.swift-debt.json).
          --format FORMAT                text, json, csv, html, diagnostics (default: text),
                                         plus debt-json, debt-markdown, debt-dot,
                                         debt-text, debt-compact, debtmap-json,
                                         debt-dashboard.
          --interactive-debt             Open ranked debt explorer when terminal supports it.
          --output PATH                  Write a report atomically instead of stdout.
          --profile-output PATH          Write machine-readable phase profiling JSON.
          --name NAME                    Performance budget name.
          --max-wall-clock-regression PERCENT
                                         Maximum accepted wall-clock regression.
          --max-peak-memory-regression PERCENT
                                         Maximum accepted peak-memory regression.
          --threshold SCORE              Required improvement for validate-improvement.
          --type-scope SCOPE             classes (paper scope) or nominals.
          --scoring MODE                 none (default), paper (literal), bounded (clamped),
                                         corrected (clamped, DC ratio = duplicated/total lines).
          --threshold METRIC=INTEGER     Override a diagnostic threshold; repeatable.
          --exclude RELATIVE_PATH        Exclude a relative path prefix; repeatable; no globs.
          --jobs INTEGER                 Bounded parallel parsing, 1...64 (default: CPU count, max \
        8).
          --max-file-bytes INTEGER       Maximum bytes accepted for each source file.
          --fail-on-violation            Exit 1 when configured thresholds are exceeded.
          --strict                       Exit 2 on any parse error instead of skipping that file.
          --manifest PATH                Explicit JSON source manifest (used by plugins).
          --lcov PATH                    LCOV input for explain coverage or debt evidence.
          --coverage PATH                Alias for --lcov in debt workflows.
          --debt-reference-time TIME     ISO-8601 reference time for Git-history evidence.
          --git-executable PATH          Absolute path to a Git executable (default: Git on PATH).
          --preset PRESET                Debt preset: strict, balanced, lenient.
          --aggregation MODE             Debt aggregation: none, file, aggregateOnly.
          --top N | --head N | --tail N  Limit ranked debt output deterministically.
          --min-score SCORE              Keep debt items with score at least SCORE.
          --min-priority PRIORITY        Keep debt items at least low, medium, high, critical.
          --category NAME                Keep a debt category; repeatable.
          --level LEVEL                  Keep callable, type, file, or module; repeatable.
          --max-score SCORE              Validate that no debt score exceeds SCORE.
          --quiet                        Suppress validation summary output.
          --stamp PATH                   Internal build-plugin completion marker.
          --                             Treat the remaining argument as a literal path.

        EXIT STATUS: 0 success; 1 metric, improvement, or required pipeline check failed; 2 \
        input/configuration/analysis error or incomplete pipeline evidence.
        Paper equations are experimental. Undefined scores are not replaced with a passing grade.
        """
}
