import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: StoreManager

    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    headerSection
                    featuresSection
                    productsSection
                    legalSection
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("FreshAlert Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 52))
                .foregroundStyle(Color.freshGreen)
                .padding(.top, 12)

            Text("Unbegrenzte Produkte")
                .font(.title2.bold())

            Text("Du hast das Limit von \(StoreManager.freeLimit) Einträgen erreicht. Mit Pro trackst du so viele Produkte du möchtest.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeatureRow(icon: "infinity",              text: "Unbegrenzte Einträge")
            FeatureRow(icon: "bell.badge",            text: "Ablauf-Erinnerungen")
            FeatureRow(icon: "barcode.viewfinder",    text: "Barcode-Scanner")
            FeatureRow(icon: "rectangle.stack",       text: "Alle zukünftigen Features")
        }
        .padding(.horizontal, 36)
    }

    private var productsSection: some View {
        VStack(spacing: 12) {
            if store.products.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ForEach(store.products) { product in
                    ProductButton(product: product, isPurchasing: store.isPurchasing) {
                        Task { await buy(product) }
                    }
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 16)
    }

    private var legalSection: some View {
        VStack(spacing: 14) {
            Button("Kauf wiederherstellen") {
                Task { await restore() }
            }
            .font(.subheadline)
            .foregroundStyle(Color.freshGreen)
            .disabled(store.isPurchasing)

            HStack(spacing: 20) {
                Link("Nutzungsbedingungen",
                     destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                // TODO: Replace with your published privacy policy URL before App Store submission.
                Link("Datenschutz",
                     destination: URL(string: "https://www.apple.com/privacy/")!)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            Text("Das Jahresabo verlängert sich automatisch um 1 Jahr, sofern es nicht mindestens 24 Stunden vor Ablauf in den iPhone-Einstellungen unter „Abonnements" gekündigt wird.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }

    // MARK: - Actions

    private func buy(_ product: Product) async {
        errorMessage = nil
        do {
            try await store.purchase(product)
            if store.isPro { dismiss() }
        } catch {
            errorMessage = "Kauf fehlgeschlagen. Bitte versuche es erneut."
        }
    }

    private func restore() async {
        errorMessage = nil
        await store.restorePurchases()
        if store.isPro { dismiss() }
    }
}

// MARK: - Subviews

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(Color.freshGreen)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }
}

private struct ProductButton: View {
    let product: Product
    let isPurchasing: Bool
    let action: () -> Void

    private var isYearly: Bool { product.id == "com.freshalert.pro.yearly" }

    private var periodSuffix: String {
        guard let sub = product.subscription else { return "" }
        switch sub.subscriptionPeriod.unit {
        case .year:  return " / Jahr"
        case .month: return " / Monat"
        default:     return ""
        }
    }

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(product.displayName)
                            .font(.subheadline.weight(.semibold))
                        if isYearly {
                            Text("EMPFOHLEN")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.25), in: Capsule())
                        }
                    }
                    if !isYearly {
                        Text("Einmalig · kein Abo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isPurchasing {
                    ProgressView()
                        .tint(isYearly ? .white : Color.freshGreen)
                } else {
                    Text(product.displayPrice + periodSuffix)
                        .font(.headline)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isYearly ? Color.freshGreen : Color(.secondarySystemBackground))
            .foregroundStyle(isYearly ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(isPurchasing)
        .buttonStyle(.plain)
    }
}
