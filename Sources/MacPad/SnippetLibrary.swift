import Foundation
import MacPadCore
import Observation

/// The user's own snippets, kept in step with `snippets.json`.
@MainActor
@Observable
final class SnippetLibrary {
    private(set) var userSnippets: [Snippet] = []
    /// Set when `snippets.json` exists but cannot be read. Saves are refused so the file is never overwritten.
    @ObservationIgnored private var unreadableURL: URL?
    @ObservationIgnored private let fileURL: URL?

    init(fileURL: URL? = try? SnippetStore.defaultURL()) {
        self.fileURL = fileURL
        guard let fileURL else { return }
        do {
            userSnippets = try SnippetStore.load(from: fileURL)
        } catch {
            unreadableURL = fileURL
        }
    }

    func add(name: String, body: String) throws {
        try persist(userSnippets + [Snippet(name: name, body: body)])
    }

    func remove(id: Snippet.ID) throws {
        try persist(userSnippets.filter { $0.id != id })
    }

    private func persist(_ snippets: [Snippet]) throws {
        if let unreadableURL { throw SnippetStoreError.unreadable(unreadableURL) }
        guard let fileURL else { throw SnippetStoreError.unavailable }
        try SnippetStore.save(snippets, to: fileURL)
        userSnippets = snippets
    }
}
