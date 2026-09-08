import Foundation

/// Serial numbers of remotes this Mac has seen as HID devices or paired through Surf.
/// IOBluetooth's paired list has no vendor/product for BLE devices, so this is how paired
/// remotes are told apart from other BLE peripherals: a paired remote's device name is its serial.
enum KnownRemotes {
    private static let key = "knownRemoteSerials"

    static var serials: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func remember(_ serial: String) {
        var s = serials
        guard s.insert(serial).inserted else { return }
        UserDefaults.standard.set(Array(s).sorted(), forKey: key)
    }

    /// Siri Remote serials look like C08S1E9K2330: 12 upper-case alphanumerics.
    static func looksLikeSerial(_ name: String) -> Bool {
        name.count == 12 && name.allSatisfy { $0.isUppercase || $0.isNumber }
    }
}
