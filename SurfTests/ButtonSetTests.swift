import Carbon.HIToolbox
import XCTest

final class ButtonSetTests: XCTestCase {
    func testSiriPress() {
        XCTAssertEqual(ButtonSet(report: [0xFB, 0x20, 0x00]), .siri)
        XCTAssertEqual(ButtonSet(report: [0xFB, 0x08, 0x10])?.labels, ["Click", "Left"])
        XCTAssertFalse(ButtonSet(report: [0xFB, 0x08, 0x10])!.isDisjoint(with: .ring))
        XCTAssertTrue(ButtonSet(report: [0xFB, 0x08, 0x00])!.isDisjoint(with: .ring))
        XCTAssertEqual(ButtonSet(report: [0xFB, 0x00, 0x00]), [])
        XCTAssertNil(ButtonSet(report: [0x01, 0x00]))
    }

    func testButtonActionsRoundTrip() throws {
        let actions: [RemoteButton: ButtonAction] = [.back: .key(KeyCombo(kVK_ANSI_W, .maskCommand)), .tv: .none]
        let data = try JSONEncoder().encode(actions)
        XCTAssertEqual(try JSONDecoder().decode([RemoteButton: ButtonAction].self, from: data), actions)
        XCTAssertEqual(ButtonAction.key(KeyCombo(kVK_ANSI_W, .maskCommand)).title, "Close window (⌘W)")
        XCTAssertEqual(ButtonAction.key(KeyCombo(kVK_UpArrow)).title, "Up Arrow")
        XCTAssertEqual(KeyCombo(kVK_PageUp, .maskCommand).label, "⌘ Page Up")
    }

    func testManufacturerData() {
        let d = Data([0x4c, 0x00, 0x07, 0x0d, 0x02, 0x15, 0x03, 0x02, 0x02, 0x00, 0x00, 0x00, 0x00, 0x01, 0x44, 0x45, 0x43])
        let parsed = NearbyRemote.parseManufacturerData(d)
        XCTAssertEqual(parsed?.productID, 0x0315)
        XCTAssertEqual(parsed?.address, "02:00:00:00:00:01")
    }
}
