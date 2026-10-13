import Testing
@testable import MacPadCore

@Suite struct ShortcutCatalogTests {
    @Test func everyEntryHasAnActionAndKeys() {
        for entry in ShortcutCatalog.all {
            #expect(!entry.action.isEmpty)
            #expect(!entry.keys.isEmpty)
        }
    }

    @Test func entriesAreUnique() {
        let ids = ShortcutCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func categoriesKeepTheirFirstAppearanceOrder() {
        #expect(ShortcutCatalog.categories.first == "File")
        #expect(Set(ShortcutCatalog.categories).count == ShortcutCatalog.categories.count)
    }

    @Test func searchMatchesActionCategoryAndKeys() {
        #expect(ShortcutCatalog.entries(matching: "").count == ShortcutCatalog.all.count)
        let cursors = ShortcutCatalog.entries(matching: "cursor")
        #expect(cursors.allSatisfy { $0.action.contains("cursor") || $0.category == "Multiple cursors" })
        #expect(ShortcutCatalog.entries(matching: "⌘D").contains { $0.action == "Select next occurrence" })
        #expect(ShortcutCatalog.entries(matching: "no such shortcut").isEmpty)
    }
}
