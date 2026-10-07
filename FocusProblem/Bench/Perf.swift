import UIKit
import os

// MARK: - Bench configuration

/// Reads a setting from `BenchSettings` (bench script), falling back to the environment.
func appSetting(_ key: String) -> String? {
    BenchSettings.values[key] ?? ProcessInfo.processInfo.environment[key]
}

enum BenchConfig {
    /// `BENCH`: `scroll` (programmatic scroll round trips), `focus` (programmatic focus jumps) or `all`.
    static let mode = appSetting("BENCH").flatMap { $0 == "none" ? nil : $0 }
    /// Debug logs are disabled while benchmarking.
    static let verbose = mode == nil
}

func debugLog(_ message: @autoclosure () -> String) {
    if BenchConfig.verbose { print(message()) }
}

// MARK: - Perf metrics

/// Accumulates timings (also emitted as signposts, visible in Instruments under "FocusProblem/Perf")
/// and frame hitches measured with a display link.
final class Perf: NSObject {
    static let shared = Perf()

    struct Stat {
        var count = 0
        var total: Double = 0
        var max: Double = 0
    }

    private let signposter = OSSignposter(subsystem: "FocusProblem", category: "Perf")
    private var stats: [String: Stat] = [:]

    @discardableResult
    func measure<T>(_ name: StaticString, _ body: () -> T) -> T {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        let start = CACurrentMediaTime()
        let result = body()
        record("\(name)", ms: (CACurrentMediaTime() - start) * 1000)
        signposter.endInterval(name, state)
        return result
    }

    func record(_ name: String, ms: Double) {
        var stat = stats[name, default: Stat()]
        stat.count += 1
        stat.total += ms
        stat.max = Swift.max(stat.max, ms)
        stats[name] = stat
    }

    func increment(_ name: String) {
        record(name, ms: 0)
    }

    // MARK: Frames

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var startTimestamp: CFTimeInterval = 0
    private var frames = 0
    private var hitches = 0
    private var hitchTime: Double = 0
    private var worstFrame: Double = 0

    func start() {
        stats = [:]
        frames = 0
        hitches = 0
        hitchTime = 0
        worstFrame = 0
        lastTimestamp = 0
        startTimestamp = CACurrentMediaTime()
        link?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard lastTimestamp > 0 else { return }
        frames += 1
        let frame = link.timestamp - lastTimestamp
        let expected = link.duration
        worstFrame = Swift.max(worstFrame, frame * 1000)
        if frame > expected * 1.5 {
            hitches += 1
            hitchTime += (frame - expected) * 1000
        }
    }

    func stopAndReport(_ label: String) {
        link?.invalidate()
        link = nil
        let duration = CACurrentMediaTime() - startTimestamp
        var lines = [String(
            format: "📊 [%@] %.1fs frames=%d fps=%.1f hitches=%d hitchRatio=%.1fms/s worstFrame=%.1fms",
            label, duration, frames, Double(frames) / duration, hitches, hitchTime / duration, worstFrame
        )]
        for (name, stat) in stats.sorted(by: { $0.value.total > $1.value.total }) {
            lines.append(String(
                format: "📊 [%@]   %@ n=%d total=%.1fms avg=%.3fms max=%.2fms",
                label, name, stat.count, stat.total, stat.count > 0 ? stat.total / Double(stat.count) : 0, stat.max
            ))
        }
        print(lines.joined(separator: "\n"))
    }
}
