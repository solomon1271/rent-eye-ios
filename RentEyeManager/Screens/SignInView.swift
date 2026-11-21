import SwiftUI

struct SignInView: View {
    @Environment(AppState.self) private var app
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var challengeId: String?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var showServer = false
    @State private var serverAddress = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    TibebBand(height: 8).clipShape(Capsule()).frame(width: 96)
                    Text("Rent Eye")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Manage your buildings, leases and rent from your phone.")
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.top, 48)

                VStack(alignment: .leading, spacing: 14) {
                    if let challengeId {
                        Text("Enter the 6-digit code we emailed to \(email).")
                            .foregroundStyle(Theme.ink)
                        TextField("Code", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .font(.title2.monospacedDigit())
                            .fieldStyle()
                        Button {
                            Task { await verify(challengeId) }
                        } label: {
                            primaryLabel("Verify and sign in")
                        }
                        .disabled(code.count < 6 || isWorking)
                        Button("Use a different account") {
                            self.challengeId = nil
                            code = ""
                            errorMessage = nil
                        }
                        .foregroundStyle(Theme.brand)
                    } else {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .fieldStyle()
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .fieldStyle()
                        Button {
                            Task { await signIn() }
                        } label: {
                            primaryLabel("Sign in")
                        }
                        .disabled(email.isEmpty || password.isEmpty || isWorking)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(Theme.danger)
                    }
                    if isWorking {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Connecting… the server can take up to a minute to wake up.")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(20)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))

                Button {
                    serverAddress = app.serverAddress
                    showServer = true
                } label: {
                    Label("Server: \(app.serverAddress)", systemImage: "server.rack")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(24)
        }
        .background(Theme.brandDeep.ignoresSafeArea())
        .alert("Server address", isPresented: $showServer) {
            TextField("https://…", text: $serverAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Save") { app.setServerAddress(serverAddress) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Use http://localhost:5050 for the backend running on this Mac, or your Render address.")
        }
    }

    private func primaryLabel(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(Theme.brand, in: RoundedRectangle(cornerRadius: 12))
    }

    private func signIn() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            challengeId = try await app.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            password = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verify(_ challengeId: String) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await app.verifyCode(challengeId: challengeId, code: code)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension View {
    func fieldStyle() -> some View {
        padding(14)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xC6D1CA)))
    }
}
