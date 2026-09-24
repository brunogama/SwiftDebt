import Dispatch
import Foundation
import SwiftDebtCore

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

public struct AnalysisProfile: Codable, Sendable {
    public let schemaVersion: Int
    public let measurements: [String]
    public let disabledOverhead: ProfilingDisabledOverhead
    public let phases: [ProfiledAnalysisPhase]

    public static let disabledInstrumentationOverhead = ProfilingDisabledOverhead(
        phaseBoundaryChecks: 24,
        clockReads: 0,
        peakMemoryReads: 0,
        perSourceWork: 0,
        note: "Disabled profiling allocates no profiler and performs at most 24 optional phase-boundary checks."
    )
}

public struct ProfilingDisabledOverhead: Codable, Sendable {
    public let phaseBoundaryChecks: Int
    public let clockReads: Int
    public let peakMemoryReads: Int
    public let perSourceWork: Int
    public let note: String
}

public struct ProfiledAnalysisPhase: Codable, Sendable {
    public let phase: AnalysisPhase
    public let elapsedNanoseconds: UInt64
    public let peakResidentMemoryBytes: UInt64?
}

// Mutable phase state is accessed only through lock.withLock.
final class AnalysisProfiler: AnalysisPhaseSink, @unchecked Sendable {
    private struct ActivePhase {
        let startedAtNanoseconds: UInt64
    }

    private var active: [AnalysisPhase: ActivePhase] = [:]
    private var elapsed: [AnalysisPhase: UInt64] = [:]
    private let lock = NSLock()

    func begin(_ phase: AnalysisPhase) {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.withLock {
            active[phase] = ActivePhase(startedAtNanoseconds: now)
        }
    }

    func end(_ phase: AnalysisPhase) {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.withLock {
            guard let started = active.removeValue(forKey: phase) else { return }
            elapsed[phase, default: 0] += now - started.startedAtNanoseconds
        }
    }

    func profile() -> AnalysisProfile {
        lock.withLock {
            let peak = peakResidentMemoryBytes()
            let phases = AnalysisPhase.allCases.compactMap { phase -> ProfiledAnalysisPhase? in
                guard let elapsedNanoseconds = elapsed[phase] else { return nil }
                return ProfiledAnalysisPhase(
                    phase: phase,
                    elapsedNanoseconds: elapsedNanoseconds,
                    peakResidentMemoryBytes: peak
                )
            }
            return AnalysisProfile(
                schemaVersion: 1,
                measurements: ["wall-clock-nanoseconds", "peak-resident-memory-bytes"],
                disabledOverhead: AnalysisProfile.disabledInstrumentationOverhead,
                phases: phases
            )
        }
    }
}

private func peakResidentMemoryBytes() -> UInt64? {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
    #if canImport(Darwin)
        return UInt64(usage.ru_maxrss)
    #else
        return UInt64(usage.ru_maxrss) * 1024
    #endif
}

extension NSLock {
    fileprivate func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
