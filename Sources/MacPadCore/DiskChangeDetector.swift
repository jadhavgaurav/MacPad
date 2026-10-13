import Foundation

/// What to do with a tab whose file may have changed on disk.
public enum DiskChangeDecision: Equatable, Sendable {
    /// Nothing to do.
    case unchanged
    /// The file changed and the tab has no unsaved edits, so reload it silently.
    case reload
    /// The file changed and the tab has unsaved edits, so ask the user.
    case conflict
    /// The file no longer exists at its path.
    case missing
}

public enum DiskChangeDetector {
    /// Modification times closer than this are treated as the same write.
    public static let tolerance: TimeInterval = 0.5

    public static func decide(known: Date?, current: Date?, isDirty: Bool) -> DiskChangeDecision {
        guard let current else { return .missing }
        if let known, abs(current.timeIntervalSince(known)) <= tolerance { return .unchanged }
        return isDirty ? .conflict : .reload
    }
}
