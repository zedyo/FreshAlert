import Foundation
import StoreKit
import os

@MainActor
final class StoreManager: ObservableObject {

    static let freeLimit = 20

    private static let yearlyID   = "com.freshalert.pro.yearly"
    private static let lifetimeID = "com.freshalert.pro.lifetime"
    static let productIDs         = [yearlyID, lifetimeID]

    private static let logger = Logger(subsystem: "com.freshalert.app", category: "storekit")

    @Published var products: [Product] = []
    @Published var isPro: Bool                 = false
    @Published var isPurchasing: Bool          = false
    @Published private(set) var isLoadingProducts: Bool = false
    /// `true` wenn das Produktladen scheiterte ODER erfolgreich eine **leere**
    /// Liste lieferte (typisch bei inaktivem „Paid Applications"-Vertrag in
    /// App Store Connect — wirft keinen Fehler, gibt nichts zurück).
    @Published private(set) var productsLoadFailed = false

    nonisolated(unsafe) private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { await observeTransactionUpdates() }
        Task {
            await loadProducts()
            await refreshPurchaseStatus()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Public API

    /// Erneut versuchen, die Produkte zu laden — vom Paywall-„Erneut versuchen"-
    /// Button aufgerufen.
    func retryLoadProducts() async {
        await loadProducts()
    }

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

    // MARK: - Private

    private func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { $0.id == Self.yearlyID && $1.id != Self.yearlyID }
            // Erfolg, aber leere Liste → behandeln wir wie einen Fehler.
            // Häufigste Ursache: „Paid Applications"-Vertrag in App Store
            // Connect ist (noch) nicht aktiv, oder die Produkt-IDs sind nicht
            // angelegt. Apple wirft hier keinen Fehler, gibt einfach nichts
            // zurück — ohne diese Behandlung würde die Paywall ewig laden.
            productsLoadFailed = products.isEmpty
            if productsLoadFailed {
                Self.logger.warning("StoreKit lieferte 0 Produkte — Paid-Apps-Vertrag inaktiv oder IDs nicht angelegt?")
            }
        } catch {
            productsLoadFailed = true
            Self.logger.error("Product.products(for:) fehlgeschlagen: \(String(describing: error), privacy: .public)")
        }
    }

    private func refreshPurchaseStatus() async {
        var hasPro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               Self.productIDs.contains(tx.productID),
               tx.revocationDate == nil {
                hasPro = true
                break
            }
        }
        isPro = hasPro
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
