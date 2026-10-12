import Foundation

/// Debounces tab saves so typing never blocks, and flushes everything on quit.
public actor SessionCoordinator {
    private let store: SessionStore
    private let delay: Duration
    private let onError: @Sendable (Error) -> Void
    private var pending: [UUID: (snapshot: TabSnapshot, task: Task<Void, Never>)] = [:]

    public init(
        store: SessionStore,
        delay: Duration = .milliseconds(300),
        onError: @escaping @Sendable (Error) -> Void = { _ in }
    ) {
        self.store = store
        self.delay = delay
        self.onError = onError
    }

    /// Replaces any pending save for this tab and writes it after the debounce delay.
    public func schedule(_ snapshot: TabSnapshot) {
        pending[snapshot.id]?.task.cancel()
        let id = snapshot.id
        let delay = self.delay
        let task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.write(id)
        }
        pending[id] = (snapshot, task)
    }

    public func saveManifest(_ manifest: SessionManifest) {
        do { try store.saveManifest(manifest) } catch { onError(error) }
    }

    /// Cancels any pending write and deletes the tab's session file.
    public func remove(_ id: UUID) {
        pending.removeValue(forKey: id)?.task.cancel()
        do { try store.remove(id) } catch { onError(error) }
    }

    /// Writes every pending snapshot immediately. Call before the app quits.
    public func flush() {
        let entries = pending
        pending.removeAll()
        for (_, entry) in entries {
            entry.task.cancel()
            do { try store.save(entry.snapshot) } catch { onError(error) }
        }
    }

    private func write(_ id: UUID) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        do { try store.save(entry.snapshot) } catch { onError(error) }
    }
}
