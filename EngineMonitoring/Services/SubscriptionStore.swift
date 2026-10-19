import Foundation
import StoreKit

/// Engine Pulse Pro: one auto-renewing monthly subscription with a free-trial introductory offer, sold
/// through the App Store (StoreKit 2). Whether the app requires it is set in Info.plist
/// (`EMRequireSubscription`): off during the beta, so testers keep full access and can still try buying.
@MainActor
final class SubscriptionStore: ObservableObject {
    static let monthlyID = "com.fueledconsulting.enginepulse.monthly"

    @Published private(set) var product: Product?
    @Published private(set) var isSubscribed = false
    /// The current entitlement is the free trial (introductory offer).
    @Published private(set) var inTrial = false
    @Published private(set) var renewsOrEnds: Date?
    @Published private(set) var willRenew = true
    @Published private(set) var eligibleForTrial = true
    @Published private(set) var isLoading = false
    @Published var message: String?

    private var updates: Task<Void, Never>?

    /// True when the app is locked without a subscription (after the beta).
    static var required: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "EMRequireSubscription") as? Bool) ?? false
    }

    static var termsURL: URL { url("EMTermsURL", fallback: "https://enginepulse.net/terms/") }
    static var privacyURL: URL { url("EMPrivacyURL", fallback: "https://enginepulse.net/privacy/") }

    private static func url(_ key: String, fallback: String) -> URL {
        let raw = (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
        return URL(string: raw.isEmpty ? fallback : raw) ?? URL(string: fallback)!
    }

    init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refresh()
            }
        }
        Task { await load() }
    }

    var hasAccess: Bool { !Self.required || isSubscribed }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            product = try await Product.products(for: [Self.monthlyID]).first
            if product == nil { message = "The subscription isn't available right now. Try again later." }
        } catch {
            message = "Couldn't reach the App Store: \(error.localizedDescription)"
        }
        await refresh()
    }

    /// Reads the current entitlement and renewal state from the App Store.
    func refresh() async {
        var active = false
        var trial = false
        var expiry: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.productID == Self.monthlyID, t.revocationDate == nil else { continue }
            if let e = t.expirationDate, e < Date() { continue }
            active = true
            expiry = t.expirationDate
            if #available(iOS 17.2, *) {
                trial = t.offer?.type == .introductory
            } else {
                trial = t.offerType == .introductory
            }
        }
        isSubscribed = active
        inTrial = trial
        renewsOrEnds = expiry
        if let status = try? await product?.subscription?.status.first,
           case .verified(let info) = status.renewalInfo {
            willRenew = info.willAutoRenew
        }
        if let sub = product?.subscription {
            eligibleForTrial = await sub.isEligibleForIntroOffer
        }
    }

    func purchase() async {
        guard let product else { await load(); return }
        isLoading = true
        defer { isLoading = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                if case .verified(let t) = result {
                    await t.finish()
                    message = nil
                } else {
                    message = "The App Store couldn't verify the purchase. Try Restore Purchases."
                }
            case .userCancelled:
                break
            case .pending:
                message = "Your purchase is waiting for approval (for example Ask to Buy)."
            @unknown default:
                break
            }
        } catch {
            message = "Purchase failed: \(error.localizedDescription)"
        }
        await refresh()
    }

    func restore() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refresh()
            message = isSubscribed ? "Your subscription is active." : "No Engine Pulse Pro subscription was found for this Apple ID."
        } catch {
            message = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: Text shown with the price (App Store guideline 3.1.2)

    var priceText: String { product.map { "\($0.displayPrice) per month" } ?? "$14.99 per month" }

    /// "15-day", "2-week", "1-month" from the configured introductory offer.
    var trialLength: String? {
        guard eligibleForTrial, let offer = product?.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let p = offer.period
        let unit: String
        switch p.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "day"
        }
        return "\(p.value)-\(unit)"
    }

    var buttonTitle: String {
        if let t = trialLength { return "Start your \(t) free trial" }
        return "Subscribe for \(priceText)"
    }

    var legalText: String {
        let start = trialLength.map { "Free for the \($0) trial, then \(priceText). " } ?? "\(priceText). "
        return start + "Payment is charged to your Apple ID. The subscription renews automatically each month unless it is cancelled at least 24 hours before the end of the current period. Manage or cancel any time in Settings > Apple ID > Subscriptions."
    }
}
