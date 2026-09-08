import Foundation
import IOKit.hid
import os

/// Listens to input reports from paired remotes and reports button state per serial number.
/// Non-seizing: the system keeps handling the remote as usual.
final class RemoteHID {
    var onButtons: ((String, ButtonSet) -> Void)?

    private let log = Logger(subsystem: "com.leftshift.surf", category: "hid")
    private var manager: IOHIDManager!
    private var devices: [IOHIDDevice: DeviceBox] = [:]

    final class DeviceBox {
        let serial: String
        var buffer = [UInt8](repeating: 0, count: 256)
        var collection = ""
        unowned let owner: RemoteHID
        init(serial: String, owner: RemoteHID) { self.serial = serial; self.owner = owner }
    }

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: Remote.vendorID, kIOHIDProductIDKey: Int(Remote.productID)] as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            Unmanaged<RemoteHID>.fromOpaque(ctx!).takeUnretainedValue().attach(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            Unmanaged<RemoteHID>.fromOpaque(ctx!).takeUnretainedValue().detach(device)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func attach(_ device: IOHIDDevice) {
        let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String ?? "?"
        let page = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? -1
        let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? -1
        let box = DeviceBox(serial: serial, owner: self)
        box.collection = String(format: "%04x/%04x", page, usage)
        devices[device] = box
        let ctx = Unmanaged.passUnretained(box).toOpaque()
        box.buffer.withUnsafeMutableBufferPointer { buf in
            IOHIDDeviceRegisterInputReportCallback(device, buf.baseAddress!, buf.count, { ctx, _, _, _, reportID, report, length in
                let box = Unmanaged<DeviceBox>.fromOpaque(ctx!).takeUnretainedValue()
                let bytes = Array(UnsafeBufferPointer(start: report, count: length))
                box.owner.log.debug("report collection=\(box.collection, privacy: .public) id=\(reportID) len=\(length)")
                box.owner.handle(serial: box.serial, reportID: reportID, bytes: bytes)
            }, ctx)
        }
        log.info("attached \(serial, privacy: .public) collection=\(box.collection, privacy: .public)")
    }

    private func detach(_ device: IOHIDDevice) {
        if let box = devices.removeValue(forKey: device) {
            log.info("detached \(box.serial)")
            onButtons?(box.serial, [])
        }
    }

    private func handle(serial: String, reportID: UInt32, bytes: [UInt8]) {
        // macOS delivers the report ID as the first byte for numbered reports; cover both cases.
        let report = bytes.first == 0xFB ? bytes : [UInt8(truncatingIfNeeded: reportID)] + bytes
        guard let buttons = ButtonSet(report: report) else { return }
        onButtons?(serial, buttons)
    }
}
