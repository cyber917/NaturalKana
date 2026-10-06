import Foundation

/// Only remembers text committed by this input session, never another field's history.
public struct RecentDraft: Sendable {
    private var committed = ""
    public init() {}
    public mutating func reset() { committed = "" }
    public mutating func recordCommit(_ text: String) {
        committed = String((committed + text).components(separatedBy: .newlines).last!.suffix(200))
    }
    public func text(hostPrefix: String?, composition: String) -> String {
        let prefix = hostPrefix ?? committed
        return String((prefix.components(separatedBy: .newlines).last! + composition).suffix(200))
    }
}
