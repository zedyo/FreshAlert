import SwiftUI
import StoreKit

/// Warum die Paywall gezeigt wird. Entscheidet über die Kopfzeile.
enum PaywallReason {
    case limitReached
    case fromSettings
}

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: StoreManager

    let reason: PaywallReason

    @State private var errorMessage: String?

    init(reason: PaywallReason = .limitReached) {
        self.reason = reason
    }

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

            Text(headerTitle)
                .font(.title2.bold())

            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }

    private var headerTitle: String {
        switch reason {
        case .limitReached: return "Unbegrenzte Produkte"
        case .fromSettings: return "FreshAlert Pro"
        }
    }

    private var headerSubtitle: String {
        switch reason {
        case .limitReached:
            return "Du hast das Limit von \(StoreManager.freeLimit) Produkten erreicht. Mit Pro trackst du so viele Produkte, wie du möchtest."
        case .fromSettings:
            return "Mehr als \(StoreManager.freeLimit) Produkte, einmal kaufen oder jährlich."
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeatureRow(icon: "infinity",              text: "Unbegrenzt viele Produkte statt \(StoreManager.freeLimit)")
            FeatureRow(icon: "lock.open",             text: "Einmal kaufen oder jährlich, kein Monatsabo")
            FeatureRow(icon: "heart",                 text: "Unterstützt die Weiterentwicklung")
        }
        .padding(.horizontal, 36)
    }

    private var productsSection: some View {
        VStack(spacing: 12) {
            if store.products.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                // Zwei große Kacheln nebeneinander, gleich hoch (Nik, 13.09.2026).
                HStack(alignment: .top, spacing: 12) {
                    ForEach(store.products) { product in
                        ProductTile(product: product, isPurchasing: store.isPurchasing) {
                            Task { await buy(product) }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
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
                Link("Nutzungsbedingungen", destination: Legal.termsOfUseURL)
                Link("Datenschutz", destination: Legal.privacyPolicyURL)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            Text("Das Jahresabo verlängert sich automatisch um 1 Jahr, sofern es nicht mindestens 24 Stunden vor Ablauf in den iPhone-Einstellungen unter „Abonnements“ gekündigt wird.")
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

private struct ProductTile: View {
    let product: Product
    let isPurchasing: Bool
    let action: () -> Void

    private var isYearly: Bool { product.id == "com.freshalert.pro.yearly" }

    /// Die gestalteten Kauf-Bilder aus App Store Connect (Nik, 13.09.2026):
    /// Erneuerung für das Jahresabo, Unendlich für Lifetime.
    private var imageName: String { isYearly ? "ProJahresabo" : "ProLifetime" }

    private var periodText: String {
        guard let subscription = product.subscription else { return "einmalig" }
        switch subscription.subscriptionPeriod.unit {
        case .year:  return "pro Jahr"
        case .month: return "pro Monat"
        case .week:  return "pro Woche"
        case .day:   return "pro Tag"
        @unknown default: return ""
        }
    }

    private var noteText: String { isYearly ? "Jederzeit kündbar" : "Kein Abo" }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Beim Einmalkauf unsichtbar, damit beide Kacheln gleich aufgebaut sind.
                Text("EMPFOHLEN")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.25), in: Capsule())
                    .opacity(isYearly ? 1 : 0)
                    .accessibilityHidden(!isYearly)

                Image(imageName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .accessibilityHidden(true)

                Text(product.displayName)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if isPurchasing {
                    ProgressView()
                        .tint(isYearly ? .white : Color.freshGreen)
                        .frame(height: 30)
                } else {
                    Text(product.displayPrice)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Text(periodText)
                    .font(.caption.weight(.medium))

                Text(noteText)
                    .font(.caption2)
                    .opacity(0.8)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isYearly ? Color.freshGreen : Color(.secondarySystemBackground))
            .foregroundStyle(isYearly ? Color.white : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isYearly ? Color.clear : Color.freshGreen.opacity(0.35), lineWidth: 1)
            )
        }
        .disabled(isPurchasing)
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(product.displayName), \(product.displayPrice) \(periodText)")
    }
}
