import SwiftUI

struct PairedRow: View {
    let remote: PairedRemote
    let forget: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "appletvremote.gen4.fill")
                .font(.title2)
                .foregroundStyle(remote.isConnected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(remote.serial).font(.body.monospaced())
                HStack(spacing: 6) {
                    Text(remote.isConnected ? (remote.hidAttached ? "Connected" : "Connecting…") : "Not connected")
                    if let b = remote.battery {
                        Label("\(b)%", systemImage: remote.charging == true ? "battery.100.bolt" : batteryIcon(b))
                    }
                    if let f = remote.firmware { Text("fw \(f)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Forget…", action: forget)
                .controlSize(.small)
                .help("Opens Bluetooth settings; macOS has no API to unpair a BLE device")
        }
    }

    private func batteryIcon(_ level: Int) -> String {
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}

struct NearbyRow: View {
    let remote: NearbyRemote
    let disabled: Bool
    let pair: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "appletvremote.gen4")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(remote.title).font(.body.monospaced())
                HStack(spacing: 6) {
                    Text(remote.isSiriRemote ? "Siri Remote" : "Apple remote")
                    Image(systemName: signalIcon)
                    Text("\(remote.rssi) dBm")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Pair", action: pair).controlSize(.small).disabled(disabled)
        }
    }

    private var signalIcon: String {
        switch remote.rssi {
        case ..<(-80): return "cellularbars"  // weakest rendering, SF renders 0 bars via variable value below
        default: return "wifi"
        }
    }
}
