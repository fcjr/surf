import XCTest

@MainActor
final class HeldActionsTests: XCTestCase {
    func testChangingMappingWhileHeldReleasesOriginalAction() {
        let held = HeldActions()
        var events: [String] = []
        held.perform = { action, down in events.append("\(action):\(down)") }
        held.update(remote: "a", button: .siri, action: .dictation, down: true)
        held.update(remote: "a", button: .siri, action: .none, down: false)
        XCTAssertEqual(events, ["dictation:true", "dictation:false"])
    }

    func testDisconnectOnlyReleasesActionsNoOtherRemoteIsHolding() {
        let held = HeldActions()
        var events: [Bool] = []
        held.perform = { _, down in events.append(down) }
        held.update(remote: "a", button: .siri, action: .dictation, down: true)
        held.update(remote: "b", button: .siri, action: .dictation, down: true)
        held.retainConnected(["b"])
        XCTAssertEqual(events, [true])
        held.retainConnected([])
        XCTAssertEqual(events, [true, false])
        held.retainConnected([])
        XCTAssertEqual(events, [true, false])
    }

    func testDisconnectReleasesEveryHeldAction() {
        let held = HeldActions()
        var released: Set<ButtonAction> = []
        held.perform = { action, down in if !down { released.insert(action) } }
        let arrow = ButtonAction.key(KeyCombo(126))
        held.update(remote: "a", button: .click, action: .click, down: true)
        held.update(remote: "a", button: .up, action: arrow, down: true)
        held.update(remote: "a", button: .siri, action: .dictation, down: true)
        held.retainConnected([])
        XCTAssertEqual(released, [.click, arrow, .dictation])
    }
}
