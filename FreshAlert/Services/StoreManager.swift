import Foundation
import StoreKit

@MainActor
final class StoreManager: ObservableObject {

    static let freeLimit = 20

    private static let yearlyID   = "com.freshalert.pro.yearly"
    private static let lifetimeID = "com.freshalert.pro.lifetime"
    static let productIDs         = [yearlyID, lifetimeID]

    @Published var products: [Product] = []
    @Published var isPro: Bool         = false
    @Published var isPurchasing: Bool  = false

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
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { $0.id == Self.yearlyID && $1.id != Self.yearlyID }
        } catch { }
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
