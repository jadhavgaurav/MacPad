import Foundation
import NotePadCore
import Observation

/// Live counts for the status bar. Large documents are counted off the main thread after a short pause.
@MainActor
@Observable
final class StatsModel {
    private(set) var stats = TextStats.empty
    private(set) var selectionStats: TextStats?
    private(set) var position = LineLocator.Position(line: 1, column: 1)

    static let synchronousLimit = 1_000_000

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var cachedText: TextStats?

    private struct Snapshot: Sendable {
        var stats: TextStats
        var selection: TextStats?
        var position: LineLocator.Position
    }

    func update(text: String, selection: NSRange, textChanged: Bool) {
        task?.cancel()
        let reuse = textChanged ? nil : cachedText
        if text.utf8.count <= Self.synchronousLimit {
            apply(Self.compute(text: text, selection: selection, reusing: reuse))
            return
        }
        task = Task { [text, selection] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .utility) {
                Self.compute(text: text, selection: selection, reusing: reuse)
            }.value
            guard !Task.isCancelled else { return }
            apply(result)
        }
    }

    private func apply(_ snapshot: Snapshot) {
        cachedText = snapshot.stats
        stats = snapshot.stats
        selectionStats = snapshot.selection
        position = snapshot.position
    }

    private nonisolated static func compute(text: String, selection: NSRange, reusing: TextStats?) -> Snapshot {
        let ns = text as NSString
        let clamped = NSRange(
            location: min(selection.location, ns.length),
            length: min(selection.length, max(0, ns.length - min(selection.location, ns.length)))
        )
        return Snapshot(
            stats: reusing ?? TextStats(text),
            selection: clamped.length > 0 ? TextStats(ns.substring(with: clamped)) : nil,
            position: LineLocator.position(at: clamped.location, in: text)
        )
    }
}
