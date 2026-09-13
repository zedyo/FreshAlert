import XCTest
@testable import FreshAlert

/// Der Schalter "Als Gratis-Nutzer anzeigen" aus dem Entwicklermenü darf nur greifen,
/// wenn das Entwicklermenü erreichbar ist, und nie in App-Store-Builds.
final class FreeUserOverrideTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "FreeUserOverrideTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func override(developerEnvironment: Bool) -> FreeUserOverride {
        FreeUserOverride(defaults: defaults, isDeveloperEnvironment: { developerEnvironment })
    }

    func testSchalterGreiftInEntwicklerumgebung() {
        let sut = override(developerEnvironment: true)
        sut.isRequested = true
        XCTAssertTrue(sut.isActive)
        XCTAssertFalse(sut.effectiveIsPro(hasEntitlement: true))
    }

    func testSchalterWirdImAppStoreIgnoriert() {
        let sut = override(developerEnvironment: false)
        // Auch wenn der Schlüssel irgendwie gesetzt ist.
        defaults.set(true, forKey: FreeUserOverride.defaultsKey)
        XCTAssertTrue(sut.isRequested)
        XCTAssertFalse(sut.isActive)
        XCTAssertTrue(sut.effectiveIsPro(hasEntitlement: true))
    }

    func testOhneSchalterBleibtProErhalten() {
        let sut = override(developerEnvironment: true)
        XCTAssertFalse(sut.isActive)
        XCTAssertTrue(sut.effectiveIsPro(hasEntitlement: true))
    }

    func testOhneKaufNiePro() {
        XCTAssertFalse(override(developerEnvironment: true).effectiveIsPro(hasEntitlement: false))
        let sut = override(developerEnvironment: false)
        sut.isRequested = true
        XCTAssertFalse(sut.effectiveIsPro(hasEntitlement: false))
    }

    func testSchalterWirdGespeichert() {
        override(developerEnvironment: true).isRequested = true
        XCTAssertTrue(defaults.bool(forKey: FreeUserOverride.defaultsKey))
        XCTAssertTrue(override(developerEnvironment: true).isActive)
    }

    @MainActor
    func testStoreManagerZeigtGratisNutzerInEntwicklerumgebung() {
        let store = StoreManager(freeUserOverride: override(developerEnvironment: true))
        store.applyEntitlements(hasPro: true, hasSubscription: true)
        XCTAssertTrue(store.isPro)
        XCTAssertTrue(store.hasActiveSubscription)

        store.simulatesFreeUser = true
        XCTAssertTrue(store.hasProEntitlement)
        XCTAssertFalse(store.isPro)
        XCTAssertFalse(store.hasActiveSubscription)

        store.simulatesFreeUser = false
        XCTAssertTrue(store.isPro)
        XCTAssertTrue(store.hasActiveSubscription)
    }

    @MainActor
    func testStoreManagerIgnoriertSchalterImAppStore() {
        defaults.set(true, forKey: FreeUserOverride.defaultsKey)
        let store = StoreManager(freeUserOverride: override(developerEnvironment: false))
        store.applyEntitlements(hasPro: true, hasSubscription: true)
        XCTAssertTrue(store.isPro)
        XCTAssertTrue(store.hasActiveSubscription)
    }
}
