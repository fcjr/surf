import Foundation
import IOBluetooth
import IOKit.hid

/// Joins IOBluetooth's paired-device list with IOHIDManager to list remotes bonded to this Mac.
final class PairedWatcher {
    var onUpdate: (([PairedRemote]) -> Void)?
    private var timer: Timer?
    private var last: [PairedRemote] = []

    func start(interval: TimeInterval = 2) {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let hidSerials = PairedWatcher.hidSerials()
        hidSerials.forEach(KnownRemotes.remember)
        let known = KnownRemotes.serials
        var list: [PairedRemote] = []
        for d in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] {
            guard d.deviceClassMajor == 0, let name = d.name, known.contains(name) else { continue }
            list.append(PairedRemote(address: d.addressString ?? name, serial: name,
                                     isConnected: d.isConnected(), hidAttached: hidSerials.contains(name)))
        }
        list.sort { $0.serial < $1.serial }
        if list != last {
            last = list
            onUpdate?(list)
        }
    }

    /// True once `serial` shows up in the paired list.
    static func isBonded(serial: String) -> Bool {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).contains { $0.deviceClassMajor == 0 && $0.name == serial }
    }

    static func hidSerials() -> Set<String> {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey: Remote.vendorID, kIOHIDProductIDKey: Int(Remote.productID)] as CFDictionary)
        guard let set = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> else { return [] }
        return Set(set.compactMap { IOHIDDeviceGetProperty($0, kIOHIDSerialNumberKey as CFString) as? String })
    }
}
