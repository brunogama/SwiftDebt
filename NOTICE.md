# Attribution and implementation provenance

The metric categories and compatibility equations are based on the user-supplied paper **SCMA: A Lightweight Tool to Analyze Swift Projects**, by Fazle Rabbi, Syeda Sumbul Hossain, and Mir Mohammad Samsul Arefin. See docs/PAPER_MAPPING.md for source positions and explicit differences.

SwiftDebt is an independent implementation, not the authors' original tool and not an affiliated product. The original paper, original tool source, and Lizard code are not redistributed here. The native clone engine does not claim Lizard equivalence.

The package declares an external dependency on the official SwiftSyntax repository, exact version 602.0.0. That dependency retains its own licensing/attribution requirements and is resolved separately by SwiftPM; none of its source or binaries is bundled in this archive.

The implementation is supplied as source for review and adaptation. Metric limits and experimental scores do not establish correctness, security, architectural conformance, or measured product quality. Validate the normal build and Xcode adapter on the target toolchain before release.
