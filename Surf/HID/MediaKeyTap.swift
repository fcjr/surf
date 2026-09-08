import AppKit
import CoreGraphics
import Foundation
import os

/// Takes the remote's media keys away from macOS when they're remapped. The remote reports
/// Play/Pause, Mute, and volume as ordinary media keys, which the system acts on before any app
/// sees them, so this taps the system-defined media key events and holds each one for a moment.
/// If the remote's own report for that key arrives while it's held, the event is dropped and the
/// remapped action runs instead; otherwise it's replayed untouched, so keyboards keep working.
@MainActor
final class MediaKeyTap {
    /// Whether a key is remapped right now. Unremapped keys pass straight through.
    var isRemapped: ((MediaKey) -> Bool)?

    static let tag: Int64 = 0x5355_5246  // "SURF" on replayed events so the tap lets them through
    static let holdTime: TimeInterval = 0.05
    static let expectTime: TimeInterval = 0.1

    private let log = Logger(subsystem: "com.leftshift.surf", category: "mediakeys")
    private var tap: CFMachPort?
    private var held: [Int: (event: CGEvent, timer: Timer)] = [:]
    private var expected: [Int: Date] = [:]

    private static let systemDefined = CGEventType(rawValue: 14)!  // NX_SYSDEFINED
    private static let auxControlSubtype = 8  // NX_SUBTYPE_AUX_CONTROL_BUTTONS

    /// Creates the tap if it doesn't exist yet. Needs the Accessibility permission; safe to call again after it's granted.
    func start() {
        guard tap == nil else { return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: CGEventMask(1 << MediaKeyTap.systemDefined.rawValue),
                                           callback: { _, type, event, ctx in
                                               let tap = Unmanaged<MediaKeyTap>.fromOpaque(ctx!).takeUnretainedValue()
                                               return MainActor.assumeIsolated { tap.handle(type, event) }
                                           }, userInfo: ctx) else {
            log.error("could not create media key tap (needs Accessibility)")
            return
        }
        tap = port
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        log.notice("media key tap running")
    }

    /// The remote reported this key itself. Drops a matching held event, or remembers to drop one that's about to arrive.
    func claim(_ key: MediaKey, down: Bool) {
        let id = MediaKeyTap.id(key, down)
        if let h = held.removeValue(forKey: id) {
            h.timer.invalidate()
        } else {
            expected[id] = Date(timeIntervalSinceNow: MediaKeyTap.expectTime)
        }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == MediaKeyTap.systemDefined, event.getIntegerValueField(.eventSourceUserData) != MediaKeyTap.tag,
              let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == MediaKeyTap.auxControlSubtype,
              let key = MediaKey(rawValue: (ns.data1 >> 16) & 0xFFFF), isRemapped?(key) == true else {
            return Unmanaged.passUnretained(event)
        }
        let down = (ns.data1 >> 8) & 0xFF == 0x0A
        let id = MediaKeyTap.id(key, down)
        if let until = expected.removeValue(forKey: id), until > Date() { return nil }
        guard let copy = event.copy() else { return Unmanaged.passUnretained(event) }
        held[id]?.timer.invalidate()
        let timer = Timer(timeInterval: MediaKeyTap.holdTime, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.replay(id) }
        }
        RunLoop.main.add(timer, forMode: .common)
        held[id] = (copy, timer)
        return nil
    }

    /// No remote report matched in time: this key came from something else. Send it on its way.
    private func replay(_ id: Int) {
        guard let h = held.removeValue(forKey: id) else { return }
        h.event.setIntegerValueField(.eventSourceUserData, value: MediaKeyTap.tag)
        h.event.post(tap: .cghidEventTap)
    }

    private static func id(_ key: MediaKey, _ down: Bool) -> Int { key.rawValue << 1 | (down ? 1 : 0) }

    /// Posts a media key the way a keyboard would. Tagged so the tap passes it through.
    static func post(_ key: MediaKey, down: Bool, repeating: Bool = false) {
        let flags = (down ? 0x0A : 0x0B) << 8 | (repeating ? 1 : 0)
        let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                    windowNumber: 0, context: nil, subtype: Int16(auxControlSubtype), data1: key.rawValue << 16 | flags, data2: -1)
        guard let cg = ev?.cgEvent else { return }
        cg.setIntegerValueField(.eventSourceUserData, value: tag)
        cg.post(tap: .cghidEventTap)
    }
}
