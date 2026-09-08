import Foundation

/// Button bitfield from HID report 251 on 2nd/3rd gen remotes (little-endian, 2 bytes).
struct ButtonSet: OptionSet, Hashable {
    let rawValue: UInt16

    init(rawValue: UInt16) { self.rawValue = rawValue }

    static let home = ButtonSet(rawValue: 0x0001)
    static let volumeUp = ButtonSet(rawValue: 0x0002)
    static let volumeDown = ButtonSet(rawValue: 0x0004)
    static let click = ButtonSet(rawValue: 0x0008)
    static let power = ButtonSet(rawValue: 0x0010)
    static let siri = ButtonSet(rawValue: 0x0020)
    static let back = ButtonSet(rawValue: 0x0040)
    static let mute = ButtonSet(rawValue: 0x0080)
    static let playPause = ButtonSet(rawValue: 0x0100)
    static let up = ButtonSet(rawValue: 0x0200)
    static let right = ButtonSet(rawValue: 0x0400)
    static let down = ButtonSet(rawValue: 0x0800)
    static let left = ButtonSet(rawValue: 0x1000)
    /// The clickpad's outer ring. A ring press reports `.click` too; it counts as a direction, not a click.
    static let ring: ButtonSet = [.up, .down, .left, .right]

    static let names: [(ButtonSet, String)] = [
        (.home, "TV"), (.volumeUp, "Vol+"), (.volumeDown, "Vol−"), (.click, "Click"), (.power, "Power"),
        (.siri, "Siri"), (.back, "Back"), (.mute, "Mute"), (.playPause, "Play"), (.up, "Up"),
        (.right, "Right"), (.down, "Down"), (.left, "Left"),
    ]

    var labels: [String] { ButtonSet.names.filter { contains($0.0) }.map(\.1) }

    /// Parses a raw input report. Returns nil for reports that are not the button report.
    init?(report: [UInt8]) {
        guard report.count >= 3, report[0] == 0xFB else { return nil }
        self.init(rawValue: UInt16(report[1]) | UInt16(report[2]) << 8)
    }
}

struct NearbyRemote: Identifiable, Equatable {
    let id: UUID
    var name: String?
    var rssi: Int
    var lastSeen: Date
    var address: String?
    var productID: UInt16?

    var title: String { name ?? address ?? "Apple Remote" }
    var isSiriRemote: Bool { productID == Remote.productID }

    /// Example manufacturer data for a 3rd gen remote, with a synthetic address:
    /// 4c00 07 0d 02 1503 02 020000000001 444543 → company, type 7, length, ?, product LE, ?, BD address, tail.
    static func parseManufacturerData(_ d: Data) -> (productID: UInt16, address: String)? {
        let b = [UInt8](d)
        guard b.count >= 14, b[0] == 0x4C, b[1] == 0x00, b[2] == 0x07 else { return nil }
        let pid = UInt16(b[5]) | UInt16(b[6]) << 8
        let addr = b[8..<14].map { String(format: "%02X", $0) }.joined(separator: ":")
        return (pid, addr)
    }
}

struct PairedRemote: Identifiable, Equatable {
    var id: String { address }
    let address: String
    var serial: String
    var isConnected: Bool
    var hidAttached: Bool
    var battery: Int?
    var charging: Bool?
    var firmware: String?
    var pressed: ButtonSet = []
}

enum Remote {
    static let vendorID = 0x004C
    static let productID: UInt16 = 0x0315
}

enum PairingState: Equatable {
    case idle
    case instructions(NearbyRemote)
    case connecting(NearbyRemote)
    case waitingForBond(serial: String)
    case attachingHID(serial: String)
    case done(serial: String)
    case failed(NearbyRemote, String)

    var isBusy: Bool {
        switch self {
        case .connecting, .waitingForBond, .attachingHID: return true
        default: return false
        }
    }
}
