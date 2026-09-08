import AppKit
import ApplicationServices
import Foundation
import QuartzCore

/// Turns finger motion on the remote's touch surface into pointer movement, clicks, and scrolling.
/// One finger moves, two fingers scroll, the touch surface click is the left button.
@MainActor
final class MouseController {
    var sensitivity: Double = 1.0
    /// Points of travel for a slow swipe across the whole surface.
    var floorGain: Double = 250
    /// Points of travel for a fast flick across the whole surface.
    var capGain: Double = 1800
    /// Speed (surface widths per second) at which gain has climbed ~63% of the way from floor to cap.
    var accelKnee: Double = 2.5
    var scrollFloorGain: Double = 300
    var scrollCapGain: Double = 2000
    /// Seconds for momentum scrolling to decay to ~37% of its speed after the fingers lift.
    var momentumDecay: Double = 0.6

    private var last: [Int: (Float, Float)] = [:]
    private var buttonDown = false
    private var smoothedSpeed = 0.0
    private var remainder = (x: 0.0, y: 0.0)

    private var scrolling = false
    private var holdPointerUntilLift = false
    private var scrollVelocity = (x: 0.0, y: 0.0)  // points per second, screen down positive
    private var scrollRemainder = (x: 0.0, y: 0.0)
    private var momentumTimer: Timer?
    private var momentumTick: CFTimeInterval = 0

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func handle(_ contacts: [Contact]) {
        let touching = contacts.filter(\.isTouching)
        defer { last = Dictionary(uniqueKeysWithValues: touching.map { ($0.id, ($0.x, $0.y)) }) }
        if !touching.isEmpty { stopMomentum() }
        if scrolling, touching.count != 2 { endScroll() }
        if touching.isEmpty { holdPointerUntilLift = false }
        var deltas: [(Double, Double, Double)] = []  // dx, dy (screen down positive), speed
        for c in touching {
            guard let (px, py) = last[c.id] else { continue }
            let dx = Double(c.x - px), dy = -Double(c.y - py)
            deltas.append((dx, dy, Double(hypot(c.vx, c.vy))))
        }
        guard !deltas.isEmpty, last.count == touching.count else {  // wait for a stable finger count
            smoothedSpeed = 0
            remainder = (0, 0)
            return
        }
        switch touching.count {
        case 1:
            if holdPointerUntilLift { break }  // a finger left over from a scroll shouldn't move the pointer
            let (dx, dy, speed) = deltas[0]
            smoothedSpeed = 0.7 * smoothedSpeed + 0.3 * speed
            let gain = curve(smoothedSpeed, floor: floorGain, cap: capGain)
            let (ix, iy) = quantize(dx * gain, dy * gain, &remainder)
            move(dx: ix, dy: iy)
        case 2:
            let dx = deltas.map { $0.0 }.reduce(0, +) / 2, dy = deltas.map { $0.1 }.reduce(0, +) / 2
            let vx = Double(touching.map(\.vx).reduce(0, +)) / 2, vy = -Double(touching.map(\.vy).reduce(0, +)) / 2
            let gain = curve(hypot(vx, vy), floor: scrollFloorGain, cap: scrollCapGain)
            scrollVelocity = (0.6 * scrollVelocity.x + 0.4 * vx * gain, 0.6 * scrollVelocity.y + 0.4 * vy * gain)
            let phase: CGScrollPhase = scrolling ? .changed : .began
            scrolling = true
            scroll(dx: dx * gain, dy: dy * gain, phase: phase)
        default:
            break
        }
    }

    func click(down: Bool) {
        guard down != buttonDown, let pos = currentPosition() else { return }
        buttonDown = down
        let ev = CGEvent(mouseEventSource: nil, mouseType: down ? .leftMouseDown : .leftMouseUp, mouseCursorPosition: pos, mouseButton: .left)
        ev?.post(tap: .cghidEventTap)
    }

    /// Gain rises from `floor` toward `cap` as speed grows, reaching ~63% of the way at `accelKnee`.
    private func curve(_ speed: Double, floor: Double, cap: Double) -> Double {
        (floor + (cap - floor) * (1 - exp(-speed / accelKnee))) * sensitivity
    }

    /// Rounds to whole points, carrying the fraction into the next frame so slow motion isn't lost.
    private func quantize(_ x: Double, _ y: Double, _ rem: inout (x: Double, y: Double)) -> (Double, Double) {
        let fx = x + rem.x, fy = y + rem.y
        let ix = fx.rounded(), iy = fy.rounded()
        rem = (fx - ix, fy - iy)
        return (ix, iy)
    }

    private func currentPosition() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    private func move(dx: Double, dy: Double) {
        guard let pos = currentPosition() else { return }
        let target = clamp(CGPoint(x: pos.x + dx, y: pos.y + dy), from: pos)
        let ev = CGEvent(mouseEventSource: nil, mouseType: buttonDown ? .leftMouseDragged : .mouseMoved, mouseCursorPosition: target, mouseButton: .left)
        ev?.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx.rounded()))
        ev?.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy.rounded()))
        ev?.post(tap: .cghidEventTap)
    }

    // MARK: Scrolling

    private func endScroll() {
        scrolling = false
        holdPointerUntilLift = true
        scroll(dx: 0, dy: 0, phase: .ended)
        if hypot(scrollVelocity.x, scrollVelocity.y) > 60 { startMomentum() }
    }

    private func startMomentum() {
        let speed = hypot(scrollVelocity.x, scrollVelocity.y)
        if speed > 8000 { scrollVelocity = (scrollVelocity.x * 8000 / speed, scrollVelocity.y * 8000 / speed) }
        momentumTick = CACurrentMediaTime()
        scroll(dx: 0, dy: 0, momentum: .begin)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickMomentum() }
        }
        RunLoop.main.add(timer, forMode: .common)  // keep coasting while a menu or our own window tracks the mouse
        momentumTimer = timer
    }

    private func tickMomentum() {
        let now = CACurrentMediaTime()
        let k = exp(-(now - momentumTick) / momentumDecay)
        momentumTick = now
        // Distance covered while the velocity decays exponentially over this tick.
        let dx = scrollVelocity.x * momentumDecay * (1 - k), dy = scrollVelocity.y * momentumDecay * (1 - k)
        scrollVelocity = (scrollVelocity.x * k, scrollVelocity.y * k)
        scroll(dx: dx, dy: dy, momentum: .continuous)
        if hypot(scrollVelocity.x, scrollVelocity.y) < 30 { stopMomentum() }
    }

    private func stopMomentum() {
        guard let timer = momentumTimer else { return }
        timer.invalidate()
        momentumTimer = nil
        scrollVelocity = (0, 0)
        scroll(dx: 0, dy: 0, momentum: .end)
    }

    private func scroll(dx: Double, dy: Double, phase: CGScrollPhase? = nil, momentum: CGMomentumScrollPhase? = nil) {
        let (ix, iy) = quantize(dx, dy, &scrollRemainder)
        // wheel1 is vertical; positive scrolls content up (natural direction inverted below to match trackpads)
        let ev = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(-iy), wheel2: Int32(-ix), wheel3: 0)
        if let phase { ev?.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue)) }
        if let momentum { ev?.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentum.rawValue)) }
        ev?.post(tap: .cghidEventTap)
    }

    /// Keeps the pointer on a display. CG coordinates put the origin at the top-left of the main display.
    private func clamp(_ p: CGPoint, from origin: CGPoint) -> CGPoint {
        let displays = MouseController.displayBounds()
        if displays.contains(where: { $0.contains(p) }) { return p }
        let home = displays.first { $0.contains(origin) } ?? displays.first ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        return CGPoint(x: min(max(p.x, home.minX), home.maxX - 1), y: min(max(p.y, home.minY), home.maxY - 1))
    }

    private static func displayBounds() -> [CGRect] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.map { CGDisplayBounds($0) }
    }
}
