import Foundation

/// Keep the action chosen on key-down until key-up, even if its mapping changes.
@MainActor
final class HeldActions {
    var perform: ((ButtonAction, Bool) -> Void)?
    private var held: [String: [RemoteButton: ButtonAction]] = [:]

    @discardableResult
    func update(remote: String, button: RemoteButton, action: ButtonAction, down: Bool) -> ButtonAction? {
        if down {
            guard held[remote]?[button] == nil else { return nil }
            let alreadyHeld = held.values.contains { $0.values.contains(action) }
            held[remote, default: [:]][button] = action
            if !alreadyHeld { perform?(action, true) }
            return action
        }
        guard let original = held[remote]?.removeValue(forKey: button) else { return nil }
        if held[remote]?.isEmpty == true { held.removeValue(forKey: remote) }
        if !held.values.contains(where: { $0.values.contains(original) }) {
            perform?(original, false)
        }
        return original
    }

    func retainConnected(_ serials: Set<String>) {
        for serial in Array(held.keys) where !serials.contains(serial) {
            for (button, _) in held[serial] ?? [:] {
                update(remote: serial, button: button, action: .none, down: false)
            }
        }
    }
}
