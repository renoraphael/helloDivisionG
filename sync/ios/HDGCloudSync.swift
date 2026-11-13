import Foundation
import SwiftUI
import Observation

@MainActor @Observable
final class HDGCloudSession {
    var authorized = false
    var busy = false
    var message = "Sign in with an approved Division G officer account."
    var revision = 0
    var latestRevision = 0
    var email = ""
    private var accessToken = ""
    private var refreshToken = ""
    private var expiresAt = Date.distantPast
    private let endpoint = "https://bhbgusdxqbjwsdlzhurb.supabase.co"
    private let publishableKey = "sb_publishable_73Y-5z5ao1d97jUibxC97g_AMmmaiXh"

    private func request(_ path: String, body: [String: Any]? = nil, authenticated: Bool = true) async throws -> Any {
        if authenticated && expiresAt < Date().addingTimeInterval(60) { try await refreshSession() }
        guard let url = URL(string: endpoint + path) else { throw cloudError("Invalid server URL.") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated { request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (bytes, response) = try await URLSession.shared.data(for: request)
        let object = (try? JSONSerialization.jsonObject(with: bytes)) ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 || status == 403 { authorized = false }
            let details = object as? [String: Any] ?? [:]
            throw cloudError(details["msg"] as? String ?? details["message"] as? String ?? details["error_description"] as? String ?? "Connection failed (\(status)).")
        }
        return object
    }

    private func cloudError(_ message: String) -> NSError {
        NSError(domain: "HelloDivisionG.Cloud", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func acceptSession(_ object: Any) throws {
        guard let value = object as? [String: Any], let token = value["access_token"] as? String,
              let refresh = value["refresh_token"] as? String else { throw cloudError("Could not establish a session.") }
        accessToken = token; refreshToken = refresh
        expiresAt = Date().addingTimeInterval(value["expires_in"] as? Double ?? 3600)
    }
    private func refreshSession() async throws {
        guard !refreshToken.isEmpty else { throw cloudError("Please sign in again.") }
        try acceptSession(await request("/auth/v1/token?grant_type=refresh_token", body: ["refresh_token": refreshToken], authenticated: false))
    }
    func signIn(email: String, password: String, repository: AppRepository) async {
        busy = true; defer { busy = false }
        do {
            let value = try await request("/auth/v1/token?grant_type=password", body: ["email": email, "password": password], authenticated: false)
            try acceptSession(value); self.email = email
            try await pull(repository: repository)
            authorized = true
        } catch { message = error.localizedDescription; authorized = false }
    }
    private func pull(repository: AppRepository) async throws {
        guard let rows = try await request("/rest/v1/hdg_sync_state?division_code=eq.G&select=revision,payload") as? [[String: Any]],
              let row = rows.first, var payload = row["payload"] as? [String: Any] else {
            throw cloudError("Your login is not approved for Division G yet.")
        }
        payload["ui"] = [:] as [String: String]
        let envelope: [String: Any] = ["format": "hello-division-dashboard", "schemaVersion": 1, "data": payload]
        let bytes = try JSONSerialization.data(withJSONObject: envelope)
        let preview = try repository.stageImport(bytes, filename: "Supabase authoritative web snapshot.json")
        // A recovery copy is required before any phone data can be replaced.
        try repository.preserveBeforeCloudRefresh()
        try repository.commit(preview, mode: .replace)
        revision = (row["revision"] as? NSNumber)?.intValue ?? 0
        latestRevision = revision
        message = "Downloaded web revision \(revision). Phone edits stay on this phone and are never uploaded. A recovery copy is kept before every refresh."
    }
    func refresh(repository: AppRepository) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { try await pull(repository: repository) } catch { message = error.localizedDescription }
    }
    func checkAccess() async {
        guard authorized && !busy else { return }
        do {
            guard let rows = try await request("/rest/v1/hdg_sync_state?division_code=eq.G&select=revision") as? [[String: Any]], let row = rows.first else {
                authorized = false; message = "Officer approval is required."; return
            }
            latestRevision = (row["revision"] as? NSNumber)?.intValue ?? revision
        } catch { message = error.localizedDescription }
    }
    func signOut() {
        authorized = false; accessToken = ""; refreshToken = ""; expiresAt = .distantPast
        message = "Signed out. Sign in to access Division G data."
    }
}

struct HDGSyncSignIn: View {
    let repository: AppRepository
    @Bindable var cloud: HDGCloudSession
    @State private var email = ""
    @State private var password = ""
    var body: some View {
        Form {
            Section("Approved officer sign in") {
                TextField("Email", text: $email).textContentType(.username).autocorrectionDisabled()
                SecureField("Password", text: $password).textContentType(.password)
                Button(cloud.busy ? "Connecting…" : "Sign in and download web data") {
                    Task { let input = password; password = ""; await cloud.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: input, repository: repository) }
                }.disabled(cloud.busy || email.isEmpty || password.isEmpty)
            }
            Section {
                Text(cloud.message)
                Text("Create and confirm your login on the website first. Your local preview profile does not grant access.")
                Text("The website is authoritative. This iPhone connection downloads only; it never uploads the phone database.")
            }
        }.navigationTitle("Hello Division G")
    }
}

struct HDGSyncSettings: View {
    let repository: AppRepository
    @Bindable var cloud: HDGCloudSession
    @State private var confirmRefresh = false
    var body: some View {
        Form {
            Section("Shared database") {
                Text(cloud.email)
                Text("Web revision on this phone: \(cloud.revision)")
                if cloud.latestRevision > cloud.revision { Text("A newer web revision is available.").foregroundStyle(.orange) }
                Text(cloud.message)
                Button(cloud.busy ? "Downloading…" : "Refresh from website") { confirmRefresh = true }.disabled(cloud.busy)
            }
            Section {
                Text("Refreshing replaces this phone's working copy with authoritative web data after saving a recovery backup. Phone edits are not uploaded.")
                Button("Sign out") { cloud.signOut() }
            }
        }
        .navigationTitle("Database sync")
        .confirmationDialog("Load the latest web data? Current phone data will be kept in a local recovery backup.", isPresented: $confirmRefresh, titleVisibility: .visible) {
            Button("Back up phone data and refresh") { Task { await cloud.refresh(repository: repository) } }
        }
    }
}
