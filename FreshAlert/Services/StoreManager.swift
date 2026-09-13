import Foundation
import StoreKit

/// Lokaler Schalter aus dem Entwicklermenü: die App behandelt den Nutzer wie einen
/// Gratis-Nutzer, obwohl ein echter Kauf besteht. Der Kauf selbst bleibt unberührt.
/// Greift nur, wenn das Entwicklermenü erreichbar ist (Debug, TestFlight,
/// `-developerMenu`). In App-Store-Builds wird der gespeicherte Wert ignoriert.
struct FreeUserOverride {
    static let defaultsKey = "developerSimulateFreeUser"

    private let defaults: UserDefaults
    private let isDeveloperEnvironment: () -> Bool

    init(
        defaults: UserDefaults = .standard,
        isDeveloperEnvironment: @escaping () -> Bool = { AppEnvironment.isDeveloperMenuAvailable }
    ) {
        self.defaults = defaults
        self.isDeveloperEnvironment = isDeveloperEnvironment
    }

    /// Der gespeicherte Wunsch aus dem Entwicklermenü, unabhängig von der Umgebung.
    var isRequested: Bool {
        get { defaults.bool(forKey: Self.defaultsKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.defaultsKey) }
    }

    /// Nur wahr, wenn der Schalter an ist **und** die Umgebung das Entwicklermenü erlaubt.
    var isActive: Bool {
        isDeveloperEnvironment() && isRequested
    }

    func effectiveIsPro(hasEntitlement: Bool) -> Bool {
        hasEntitlement && !isActive
    }
}

@MainActor
final class StoreManager: ObservableObject {

    static let freeLimit = 20

    private static let yearlyID   = "com.freshalert.pro.yearly"
    private static let lifetimeID = "com.freshalert.pro.lifetime"
    static let productIDs         = [yearlyID, lifetimeID]

    @Published var products: [Product] = []
    /// Die einzige Stelle, die über Pro entscheidet. Berücksichtigt `FreeUserOverride`.
    @Published private(set) var isPro: Bool = false
    /// True, wenn das Jahresabo aktiv ist (nicht beim Einmalkauf). Steuert "Abo verwalten".
    @Published private(set) var hasActiveSubscription = false
    @Published var isPurchasing: Bool  = false
    /// Echter Stand laut StoreKit, ohne den Schalter aus dem Entwicklermenü.
    @Published private(set) var hasProEntitlement = false
    private var hasSubscriptionEntitlement = false

    private let freeUserOverride: FreeUserOverride

    /// Schalter "Als Gratis-Nutzer anzeigen" im Entwicklermenü.
    var simulatesFreeUser: Bool {
        get { freeUserOverride.isRequested }
        set {
            objectWillChange.send()
            freeUserOverride.isRequested = newValue
            applyEntitlements()
        }
    }

    nonisolated(unsafe) private var updatesTask: Task<Void, Never>?

    init(freeUserOverride: FreeUserOverride = FreeUserOverride()) {
        self.freeUserOverride = freeUserOverride
        updatesTask = Task { await observeTransactionUpdates() }
        Task {
            await loadProducts()
            await refreshPurchaseStatus()
            // Nur wenn der Schalter gesetzt ist: TestFlight-Umgebung notfalls über
            // StoreKit nachziehen, damit er schon vor dem Öffnen des Menüs greift.
            if freeUserOverride.isRequested {
                await AppEnvironmentObserver.shared.refresh()
                applyEntitlements()
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Public API

    func purchase(_ product: Product) async throws {
        isPurchasing = true
        defer { isPurchasing = false }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refreshPurchaseStatus()
        case .pending, .userCancelled:
            break
        @unknown default:
            break
        }
    }

    func restorePurchases() async {
        isPurchasing = true
        defer { isPurchasing = false }
        try? await AppStore.sync()
        await refreshPurchaseStatus()
    }

    /// Wie `restorePurchases`, reicht Fehler aber an das Entwicklermenü weiter.
    func syncPurchases() async throws {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
        } catch {
            await refreshPurchaseStatus()
            throw error
        }
        await refreshPurchaseStatus()
    }

    func refreshPurchaseStatus() async {
        var hasPro = false
        var hasSubscription = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               Self.productIDs.contains(tx.productID),
               tx.revocationDate == nil {
                hasPro = true
                if tx.productID == Self.yearlyID { hasSubscription = true }
            }
        }
        applyEntitlements(hasPro: hasPro, hasSubscription: hasSubscription)
    }

    /// Setzt den echten Stand und leitet daraus `isPro` und `hasActiveSubscription` ab.
    func applyEntitlements(hasPro: Bool, hasSubscription: Bool) {
        hasProEntitlement = hasPro
        hasSubscriptionEntitlement = hasSubscription
        applyEntitlements()
    }

    /// Wendet den Schalter erneut an, etwa nachdem die Umgebung erkannt wurde.
    func applyEntitlements() {
        isPro = freeUserOverride.effectiveIsPro(hasEntitlement: hasProEntitlement)
        hasActiveSubscription = hasSubscriptionEntitlement && !freeUserOverride.isActive
    }

    // MARK: - Private

    private func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { $0.id == Self.yearlyID && $1.id != Self.yearlyID }
        } catch { }
    }

    private func observeTransactionUpdates() async {
        for await result in Transaction.updates {
            if case .verified(let tx) = result {
                await tx.finish()
                await refreshPurchaseStatus()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreError.failedVerification
        case .verified(let safe): return safe
        }
    }

    enum StoreError: LocalizedError {
        case failedVerification
        var errorDescription: String? { "Kauf konnte nicht verifiziert werden." }
    }
}
