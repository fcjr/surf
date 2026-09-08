import CoreBluetooth
import Foundation
import os

/// Reads battery and firmware from remotes that are currently connected to the Mac.
/// Uses the system's existing link, so it does not disturb the HID connection.
final class RemoteProbe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    struct Reading { var serial: String?; var battery: Int?; var charging: Bool?; var firmware: String? }
    var onReading: ((Reading) -> Void)?

    private let log = Logger(subsystem: "com.leftshift.surf", category: "probe")
    private var central: CBCentralManager!
    private var readings: [UUID: Reading] = [:]
    private var pendingReads: [UUID: Int] = [:]
    private var timer: Timer?
    private let battery = CBUUID(string: "180F")
    private let deviceInfo = CBUUID(string: "180A")

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func start(interval: TimeInterval = 30) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.probe() }
    }

    func probe() {
        guard central.state == .poweredOn else { return }
        for p in central.retrieveConnectedPeripherals(withServices: [battery]) {
            p.delegate = self
            readings[p.identifier] = Reading()
            central.connect(p, options: nil)
        }
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn { probe() }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([deviceInfo, battery])
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { p.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        let wanted: Set<String> = ["2A25", "2A26", "2A19", "2A1A"]
        for ch in s.characteristics ?? [] where wanted.contains(ch.uuid.uuidString) {
            pendingReads[p.identifier, default: 0] += 1
            p.readValue(for: ch)
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        var r = readings[p.identifier] ?? Reading()
        if error == nil, let v = ch.value {
            switch ch.uuid.uuidString {
            case "2A25": r.serial = String(data: v, encoding: .utf8)
            case "2A26": r.firmware = String(data: v, encoding: .utf8)
            case "2A19": r.battery = v.first.map(Int.init)
            case "2A1A": r.charging = v.first.map { $0 == 0xAB || $0 == 0xBB }  // AB charging, BB plugged in, AF discharging
            default: break
            }
        }
        readings[p.identifier] = r
        pendingReads[p.identifier, default: 1] -= 1
        if pendingReads[p.identifier, default: 0] <= 0 {
            pendingReads[p.identifier] = nil
            if r.serial != nil { onReading?(r) }
            central.cancelPeripheralConnection(p)
        }
    }
}
