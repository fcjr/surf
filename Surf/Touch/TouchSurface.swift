import Foundation
import os

struct Contact {
    let id: Int
    let state: Int
    let x: Float
    let y: Float
    let vx: Float
    let vy: Float
    let size: Float

    var isTouching: Bool { state == 4 }
}

/// Reads contact frames from the remote's touch surface through the private MultitouchSupport
/// framework. macOS never hands the touch HID report to user space, but it does register the
/// surface as a multitouch device (family 145, 6 by 12 sensor) alongside built-in trackpads.
final class TouchSurface {
    static let remoteFamily = 145
    var onFrame: (([Contact]) -> Void)?

    private static var current: TouchSurface?
    private let log = Logger(subsystem: "com.leftshift.surf", category: "touch")
    private var running: [MTDeviceRef] = []
    private var deviceList: CFArray?

    private let createList: MTDeviceCreateListFn?
    private let registerCallback: MTRegisterContactFrameCallbackFn?
    private let unregisterCallback: MTUnregisterContactFrameCallbackFn?
    private let start: MTDeviceStartFn?
    private let stop: MTDeviceStopFn?
    private let isBuiltIn: MTDeviceIsBuiltInFn?
    private let familyID: MTDeviceGetFamilyIDFn?

    private static let contactCallback: MTContactCallback = { device, data, count, _, _ in
        guard let surface = TouchSurface.current, let data else { return }
        let contacts = (0..<Int(count)).map { i -> Contact in
            let f = data[i]
            return Contact(id: Int(f.identifier), state: Int(f.state), x: f.normalized.pos.x, y: f.normalized.pos.y,
                           vx: f.normalized.vel.x, vy: f.normalized.vel.y, size: f.size)
        }
        DispatchQueue.main.async { surface.onFrame?(contacts) }
    }

    init?() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW) else {
            return nil
        }
        func sym<T>(_ name: String, _: T.Type) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        createList = sym("MTDeviceCreateList", MTDeviceCreateListFn.self)
        registerCallback = sym("MTRegisterContactFrameCallback", MTRegisterContactFrameCallbackFn.self)
        unregisterCallback = sym("MTUnregisterContactFrameCallback", MTUnregisterContactFrameCallbackFn.self)
        start = sym("MTDeviceStart", MTDeviceStartFn.self)
        stop = sym("MTDeviceStop", MTDeviceStopFn.self)
        isBuiltIn = sym("MTDeviceIsBuiltIn", MTDeviceIsBuiltInFn.self)
        familyID = sym("MTDeviceGetFamilyID", MTDeviceGetFamilyIDFn.self)
        guard createList != nil, registerCallback != nil, start != nil, stop != nil else { return nil }
        TouchSurface.current = self
    }

    /// Number of remote touch surfaces currently being read.
    var deviceCount: Int { running.count }

    /// Re-enumerates multitouch devices and starts reading every remote surface. Safe to call often.
    func rescan() {
        stopAll()
        guard let list = createList?()?.takeRetainedValue() else { return }
        deviceList = list
        let n = CFArrayGetCount(list)
        for i in 0..<n {
            let dev = unsafeBitCast(CFArrayGetValueAtIndex(list, i), to: MTDeviceRef.self)
            var family: Int32 = -1
            _ = familyID?(dev, &family)
            let builtIn = isBuiltIn?(dev) ?? true
            guard !builtIn, Int(family) == TouchSurface.remoteFamily else {
                log.debug("skipping multitouch device family=\(family) builtIn=\(builtIn)")
                continue
            }
            registerCallback?(dev, TouchSurface.contactCallback)
            _ = start?(dev, 0)
            running.append(dev)
            log.info("reading touch surface family=\(family)")
        }
    }

    func stopAll() {
        for dev in running {
            _ = stop?(dev)
            unregisterCallback?(dev, TouchSurface.contactCallback)
        }
        running.removeAll()
        deviceList = nil
    }
}
