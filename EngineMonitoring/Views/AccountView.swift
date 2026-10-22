import SwiftUI
import AuthenticationServices

/// ACCOUNT: email sign-in, cloud sync status, sign out and account deletion.
struct AccountView: View {
    @EnvironmentObject private var cloud: CloudStore
    @EnvironmentObject private var aircraft: AircraftProfileStore
    @EnvironmentObject private var logs: FlightLogStore
    @State private var nonce = ""
    @State private var confirmDelete = false
    @State private var restoreOffer: AircraftProfile?
    @AppStorage("EM.exploreWithoutAccount") private var exploring = false
    @State private var showPaywall = false
    @State private var showManage = false
    @State private var isAdmin = false

    var body: some View {
        List {
            if !cloud.isConfigured {
                Section {
                    Label("Cloud storage is not set up in this build. Everything stays on this iPad.", systemImage: "icloud.slash")
                } footer: {
                    Text("Developer: add the Supabase project URL and anon key to Info.plist (EMSupabaseURL, EMSupabaseAnonKey).")
                }
            } else if let session = cloud.session {
                signedIn(session)
            } else {
                signInSection
            }

            SubscriptionSection(showPaywall: $showPaywall, showManage: $showManage)

            if let status = cloud.status {
                Section { Text(status).foregroundStyle(.secondary) }
            }
            if let error = cloud.lastError {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }

            Section {
                NavigationLink("Acknowledgements") { AcknowledgementsView() }
                Text("Engine Pulse is advisory only. It is not FAA-approved and never replaces your POH/AFM, your engine monitor or your A&P.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("\u{00A9} 2026 Engine Pulse LLC. All rights reserved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("ACCOUNT")
        .task(id: cloud.session?.userID) { isAdmin = await cloud.checkAdmin() }
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PaywallView() }
        }
        .manageSubscriptionsSheet(isPresented: $showManage)
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account and cloud data", role: .destructive) {
                Task { _ = await cloud.deleteAccount() }
            }
        } message: {
            Text("This permanently deletes your cloud account, your aircraft and every uploaded log. Data on this iPad is not deleted.")
        }
        .alert("Restore your aircraft?", isPresented: Binding(get: { restoreOffer != nil }, set: { if !$0 { restoreOffer = nil } })) {
            Button("Restore") {
                if let p = restoreOffer { aircraft.profile = p }
                restoreOffer = nil
            }
            Button("Keep this iPad's profile", role: .cancel) { restoreOffer = nil }
        } message: {
            Text("Your account already has \(restoreOffer?.displayName ?? "an aircraft") saved. Use it on this iPad?")
        }
    }

    @ViewBuilder
    private var signInSection: some View {
        Section {
            NavigationLink {
                LoginView()
            } label: {
                Label("Log in with email", systemImage: "envelope.fill").font(.headline)
            }
            NavigationLink {
                RegisterView()
            } label: {
                Label("Register a new account", systemImage: "person.badge.plus")
            }
        } header: {
            Text("Log In")
        } footer: {
            Text("Use the same email and password on every iPad and iPhone, and on the upload website.")
        }
        if AppleSignIn.enabled {
        Section {
            SignInWithAppleButton(.signIn) { request in
                nonce = CloudAPI.randomNonce()
                request.requestedScopes = [.email]
                request.nonce = CloudAPI.sha256(nonce)
            } onCompletion: { result in
                switch result {
                case .success(let auth):
                    guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                          let tokenData = credential.identityToken,
                          let idToken = String(data: tokenData, encoding: .utf8) else {
                        cloud.lastError = "Apple did not return a sign-in token."
                        return
                    }
                    let raw = nonce
                    Task {
                        await cloud.signIn(idToken: idToken, nonce: raw)
                        await offerRestore()
                        await cloud.sync(profile: aircraft.profile, logs: logs)
                    }
                case .failure(let error):
                    if (error as? ASAuthorizationError)?.code != .canceled {
                        cloud.lastError = "Sign in with Apple failed: \(error.localizedDescription)"
                    }
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
        } header: {
            Text("Or Sign In with Apple")
        } footer: {
            Text("Only if you registered with Apple. Choose \"Share My Email\" so it joins your email account; \"Hide My Email\" creates a separate, empty account.")
        }
        }
    }

    @ViewBuilder
    private func signedIn(_ session: CloudSession) -> some View {
        Section {
            LabeledContent("Signed in", value: session.email ?? "Apple ID (email hidden)")
            LabeledContent("Aircraft", value: aircraft.profile.displayName)
            LabeledContent("Logs uploaded", value: "\(cloud.uploadedLogs.count) of \(logs.entries.count)")
            if let last = cloud.lastSync {
                LabeledContent("Last sync", value: last.formatted(date: .abbreviated, time: .shortened))
            }
            Button {
                Task { await cloud.sync(profile: aircraft.profile, logs: logs) }
            } label: {
                if cloud.isBusy {
                    HStack { ProgressView(); Text("Syncing…") }
                } else {
                    Label("Sync now", systemImage: "arrow.triangle.2.circlepath.icloud")
                }
            }
            .disabled(cloud.isBusy)
        } header: {
            Text("Cloud Account")
        } footer: {
            Text("New logs and profile changes upload automatically while you are signed in.")
        }

        AircraftOwnershipSection()

        if isAdmin {
            Section {
                NavigationLink {
                    AdminTestersView()
                } label: {
                    Label("Beta testers", systemImage: "person.3")
                }
            } header: {
                Text("Admin")
            } footer: {
                Text("Who has signed in, set up an aircraft and uploaded data. Only admin accounts see this.")
            }
        }

        Section {
            Button("Sign out") {
                cloud.signOut()
                exploring = false
            }
            Button("Delete account…", role: .destructive) { confirmDelete = true }
                .disabled(cloud.isBusy)
        }
    }

    /// After sign-in on a fresh iPad, offer the profile already saved in the account.
    private func offerRestore() async {
        guard aircraft.profile.tailNumber.trimmingCharacters(in: .whitespaces).isEmpty,
              let saved = await cloud.cloudProfile(),
              !saved.tailNumber.isEmpty else { return }
        restoreOffer = saved
    }
}
