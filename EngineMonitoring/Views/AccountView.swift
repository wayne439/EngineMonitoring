import SwiftUI
import AuthenticationServices

/// ACCOUNT: Sign in with Apple, cloud sync status, sign out and account deletion.
struct AccountView: View {
    @EnvironmentObject private var cloud: CloudStore
    @EnvironmentObject private var aircraft: AircraftProfileStore
    @EnvironmentObject private var logs: FlightLogStore
    @State private var nonce = ""
    @State private var confirmDelete = false
    @State private var restoreOffer: AircraftProfile?

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

            if let status = cloud.status {
                Section { Text(status).foregroundStyle(.secondary) }
            }
            if let error = cloud.lastError {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }

            Section {
                Text("Engine Monitoring is advisory only. It is not FAA-approved and never replaces your POH/AFM, your engine monitor or your A&P.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("ACCOUNT")
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

    private var signInSection: some View {
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
            Text("Sign In")
        } footer: {
            Text("Signing in stores your aircraft profile and engine logs in your own private cloud account, so they are backed up and available on a new iPad.")
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

        Section {
            Button("Sign out") { cloud.signOut() }
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
