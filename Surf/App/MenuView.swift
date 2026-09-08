import CoreBluetooth
import SwiftUI

struct MenuView: View {
    @Environment(RemoteStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 12) {
            if store.bluetoothState != .poweredOn && store.bluetoothState != .unknown {
                Label("Bluetooth is off", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            section("Paired") {
                if store.paired.isEmpty {
                    Text("No remotes paired with this Mac.").foregroundStyle(.secondary)
                }
                ForEach(store.paired) { r in
                    PairedRow(remote: r) { store.openBluetoothSettings() }
                }
            }

            section("Nearby") {
                if store.nearby.isEmpty {
                    Text("Hold Back + Volume Up on a remote for 5 seconds to make it appear.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(store.nearby) { r in
                    NearbyRow(remote: r, disabled: store.pairing.isBusy) { store.beginPairing(r) }
                }
            }

            if store.pairing != .idle {
                PairingPanel()
            }

            section("Mouse") {
                Toggle("Touch surface moves the pointer", isOn: $store.mouseEnabled).toggleStyle(.checkbox)
                if store.mouseEnabled {
                    HStack {
                        Text("Speed").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $store.mouseSensitivity, in: 0.3...3)
                    }
                    if !store.accessibilityTrusted {
                        HStack {
                            Label("Needs Accessibility permission", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("Open Settings") { store.requestAccessibility() }.controlSize(.small)
                        }
                    } else if !store.touchSurfaceAvailable {
                        Text("No connected remote touch surface yet.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("One finger moves, two fingers scroll, press the surface to click.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            section("Dictation") {
                Toggle("Hold Siri to dictate", isOn: $store.dictationEnabled).toggleStyle(.checkbox)
                if store.dictationEnabled {
                    DictationStatus()
                }
            }

            section("Buttons") {
                HStack {
                    Text("Choose what each button does.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Customize…") {
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: "buttons")
                    }.controlSize(.small)
                }
            }

            Divider()
            HStack {
                Toggle("Launch at login", isOn: $store.launchAtLogin).toggleStyle(.checkbox)
                Spacer()
                Button("Updates…") { Updater.checkForUpdates() }.controlSize(.small)
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
            content()
        }
    }
}

struct PairingPanel: View {
    @Environment(RemoteStore.self) private var store

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                switch store.pairing {
                case .idle:
                    EmptyView()
                case .instructions(let r):
                    Text("Pair \(r.title)").font(.headline)
                    Text("1. Put the Apple TV to sleep so it does not take the remote back.\n2. Hold Back + Volume Up on the remote for 5 seconds.\n3. Click Connect.")
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Cancel") { store.cancelPairing() }
                        Spacer()
                        Button("Connect") { store.connect(r) }.keyboardShortcut(.defaultAction)
                    }
                case .connecting(let r):
                    progress("Connecting to \(r.title)…")
                case .waitingForBond(let s):
                    progress("Pairing \(s)…")
                case .attachingHID(let s):
                    progress("Paired \(s), finishing setup…")
                case .done(let s):
                    Label("\(s) is paired. Volume buttons control this Mac now.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Done") { store.cancelPairing() }.keyboardShortcut(.defaultAction)
                case .failed(let r, let message):
                    Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    HStack {
                        Button("Cancel") { store.cancelPairing() }
                        Spacer()
                        Button("Try again") { store.connect(r) }.keyboardShortcut(.defaultAction)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func progress(_ text: String) -> some View {
        HStack {
            ProgressView().controlSize(.small)
            Text(text)
            Spacer()
            Button("Cancel") { store.cancelPairing() }
        }
    }
}


struct DictationStatus: View {
    @Environment(RemoteStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch store.modelState {
            case .notLoaded, .loading:
                HStack { ProgressView().controlSize(.small); Text("Downloading speech model (first time only)…") }
            case .loaded:
                EmptyView()
            case .failed(let m):
                HStack {
                    Label("Model failed: \(m)", systemImage: "xmark.octagon").foregroundStyle(.red).lineLimit(2)
                    Spacer()
                    Button("Retry") { store.retryModel() }.controlSize(.small)
                }
            }
            if !store.accessibilityTrusted {
                Text("Without Accessibility permission, text goes to the clipboard instead of the focused app.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
