import AppKit
import CoreGraphics
import Foundation

/// Carries out a `ButtonAction` for a press or release. Keys repeat while held at the keyboard's
/// cadence, since synthetic key events don't on their own; shortcuts with modifiers fire once.
@MainActor
final class ActionRunner {
    var click: ((Bool) -> Void)?
    var dictation: ((Bool) -> Void)?
    var repeatDelay: TimeInterval = 0.4
    var repeatInterval: TimeInterval = 0.06

    private var timers: [AnyHashable: Timer] = [:]

    func perform(_ action: ButtonAction, down: Bool) {
        switch action {
        case .none, .system:
            break
        case .media(let key):
            MediaKeyTap.post(key, down: down)
            // volume keys repeat while held, like on a keyboard
            if key == .volumeUp || key == .volumeDown {
                if down { repeatWhileHeld(key) { MediaKeyTap.post(key, down: true, repeating: true) } } else { timers.removeValue(forKey: key)?.invalidate() }
            }
        case .click:
            click?(down)
        case .dictation:
            dictation?(down)
        case .missionControl:
            if down { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app")) }
        case .sleepDisplays:
            if down {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
                p.arguments = ["displaysleepnow"]
                try? p.run()
            }
        case .key(let combo):
            if down { press(combo) } else { release(combo) }
        }
    }

    private func press(_ combo: KeyCombo) {
        post(combo, down: true, autorepeat: false)
        guard combo.flags.isEmpty else { return }
        repeatWhileHeld(combo) { [weak self] in self?.post(combo, down: true, autorepeat: true) }
    }

    private func repeatWhileHeld(_ id: AnyHashable, _ fire: @escaping @MainActor () -> Void) {
        let timer = Timer(fire: Date(timeIntervalSinceNow: repeatDelay), interval: repeatInterval, repeats: true) { _ in
            MainActor.assumeIsolated { fire() }
        }
        RunLoop.main.add(timer, forMode: .common)
        timers[id]?.invalidate()
        timers[id] = timer
    }

    private func release(_ combo: KeyCombo) {
        timers.removeValue(forKey: combo)?.invalidate()
        post(combo, down: false, autorepeat: false)
    }

    private func post(_ combo: KeyCombo, down: Bool, autorepeat: Bool) {
        let ev = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(combo.keyCode), keyDown: down)
        ev?.flags = combo.flags
        ev?.setIntegerValueField(.keyboardEventAutorepeat, value: autorepeat ? 1 : 0)
        ev?.post(tap: .cghidEventTap)
    }
}
