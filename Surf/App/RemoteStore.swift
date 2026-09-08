import AppKit
import AVFoundation
import CoreBluetooth
import Foundation
import Observation
import ServiceManagement

@Observable
@MainActor
final class RemoteStore {
    var nearby: [NearbyRemote] = []
    var paired: [PairedRemote] = []
    var pairing: PairingState = .idle
    var bluetoothState: CBManagerState = .unknown
    var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet { setLaunchAtLogin(launchAtLogin) }
    }
    var mouseEnabled: Bool = UserDefaults.standard.bool(forKey: "mouseEnabled") {
        didSet {
            UserDefaults.standard.set(mouseEnabled, forKey: "mouseEnabled")
            applyMouseSetting()
        }
    }
    var mouseSensitivity: Double = UserDefaults.standard.object(forKey: "mouseSensitivity") as? Double ?? 1.0 {
        didSet {
            UserDefaults.standard.set(mouseSensitivity, forKey: "mouseSensitivity")
            mouse.sensitivity = mouseSensitivity
        }
    }
    var accessibilityTrusted = MouseController.isTrusted {
        didSet { if accessibilityTrusted { mediaTap.start() } }
    }
    var touchSurfaceAvailable = false
    var dictationEnabled: Bool = UserDefaults.standard.bool(forKey: "dictationEnabled") {
        didSet {
            UserDefaults.standard.set(dictationEnabled, forKey: "dictationEnabled")
            applyDictationSetting()
        }
    }
    var dictationState: DictationController.State = .idle
    var modelState: DictationController.ModelState = .notLoaded
    var lastTranscript = ""
    var buttonActions: [RemoteButton: ButtonAction] = ButtonAction.load() {
        didSet { ButtonAction.save(buttonActions) }
    }

    private let scanner = RemoteScanner()
    private let watcher = PairedWatcher()
    private let hid = RemoteHID()
    private let pairer = Pairer()
    private let probe = RemoteProbe()
    private let touch = TouchSurface()
    private let mouse = MouseController()
    private let runner = ActionRunner()
    private let heldActions = HeldActions()
    private let mediaTap = MediaKeyTap()
    private var effective: [String: ButtonSet] = [:]  // per remote, after ring/click disambiguation
    private let dictation = DictationController()
    private var trustTimer: Timer?

    init() {
        scanner.onState = { [weak self] s in self?.bluetoothState = s }
        scanner.onUpdate = { [weak self] list in
            guard let self else { return }
            // a remote that is already paired keeps advertising while disconnected; keep it out of Nearby
            let pairedAddresses = Set(self.paired.map(\.address).map { $0.replacingOccurrences(of: "-", with: ":").uppercased() })
            self.nearby = list.filter { r in r.address.map { !pairedAddresses.contains($0) } ?? true }
        }
        watcher.onUpdate = { [weak self] list in
            guard let self else { return }
            let old = Dictionary(uniqueKeysWithValues: self.paired.map { ($0.serial, $0) })
            let connected = Set(list.filter { $0.isConnected && $0.hidAttached }.map(\.serial))
            self.heldActions.retainConnected(connected)
            self.effective = self.effective.filter { connected.contains($0.key) }
            self.paired = list.map { var r = $0
                if let o = old[r.serial] { r.battery = o.battery; r.charging = o.charging; r.firmware = o.firmware; r.pressed = o.pressed }
                if !connected.contains(r.serial) { r.pressed = [] }
                return r
            }
            self.probe.probe()
            // the touch surface registers a moment after the HID connection comes up
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.rescanTouch() }
        }
        hid.onButtons = { [weak self] serial, buttons in
            guard let self, let i = self.paired.firstIndex(where: { $0.serial == serial }) else { return }
            self.paired[i].pressed = buttons
            self.dispatch(serial: serial, buttons)
        }
        mediaTap.isRemapped = { [weak self] key in
            guard let self, self.paired.contains(where: \.isConnected),
                  let b = RemoteButton.allCases.first(where: { $0.mediaKey == key }) else { return false }
            return (self.buttonActions[b] ?? .system) != .system
        }
        mediaTap.start()
        heldActions.perform = { [weak self] action, down in
            self?.runner.perform(action, down: down)
        }
        runner.click = { [weak self] down in
            guard let self, !down || self.mouseEnabled else { return }
            self.mouse.click(down: down)
        }
        runner.dictation = { [weak self] down in
            guard let self else { return }
            if down { self.dictation.press() } else { self.dictation.release() }
        }
        touch?.onFrame = { [weak self] contacts in
            guard let self, self.mouseEnabled else { return }
            self.mouse.handle(contacts)
        }
        pairer.onState = { [weak self] s in
            self?.pairing = s
            if case .done = s { self?.watcher.refresh() }
        }
        probe.onReading = { [weak self] r in
            guard let self, let i = self.paired.firstIndex(where: { $0.serial == r.serial }) else { return }
            self.paired[i].battery = r.battery
            self.paired[i].charging = r.charging
            self.paired[i].firmware = r.firmware
        }
        watcher.start()
        probe.start()
        mouse.sensitivity = mouseSensitivity
        applyMouseSetting()
        dictation.onStateChange = { [weak self] s in self?.dictationState = s }
        dictation.onModelStateChange = { [weak self] s in self?.modelState = s }
        dictation.onTranscript = { [weak self] t in self?.lastTranscript = t }
        applyDictationSetting()
    }

    /// Runs the configured action for every button that changed. A ring press reports `.click`
    /// too; it counts as a direction unless a center press was already held, so a drag that
    /// wanders onto the rim keeps dragging.
    private func dispatch(serial: String, _ buttons: ButtonSet) {
        let was = effective[serial] ?? []
        var now = buttons
        if now.contains(.click) {
            if was.contains(.click) { now.subtract(.ring) } else if !now.isDisjoint(with: .ring) { now.remove(.click) }
        }
        effective[serial] = now
        for b in RemoteButton.allCases where was.contains(b.bit) != now.contains(b.bit) {
            let action = buttonActions[b] ?? b.defaultAction
            let down = now.contains(b.bit)
            let performed = heldActions.update(remote: serial, button: b, action: action, down: down)
            if let performed, performed != .system, let key = b.mediaKey {
                mediaTap.claim(key, down: down)
            }
        }
    }

    func resetButtonActions() { buttonActions = ButtonAction.defaults }

    func retryModel() { dictation.preload() }

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    private func applyDictationSetting() {
        dictation.setEnabled(dictationEnabled)
        guard dictationEnabled else { return }
        dictation.preload()
        requestMicrophone()
    }

    func requestAccessibility() {
        MouseController.requestTrust()
        MouseController.openAccessibilitySettings()
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            Task { @MainActor in
                guard let self else { return t.invalidate() }
                self.accessibilityTrusted = MouseController.isTrusted
                if self.accessibilityTrusted { t.invalidate() }
            }
        }
    }

    private func applyMouseSetting() {
        accessibilityTrusted = MouseController.isTrusted
        if mouseEnabled {
            if !accessibilityTrusted { MouseController.requestTrust() }
            rescanTouch()
        } else {
            mouse.click(down: false)
            touch?.stopAll()
            touchSurfaceAvailable = false
        }
    }

    private func rescanTouch() {
        guard mouseEnabled, let touch else { return }
        touch.rescan()
        touchSurfaceAvailable = touch.deviceCount > 0
    }

    func beginPairing(_ r: NearbyRemote) { pairing = .instructions(r) }

    func connect(_ r: NearbyRemote) { pairer.pair(r) }

    func cancelPairing() {
        pairer.cancel()
        pairing = .idle
    }

    func openBluetoothSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
