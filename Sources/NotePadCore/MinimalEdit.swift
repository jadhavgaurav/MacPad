import Foundation

/// The smallest single replacement that turns one string into another.
/// Replacing only the changed middle keeps NSTextView undo history, selection and scroll position intact.
public struct MinimalEdit: Equatable, Sendable {
    /// UTF-16 range in the old text to replace.
    public var range: NSRange
    public var replacement: String

    public var isNoOp: Bool { range.length == 0 && replacement.isEmpty }

    public init(from old: String, to new: String) {
        let oldNS = old as NSString
        let newNS = new as NSString
        let shortest = min(oldNS.length, newNS.length)

        var prefix = 0
        while prefix < shortest, oldNS.character(at: prefix) == newNS.character(at: prefix) { prefix += 1 }
        if prefix > 0, UTF16.isLeadSurrogate(oldNS.character(at: prefix - 1)) { prefix -= 1 }

        var suffix = 0
        while suffix < shortest - prefix,
              oldNS.character(at: oldNS.length - 1 - suffix) == newNS.character(at: newNS.length - 1 - suffix) {
            suffix += 1
        }
        if suffix > 0, UTF16.isTrailSurrogate(oldNS.character(at: oldNS.length - suffix)) { suffix -= 1 }

        range = NSRange(location: prefix, length: oldNS.length - prefix - suffix)
        replacement = newNS.substring(with: NSRange(location: prefix, length: newNS.length - prefix - suffix))
    }
}
