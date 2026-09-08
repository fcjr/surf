import CoreBluetooth
import Foundation
import os

/// Scans for remotes advertising the HID service. A remote advertises when it is in pairing
/// mode and also when it has lost its host and is trying to reconnect; the two look the same.
final class RemoteScanner: NSObject, CBCentralManagerDelegate {
    var onUpdate: (([NearbyRemote]) -> Void)?
    var onState: ((CBManagerState) -> Void)?

    private let log = Logger(subsystem: "com.leftshift.surf", category: "scanner")
    private var central: CBCentralManager!
    private var found: [UUID: NearbyRemote] = [:]
    private var expiry: Timer?
    private let hidService = CBUUID(string: "1812")
    private let staleAfter: TimeInterval = 6

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        expiry = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.expire() }
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        onState?(c.state)
        if c.state == .poweredOn {
            c.scanForPeripherals(withServices: [hidService], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            log.info("scanning")
        } else {
            found.removeAll()
            onUpdate?([])
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        var r = found[p.identifier] ?? NearbyRemote(id: p.identifier, name: nil, rssi: rssi.intValue, lastSeen: Date())
        r.rssi = rssi.intValue
        r.lastSeen = Date()
        r.name = p.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? r.name
        if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
           let parsed = NearbyRemote.parseManufacturerData(mfg) {
            r.productID = parsed.productID
            r.address = parsed.address
        }
        if found[p.identifier] == nil { log.info("found \(p.identifier) \(r.title)") }
        found[p.identifier] = r
        publish()
    }

    private func expire() {
        let cutoff = Date().addingTimeInterval(-staleAfter)
        let before = found.count
        found = found.filter { $0.value.lastSeen > cutoff }
        if found.count != before { publish() }
    }

    private func publish() {
        onUpdate?(found.values.sorted { $0.rssi > $1.rssi })
    }
}
