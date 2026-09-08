import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// A physical button on the remote, in the order they sit on the body.
enum RemoteButton: String, CaseIterable, Codable, Identifiable {
    case click, up, right, down, left, back, tv, playPause, siri, volumeUp, volumeDown, mute, power

    var id: String { rawValue }

    var bit: ButtonSet {
        switch self {
        case .click: .click
        case .up: .up
        case .right: .right
        case .down: .down
        case .left: .left
        case .back: .back
        case .tv: .home
        case .playPause: .playPause
        case .siri: .siri
        case .volumeUp: .volumeUp
        case .volumeDown: .volumeDown
        case .mute: .mute
        case .power: .power
        }
    }

    var title: String {
        switch self {
        case .click: "Center press"
        case .up: "Ring up"
        case .right: "Ring right"
        case .down: "Ring down"
        case .left: "Ring left"
        case .back: "Back"
        case .tv: "TV"
        case .playPause: "Play/Pause"
        case .siri: "Siri"
        case .volumeUp: "Volume up"
        case .volumeDown: "Volume down"
        case .mute: "Mute"
        case .power: "Power"
        }
    }

    /// The media key macOS sees when this button is pressed, for the buttons it handles itself.
    var mediaKey: MediaKey? {
        switch self {
        case .playPause: .playPause
        case .volumeUp: .volumeUp
        case .volumeDown: .volumeDown
        case .mute: .mute
        default: nil
        }
    }

    /// macOS handles these itself once the remote is paired, unless Surf remaps them.
    var isSystem: Bool { mediaKey != nil }

    var defaultAction: ButtonAction { ButtonAction.defaults[self] ?? (isSystem ? .system : .none) }
}

/// Media keys as macOS numbers them (NX_KEYTYPE_*).
enum MediaKey: Int, Codable, Hashable, CaseIterable {
    case volumeUp = 0, volumeDown = 1, mute = 7, playPause = 16

    var title: String {
        switch self {
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute"
        case .playPause: "Play/Pause"
        }
    }
}

struct KeyCombo: Codable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt64 = 0  // CGEventFlags

    init(_ keyCode: Int, _ flags: CGEventFlags = []) {
        self.keyCode = UInt16(keyCode)
        self.modifiers = flags.rawValue & KeyCombo.modifierMask.rawValue
    }

    static let modifierMask: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]

    var flags: CGEventFlags { CGEventFlags(rawValue: modifiers) }

    var label: String {
        var s = ""
        if flags.contains(.maskControl) { s += "⌃" }
        if flags.contains(.maskAlternate) { s += "⌥" }
        if flags.contains(.maskShift) { s += "⇧" }
        if flags.contains(.maskCommand) { s += "⌘" }
        let key = KeyCombo.name(for: keyCode)
        return s.isEmpty || key.count == 1 ? s + key : s + " " + key
    }

    private static let names: [Int: String] = [
        kVK_UpArrow: "Up Arrow", kVK_DownArrow: "Down Arrow", kVK_LeftArrow: "Left Arrow", kVK_RightArrow: "Right Arrow",
        kVK_Return: "Return", kVK_Space: "Space", kVK_Escape: "Escape", kVK_Tab: "Tab",
        kVK_Delete: "Delete", kVK_ForwardDelete: "Forward Delete", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
        kVK_Home: "Home", kVK_End: "End",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
        kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
        kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
        kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
    ]

    static func name(for code: UInt16) -> String { names[Int(code)] ?? "Key \(code)" }
}

/// What a remote button does when pressed.
enum ButtonAction: Codable, Hashable {
    case none
    /// Leave it to macOS. Only meaningful for the media buttons.
    case system
    case click
    case dictation
    case missionControl
    case sleepDisplays
    case key(KeyCombo)
    case media(MediaKey)

    var title: String {
        switch self {
        case .none: "Do nothing"
        case .system: "What macOS does"
        case .media(let k): k.title
        case .click: "Click"
        case .dictation: "Dictate while held"
        case .missionControl: "Mission Control"
        case .sleepDisplays: "Sleep displays"
        case .key(let c): ButtonAction.named[c].map { "\($0) (\(c.label))" } ?? c.label
        }
    }

    /// Key combos with a friendlier name than their keys.
    private static let named: [KeyCombo: String] = [
        KeyCombo(kVK_ANSI_Q, [.maskControl, .maskCommand]): "Lock screen",
        KeyCombo(kVK_ANSI_LeftBracket, .maskCommand): "Back",
        KeyCombo(kVK_ANSI_RightBracket, .maskCommand): "Forward",
        KeyCombo(kVK_ANSI_W, .maskCommand): "Close window",
        KeyCombo(kVK_ANSI_F, [.maskControl, .maskCommand]): "Full screen",
        KeyCombo(kVK_Space, .maskCommand): "Spotlight",
    ]

    /// Choices offered in the picker, grouped; a divider separates groups.
    static let presets: [[ButtonAction]] = [
        [.none, .click, .dictation],
        [.missionControl, .sleepDisplays, .key(KeyCombo(kVK_ANSI_Q, [.maskControl, .maskCommand]))],
        [.media(.playPause), .media(.mute), .media(.volumeUp), .media(.volumeDown)],
        [.key(KeyCombo(kVK_UpArrow)), .key(KeyCombo(kVK_DownArrow)), .key(KeyCombo(kVK_LeftArrow)), .key(KeyCombo(kVK_RightArrow)),
         .key(KeyCombo(kVK_Return)), .key(KeyCombo(kVK_Space)), .key(KeyCombo(kVK_Escape)), .key(KeyCombo(kVK_Tab)),
         .key(KeyCombo(kVK_Delete)), .key(KeyCombo(kVK_PageUp)), .key(KeyCombo(kVK_PageDown))],
        [.key(KeyCombo(kVK_ANSI_LeftBracket, .maskCommand)), .key(KeyCombo(kVK_ANSI_RightBracket, .maskCommand)),
         .key(KeyCombo(kVK_ANSI_W, .maskCommand)), .key(KeyCombo(kVK_ANSI_F, [.maskControl, .maskCommand])),
         .key(KeyCombo(kVK_Space, .maskCommand))],
    ]

    static let defaults: [RemoteButton: ButtonAction] = [
        .click: .click,
        .up: .key(KeyCombo(kVK_UpArrow)), .down: .key(KeyCombo(kVK_DownArrow)),
        .left: .key(KeyCombo(kVK_LeftArrow)), .right: .key(KeyCombo(kVK_RightArrow)),
        .back: .key(KeyCombo(kVK_Escape)),
        .tv: .missionControl,
        .power: .sleepDisplays,
        .siri: .dictation,
        .playPause: .system, .mute: .system, .volumeUp: .system, .volumeDown: .system,
    ]

    static let defaultsKey = "buttonActions"

    static func load() -> [RemoteButton: ButtonAction] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode([RemoteButton: ButtonAction].self, from: data) else { return defaults }
        return defaults.merging(saved) { $1 }
    }

    static func save(_ actions: [RemoteButton: ButtonAction]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(actions), forKey: defaultsKey)
    }
}
