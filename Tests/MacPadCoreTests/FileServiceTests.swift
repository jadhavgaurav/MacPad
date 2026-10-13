import Foundation
import Testing
@testable import MacPadCore

@Suite struct FileServiceTests {
    private func temporaryURL(_ name: String = "file.txt") -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }

    @Test func readsPlainUTF8() throws {
        let url = temporaryURL()
        try Data("h\u{E9}llo\nworld".utf8).write(to: url)
        let file = try FileService.read(url)
        #expect(file.text == "h\u{E9}llo\nworld")
        #expect(file.encoding == .utf8)
        #expect(file.lineEnding == .lf)
    }

    @Test func detectsAndStripsUTF8BOM() throws {
        let url = temporaryURL()
        try (Data([0xEF, 0xBB, 0xBF]) + Data("hi".utf8)).write(to: url)
        let file = try FileService.read(url)
        #expect(file.text == "hi")
        #expect(file.encoding == .utf8BOM)
    }

    @Test func detectsUTF16LE() throws {
        let url = temporaryURL()
        try (Data([0xFF, 0xFE]) + "hi".data(using: .utf16LittleEndian)!).write(to: url)
        let file = try FileService.read(url)
        #expect(file.text == "hi")
        #expect(file.encoding == .utf16LE)
    }

    @Test func detectsUTF16BE() throws {
        let url = temporaryURL()
        try (Data([0xFE, 0xFF]) + "hi".data(using: .utf16BigEndian)!).write(to: url)
        let file = try FileService.read(url)
        #expect(file.text == "hi")
        #expect(file.encoding == .utf16BE)
    }

    @Test func fallsBackToWindows1252ForInvalidUTF8() throws {
        let url = temporaryURL()
        try Data([0x63, 0x61, 0x66, 0xE9]).write(to: url)
        let file = try FileService.read(url)
        #expect(file.text == "caf\u{E9}")
        #expect(file.encoding == .windows1252)
    }

    @Test func emptyFileIsEmptyUTF8() throws {
        let url = temporaryURL()
        try Data().write(to: url)
        let file = try FileService.read(url)
        #expect(file.text.isEmpty)
        #expect(file.encoding == .utf8)
    }

    @Test func normalizesCRLFOnReadAndRemembersIt() throws {
        let url = temporaryURL()
        try Data("a\r\nb\r\n".utf8).write(to: url)
        let file = try FileService.read(url)
        #expect(file.text == "a\nb\n")
        #expect(file.lineEnding == .crlf)
    }

    @Test func roundTripPreservesEncodingAndLineEnding() throws {
        let url = temporaryURL()
        try FileService.write("a\nb", to: url, encoding: .utf16LE, lineEnding: .crlf)
        let file = try FileService.read(url)
        #expect(file.text == "a\nb")
        #expect(file.encoding == .utf16LE)
        #expect(file.lineEnding == .crlf)
    }

    @Test func writesBOMForUTF8BOM() throws {
        let url = temporaryURL()
        try FileService.write("x", to: url, encoding: .utf8BOM, lineEnding: .lf)
        #expect(try Data(contentsOf: url) == Data([0xEF, 0xBB, 0xBF, 0x78]))
    }

    @Test func rejectsCharactersTheEncodingCannotHold() {
        let url = temporaryURL()
        #expect(throws: FileServiceError.self) {
            try FileService.write("\u{4F60}", to: url, encoding: .windows1252, lineEnding: .lf)
        }
    }

    @Test func missingFileThrowsFileNotFound() {
        let url = temporaryURL("missing.txt")
        #expect(throws: FileServiceError.fileNotFound(url)) { try FileService.read(url) }
    }

    @Test func forcedEncodingOverridesDetection() throws {
        let url = temporaryURL()
        try Data([0x63, 0x61, 0x66, 0xC3, 0xA9]).write(to: url)
        let file = try FileService.read(url, as: .windows1252)
        #expect(file.encoding == .windows1252)
        #expect(file.text == "caf\u{C3}\u{A9}")
    }

    @Test func errorsHaveReadableDescriptions() {
        let url = URL(fileURLWithPath: "/tmp/notes.txt")
        #expect(FileServiceError.fileNotFound(url).errorDescription?.contains("notes.txt") == true)
    }

    @Test func readOnlyFileIsNotWritable() throws {
        let url = temporaryURL()
        try Data("locked".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        #expect(FileService.isWritable(url) == false)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        #expect(FileService.isWritable(url))
    }

    @Test func missingFileCountsAsWritable() {
        #expect(FileService.isWritable(temporaryURL("new.txt")))
    }
}
