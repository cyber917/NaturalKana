import Foundation
import Testing
@testable import NaturalSuggestCore

struct HelperShortcutTests {
    @Test func defaultsAreDistinctAndSurviveSaving() throws {
        #expect(HelperShortcut.check.isValid)
        #expect(HelperShortcut.selectAndCheck.isValid)
        #expect(HelperShortcut.check != HelperShortcut.selectAndCheck)
        #expect(HelperShortcut.check.label == "⌃⌥J")
        #expect(HelperShortcut.selectAndCheck.label == "⌃⌥⇧J")
        let custom = HelperShortcut(keyCode: 40, modifiers: HelperShortcut.control | HelperShortcut.command)
        #expect(try JSONDecoder().decode(HelperShortcut.self, from: JSONEncoder().encode(custom)) == custom)
        #expect(custom.label == "⌃⌘K")
    }
    @Test func rejectsTypingKeysUnknownKeysAndCommonEditingShortcuts() {
        #expect(!HelperShortcut(keyCode: 38, modifiers: 0).isValid)
        #expect(!HelperShortcut(keyCode: 38, modifiers: HelperShortcut.shift).isValid)
        #expect(!HelperShortcut(keyCode: 999, modifiers: HelperShortcut.control).isValid)
        #expect(!HelperShortcut(keyCode: 38, modifiers: 1 << 30).isValid)
        for code: UInt32 in [0, 8, 9, 7, 6, 12, 13] {
            #expect(!HelperShortcut(keyCode: code, modifiers: HelperShortcut.command).isValid)
        }
    }
}
