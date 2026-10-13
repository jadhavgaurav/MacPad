import Foundation
import Testing
@testable import MacPadCore

@Suite struct TabWindowTests {
    @Test func aTabSnapshotKeepsItsWindow() throws {
        let window = UUID()
        let snapshot = TabSnapshot(windowID: window)
        let decoded = try JSONDecoder().decode(TabSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded.windowID == window)
    }

    @Test func aSnapshotFromBeforeTearOffHasNoWindow() throws {
        let fields = [
            "\"id\":\"\(UUID().uuidString)\"", #""text":"hi""#, #""encoding":"utf8""#, #""lineEnding":"lf""#,
            #""isDirty":false"#, #""selectionLocation":0"#, #""selectionLength":0"#, #""scrollOffsetY":0"#,
            #""zoom":1"#, #""previewVisible":false"#,
        ]
        let json = Data(("{" + fields.joined(separator: ",") + "}").utf8)
        let decoded = try JSONDecoder().decode(TabSnapshot.self, from: json)
        #expect(decoded.windowID == nil)
    }

    @Test func aManifestFromBeforeTearOffHasNoWindows() throws {
        let json = Data(#"{"schemaVersion":1,"tabIDs":[],"activeTabID":null}"#.utf8)
        let decoded = try JSONDecoder().decode(SessionManifest.self, from: json)
        #expect(decoded.windowIDs == nil)
    }

    @Test func theManifestKeepsItsWindows() throws {
        let windows = [UUID(), UUID()]
        let manifest = SessionManifest(tabIDs: [], activeTabID: nil, windowIDs: windows)
        let decoded = try JSONDecoder().decode(SessionManifest.self, from: JSONEncoder().encode(manifest))
        #expect(decoded.windowIDs == windows)
    }
}
