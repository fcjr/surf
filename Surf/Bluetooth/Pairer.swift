import CoreBluetooth
import Foundation
import os

/// Bonds a remote by connecting with CoreBluetooth and reading an authenticated characteristic.
/// Works only after the user has put the remote in pairing mode (Back + Volume Up); a remote
/// that still holds an old bond answers "Authentication is insufficient" and never pairs.
final class Pairer: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var onState: ((PairingState) -> Void)?

    private let log = Logger(subsystem: "com.leftshift.surf", category: "pairer")
    private var central: CBCentralManager!
    private var target: NearbyRemote?
    private var peripheral: CBPeripheral?
    private var serial: String?
    private var timeout: Timer?
    private var bondPoll: Timer?
    private let deviceInfo = CBUUID(string: "180A")
    private let battery = CBUUID(string: "180F")
    private let serialChar = CBUUID(string: "2A25")
    private let batteryLevel = CBUUID(string: "2A19")

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func pair(_ remote: NearbyRemote) {
        cancel()
        target = remote
        guard central.state == .poweredOn else { return fail("Bluetooth is off") }
        guard let p = central.retrievePeripherals(withIdentifiers: [remote.id]).first else {
            return fail("The remote is no longer in range")
        }
        peripheral = p
        p.delegate = self
        onState?(.connecting(remote))
        central.connect(p, options: nil)
        timeout = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { [weak self] _ in
            self?.fail("Timed out. Hold Back + Volume Up for 5 seconds and try again.")
        }
        log.info("connecting to \(remote.id)")
    }

    func cancel() {
        timeout?.invalidate()
        bondPoll?.invalidate()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        serial = nil
    }

    private func fail(_ message: String) {
        let t = target
        cancel()
        log.error("pairing failed: \(message)")
        if let t { onState?(.failed(t, message)) }
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ c: CBCentralManager) {}

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        log.info("connected")
        p.discoverServices([deviceInfo, battery])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        fail(error?.localizedDescription ?? "Could not connect")
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard peripheral != nil, serial == nil else { return }
        fail("The remote disconnected. Hold Back + Volume Up for 5 seconds and try again.")
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { return fail(error.localizedDescription) }
        for s in p.services ?? [] { p.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            if ch.uuid == serialChar { p.readValue(for: ch) }
            if ch.uuid == batteryLevel { p.setNotifyValue(true, for: ch) }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        if let error {
            let msg = error.localizedDescription
            let hint = msg.localizedCaseInsensitiveContains("authentication") || msg.localizedCaseInsensitiveContains("encryption")
                ? "The remote still remembers another host. Hold Back + Volume Up for 5 seconds, then try again."
                : msg
            return fail(hint)
        }
        guard ch.uuid == serialChar, let s = ch.value.flatMap({ String(data: $0, encoding: .utf8) }) else { return }
        serial = s
        onState?(.waitingForBond(serial: s))
        log.info("serial \(s); waiting for bond")
        bondPoll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.checkBond() }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        if let error, serial == nil {
            fail(error.localizedDescription.localizedCaseInsensitiveContains("authentication")
                 ? "The remote still remembers another host. Hold Back + Volume Up for 5 seconds, then try again."
                 : error.localizedDescription)
        }
    }

    private func checkBond() {
        guard let s = serial else { return }
        if PairedWatcher.hidSerials().contains(s) {
            log.info("HID attached for \(s)")
            KnownRemotes.remember(s)
            bondPoll?.invalidate()
            timeout?.invalidate()
            if let p = peripheral { central.cancelPeripheralConnection(p) }
            peripheral = nil
            onState?(.done(serial: s))
        } else if PairedWatcher.isBonded(serial: s) {
            KnownRemotes.remember(s)
            onState?(.attachingHID(serial: s))
        }
    }
}
