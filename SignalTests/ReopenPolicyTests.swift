import XCTest

/// Re-opening an already-running Signal is the escape hatch out of a hidden
/// menu bar icon, so it has to do two things at once — and the preference
/// behind it has to default to "visible" even on a fresh install.
final class ReopenPolicyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: SettingsStore.Key.showMenuBarIcon)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsStore.Key.showMenuBarIcon)
        super.tearDown()
    }

    // MARK: - ReopenPolicy

    func testVisibleIconReopenOnlyPresentsPanel() {
        let actions = ReopenPolicy.actions(menuBarIconVisible: true)
        XCTAssertEqual(actions, ReopenPolicy.Actions(presentPanel: true, openPreferences: false))
    }

    func testHiddenIconReopenAlsoOpensPreferences() {
        let actions = ReopenPolicy.actions(menuBarIconVisible: false)
        XCTAssertEqual(actions, ReopenPolicy.Actions(presentPanel: true, openPreferences: true))
    }

    func testPanelIsAlwaysPresented() {
        XCTAssertTrue(ReopenPolicy.actions(menuBarIconVisible: true).presentPanel)
        XCTAssertTrue(ReopenPolicy.actions(menuBarIconVisible: false).presentPanel)
    }

    // MARK: - SettingsStore.showMenuBarIcon

    func testShowMenuBarIconDefaultsToTrue() {
        SettingsStore.registerDefaults()
        XCTAssertTrue(SettingsStore.showMenuBarIcon)
    }

    func testShowMenuBarIconRoundTrips() {
        SettingsStore.showMenuBarIcon = false
        XCTAssertFalse(SettingsStore.showMenuBarIcon)

        SettingsStore.showMenuBarIcon = true
        XCTAssertTrue(SettingsStore.showMenuBarIcon)
    }
}
