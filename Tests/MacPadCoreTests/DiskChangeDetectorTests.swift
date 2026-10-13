import Foundation
import Testing
@testable import MacPadCore

@Suite struct DiskChangeDetectorTests {
    private let known = Date(timeIntervalSince1970: 1_000)

    @Test func sameDateIsUnchanged() {
        #expect(DiskChangeDetector.decide(known: known, current: known, isDirty: false) == .unchanged)
    }

    @Test func tinyDifferenceWithinToleranceIsUnchanged() {
        #expect(DiskChangeDetector.decide(known: known, current: known.addingTimeInterval(0.3), isDirty: true) == .unchanged)
    }

    @Test func newerFileReloadsWhenClean() {
        #expect(DiskChangeDetector.decide(known: known, current: known.addingTimeInterval(5), isDirty: false) == .reload)
    }

    @Test func newerFileConflictsWhenDirty() {
        #expect(DiskChangeDetector.decide(known: known, current: known.addingTimeInterval(5), isDirty: true) == .conflict)
    }

    @Test func olderFileIsTreatedAsAChange() {
        #expect(DiskChangeDetector.decide(known: known, current: known.addingTimeInterval(-5), isDirty: false) == .reload)
    }

    @Test func missingFileIsMissingRegardlessOfDirty() {
        #expect(DiskChangeDetector.decide(known: known, current: nil, isDirty: false) == .missing)
        #expect(DiskChangeDetector.decide(known: known, current: nil, isDirty: true) == .missing)
    }

    @Test func unknownKnownDateTreatsAnyFileAsChanged() {
        #expect(DiskChangeDetector.decide(known: nil, current: known, isDirty: false) == .reload)
    }
}
