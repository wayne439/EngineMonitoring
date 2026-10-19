import SwiftUI
import StoreKit

/// Engine Pulse Pro: what the subscription includes, the free trial, the price and Apple's required terms.
/// Shown when the subscription is required and missing, and from ACCOUNT at any time.
struct PaywallView: View {
    @EnvironmentObject private var store: SubscriptionStore
    @EnvironmentObject private var cloud: CloudStore
    @Environment(\.dismiss) private var dismiss
    /// Shown as a gate (no close button) rather than a sheet.
    var isGate = false

    private let features: [(icon: String, title: String, detail: String)] = [
        ("waveform.path.ecg", "Engine health score", "Green, yellow or red from your last 10 flights, with the trend and every reason."),
        ("checkmark.shield", "Every flight checked", "Against the limits read from your own POH and supplements, locked so they stay right."),
        ("chart.line.uptrend.xyaxis", "Early warning", "Slow changes in CHT, oil, EGT, TIT and voltage, corrected for OAT and fuel flow."),
        ("wrench.and.screwdriver", "Maintenance and ADs", "Service history, reminders and an airworthiness directive check for your aircraft."),
        ("icloud.and.arrow.up", "Every device, any upload", "iPad, iPhone and the upload website, all in sync."),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    Image("Logo")
                        .resizable()
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Text("Engine Pulse Pro")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                    Text("Know your engine before it tells you.")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(features, id: \.title) { f in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: f.icon)
                                .font(.title3)
                                .foregroundStyle(.cyan)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.title).font(.headline)
                                Text(f.detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                if store.isSubscribed {
                    Label(store.inTrial ? "Your free trial is active" : "You're subscribed", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    if let d = store.renewsOrEnds {
                        Text("\(store.willRenew ? "Renews" : "Ends") \(d.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 6) {
                        if let t = store.trialLength {
                            Text("\(t.capitalized) free trial")
                                .font(.title2.bold())
                            Text("then \(store.priceText)")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(store.priceText).font(.title2.bold())
                        }
                    }
                    Button {
                        Task { await store.purchase() }
                    } label: {
                        HStack {
                            if store.isLoading { ProgressView().tint(.white) }
                            Text(store.buttonTitle).font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.isLoading)
                }

                if let message = store.message {
                    Text(message).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                }

                HStack(spacing: 18) {
                    Button("Restore Purchases") { Task { await store.restore() } }
                    if store.isSubscribed {
                        ManageButton()
                    }
                }
                .font(.subheadline)

                Text(store.legalText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 16) {
                    Link("Terms of Use", destination: SubscriptionStore.termsURL)
                    Link("Privacy Policy", destination: SubscriptionStore.privacyURL)
                    Link("Apple EULA", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                }
                .font(.caption)

                if isGate && cloud.isSignedIn {
                    Button("Sign out", role: .destructive) { cloud.signOut() }
                        .font(.caption)
                }
                Text("Engine Pulse is advisory only. It is not FAA-approved and never replaces your POH/AFM, your engine monitor or your A&P.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            if !isGate {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .task { await store.refresh() }
    }
}

/// Opens Apple's subscription management sheet.
private struct ManageButton: View {
    @State private var show = false
    var body: some View {
        Button("Manage subscription") { show = true }
            .manageSubscriptionsSheet(isPresented: $show)
    }
}

/// ACCOUNT section: subscription status and the way in to the paywall.
struct SubscriptionSection: View {
    @EnvironmentObject private var store: SubscriptionStore
    /// Owned by the screen (sheets attached inside a List section don't always present).
    @Binding var showPaywall: Bool
    @Binding var showManage: Bool

    var body: some View {
        Section {
            if store.isSubscribed {
                Label(store.inTrial ? "Engine Pulse Pro · free trial" : "Engine Pulse Pro · active", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                if let d = store.renewsOrEnds {
                    LabeledContent(store.willRenew ? "Renews" : "Ends", value: d.formatted(date: .abbreviated, time: .omitted))
                }
                Button("Manage subscription") { showManage = true }
            } else if !SubscriptionStore.required {
                Label("Beta: everything is free for now", systemImage: "gift")
                Button("See Engine Pulse Pro") { showPaywall = true }
            } else {
                Button("Subscribe to Engine Pulse Pro") { showPaywall = true }
            }
            Button("Restore Purchases") { Task { await store.restore() } }
            if let m = store.message { Text(m).font(.footnote).foregroundStyle(.secondary) }
        } header: {
            Text("Subscription")
        } footer: {
            Text("Billed by Apple through your Apple ID. Cancel any time in Settings > Apple ID > Subscriptions.")
        }
    }
}
