import Foundation

/// Physical key codes and modifier flags, independent of the current keyboard layout.
public struct HelperShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
    public static let command: UInt32 = 256
    public static let shift: UInt32 = 512
    public static let option: UInt32 = 2048
    public static let control: UInt32 = 4096
    public static let check = HelperShortcut(keyCode: 38, modifiers: control | option)
    public static let selectAndCheck = HelperShortcut(keyCode: 38, modifiers: control | option | shift)
    public static let keys: [(code: UInt32, label: String)] = [
        (0,"A"),(11,"B"),(8,"C"),(2,"D"),(14,"E"),(3,"F"),(5,"G"),(4,"H"),(34,"I"),(38,"J"),(40,"K"),(37,"L"),(46,"M"),
        (45,"N"),(31,"O"),(35,"P"),(12,"Q"),(15,"R"),(1,"S"),(17,"T"),(32,"U"),(9,"V"),(13,"W"),(7,"X"),(16,"Y"),(6,"Z"),
        (29,"0"),(18,"1"),(19,"2"),(20,"3"),(21,"4"),(23,"5"),(22,"6"),(26,"7"),(28,"8"),(25,"9")
    ]
    public var isValid: Bool {
        let allowed = Self.command | Self.shift | Self.option | Self.control
        if modifiers == Self.command, [0, 8, 9, 7, 6, 12, 13, 1, 3, 4, 46, 31, 35, 45].contains(keyCode) { return false }
        return Self.keys.contains { $0.code == keyCode } && modifiers & ~allowed == 0
            && modifiers & (Self.command | Self.control | Self.option) != 0
    }
    public var label: String {
        [(Self.control,"⌃"),(Self.option,"⌥"),(Self.shift,"⇧"),(Self.command,"⌘")]
            .filter { modifiers & $0.0 != 0 }.map(\.1).joined() + (Self.keys.first { $0.code == keyCode }?.label ?? "?")
    }
}
